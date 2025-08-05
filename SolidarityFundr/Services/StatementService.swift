import Foundation
import CoreData

// MARK: - Statement Service

class StatementService: ObservableObject {
    static let shared = StatementService()
    
    private let pdfGenerator: PDFGenerator
    private let context: NSManagedObjectContext
    
    @Published var isProcessing = false
    @Published var processedCount = 0
    @Published var totalCount = 0
    @Published var errors: [StatementError] = []
    @Published var generatedStatements: [(member: Member, pdfData: Data)] = []
    
    private init() {
        self.context = PersistenceController.shared.container.viewContext
        self.pdfGenerator = PDFGenerator()
    }
    
    // MARK: - Public Methods
    
    func generateMonthlyStatements() async throws -> [(member: Member, pdfData: Data)] {
        // Check if statements should be generated today
        let fundSettings = FundSettings.fetchOrCreate(in: context)
        guard fundSettings.isTimeToSendStatements else {
            throw StatementError.notScheduledToday
        }
        
        // Get all active members
        let members = try await fetchEligibleMembers()
        
        await MainActor.run {
            self.totalCount = members.count
            self.processedCount = 0
            self.isProcessing = true
            self.errors = []
            self.generatedStatements.removeAll()
        }
        
        var statements: [(member: Member, pdfData: Data)] = []
        
        // Generate PDFs for all members
        for member in members {
            do {
                let pdfData = try await generatePDF(for: member)
                statements.append((member: member, pdfData: pdfData))
                
                await MainActor.run {
                    self.processedCount += 1
                }
            } catch {
                await MainActor.run {
                    self.errors.append(StatementError.pdfGenerationFailed(member.name ?? "Unknown", error))
                }
            }
        }
        
        await MainActor.run {
            self.generatedStatements = statements
            self.isProcessing = false
        }
        
        // Update last statement generated date
        fundSettings.updatedAt = Date()
        try context.save()
        
        return statements
    }
    
    func generateStatementForMember(_ member: Member) async throws -> Data {
        guard member.canReceiveWhatsApp else {
            throw StatementError.memberNotEligible(member.name ?? "Unknown")
        }
        
        await MainActor.run {
            self.isProcessing = true
            self.totalCount = 1
            self.processedCount = 0
        }
        
        do {
            // Generate PDF
            let pdfData = try await generatePDF(for: member)
            
            // Store for later sharing
            await MainActor.run {
                self.generatedStatements.append((member: member, pdfData: pdfData))
                self.processedCount = 1
                self.isProcessing = false
            }
            
            return pdfData
        } catch {
            await MainActor.run {
                self.errors.append(StatementError.processingFailed(member.name ?? "Unknown", error))
                self.isProcessing = false
            }
            throw error
        }
    }
    
    func generateAllStatements() async throws -> [(member: Member, pdfData: Data)] {
        let members = try await fetchEligibleMembers()
        var statements: [(member: Member, pdfData: Data)] = []
        
        await MainActor.run {
            self.isProcessing = true
            self.totalCount = members.count
            self.processedCount = 0
            self.generatedStatements.removeAll()
            self.errors.removeAll()
        }
        
        for member in members {
            do {
                let pdfData = try await generatePDF(for: member)
                statements.append((member: member, pdfData: pdfData))
                
                await MainActor.run {
                    self.processedCount += 1
                }
            } catch {
                await MainActor.run {
                    self.errors.append(StatementError.processingFailed(member.name ?? "Unknown", error))
                }
            }
        }
        
        await MainActor.run {
            self.generatedStatements = statements
            self.isProcessing = false
        }
        
        return statements
    }
    
    func testStatementForMember(_ member: Member) async throws -> Data {
        guard member.canReceiveWhatsApp else {
            throw StatementError.memberNotEligible(member.name ?? "Unknown")
        }
        
        // Generate test PDF with sample data
        let pdfData = try await generatePDF(for: member)
        
        // Store for later sharing
        await MainActor.run {
            self.generatedStatements = [(member: member, pdfData: pdfData)]
        }
        
        return pdfData
    }
    
    // MARK: - Private Methods
    
    private func fetchEligibleMembers() async throws -> [Member] {
        let request: NSFetchRequest<Member> = Member.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@ AND phoneNumber != nil", MemberStatus.active.rawValue)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Member.name, ascending: true)]
        
        return try context.fetch(request)
    }
    
    // This method is no longer needed - removed
    
    private func generatePDF(for member: Member) async throws -> Data {
        // Generate member statement PDF
        let url = try await pdfGenerator.generateReport(
            type: .memberStatement,
            dataManager: DataManager.shared,
            member: member,
            startDate: Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date(),
            endDate: Date()
        )
        
        // Read the PDF data from the URL
        return try Data(contentsOf: url)
    }
    
    func recordWhatsAppShare(for member: Member, pdfData: Data) async throws {
        // Simply update the member's last statement sent date
        // Don't create NotificationHistory as it may have issues with Core Data relationships
        await MainActor.run {
            member.lastStatementSentDate = Date()
            
            do {
                try context.save()
            } catch {
                print("Error saving WhatsApp share record: \(error)")
                // Don't throw - this is not critical
            }
        }
    }
    
    // Delivery status mapping no longer needed - removed
}

// MARK: - Statement Scheduler

class StatementScheduler {
    static let shared = StatementScheduler()
    private var timer: Timer?
    
    private init() {}
    
    func startScheduler() {
        // Check every hour if statements should be sent
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task {
                await self.checkAndSendStatements()
            }
        }
        
        // Also check immediately
        Task {
            await checkAndSendStatements()
        }
    }
    
    func stopScheduler() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkAndSendStatements() async {
        let context = PersistenceController.shared.container.viewContext
        let fundSettings = FundSettings.fetchOrCreate(in: context)
        
        // Check if it's time to send statements
        guard fundSettings.isTimeToSendStatements else { return }
        
        // Check if we haven't already sent statements today
        let calendar = Calendar.current
        if let lastSent = getLastStatementSentDate(),
           calendar.isDateInToday(lastSent) {
            return
        }
        
        // Send statements
        do {
            // Generate statements - sharing will be done manually via WhatsApp
            _ = try await StatementService.shared.generateMonthlyStatements()
            saveLastStatementSentDate(Date())
        } catch {
            print("Failed to send monthly statements: \(error)")
        }
    }
    
    private func getLastStatementSentDate() -> Date? {
        return UserDefaults.standard.object(forKey: "LastStatementSentDate") as? Date
    }
    
    private func saveLastStatementSentDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: "LastStatementSentDate")
    }
}

// MARK: - Statement Errors

enum StatementError: LocalizedError {
    case notScheduledToday
    case memberNotEligible(String)
    case testModeDisabled
    case pdfGenerationFailed(String, Error)
    case uploadFailed(String, Error)
    case urlCreationFailed(String, Error)
    case messageSendFailed(String, Error)
    case processingFailed(String, Error)
    
    var errorDescription: String? {
        switch self {
        case .notScheduledToday:
            return "Statements are not scheduled to be sent today"
        case .memberNotEligible(let name):
            return "Member \(name) is not eligible for statements (no phone number)"
        case .testModeDisabled:
            return "Test mode is disabled"
        case .pdfGenerationFailed(let name, let error):
            return "Failed to generate PDF for \(name): \(error.localizedDescription)"
        case .uploadFailed(let name, let error):
            return "Failed to upload PDF for \(name): \(error.localizedDescription)"
        case .urlCreationFailed(let name, let error):
            return "Failed to create short URL for \(name): \(error.localizedDescription)"
        case .messageSendFailed(let name, let error):
            return "Failed to send message to \(name): \(error.localizedDescription)"
        case .processingFailed(let name, let error):
            return "Failed to process statement for \(name): \(error.localizedDescription)"
        }
    }
}

// MARK: - Array Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}