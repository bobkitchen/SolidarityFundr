//
//  StatementIntents.swift
//  SolidarityFundr
//
//  Created on 7/25/25.
//

import AppIntents
import CoreData
import SwiftUI

// MARK: - Send Statement Intent

struct SendStatementIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Member Statement"
    static var description = IntentDescription("Generate and send a member statement via WhatsApp")
    
    @Parameter(title: "Member Name")
    var memberName: String
    
    @Parameter(title: "Start Date", default: nil)
    var startDate: Date?
    
    @Parameter(title: "End Date", default: Date())
    var endDate: Date
    
    static var parameterSummary: some ParameterSummary {
        Summary("Send statement for \(\.$memberName)") {
            \.$startDate
            \.$endDate
        }
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        // Get the managed object context
        let context = PersistenceController.shared.container.viewContext
        
        // Find the member
        let request: NSFetchRequest<Member> = Member.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", memberName)
        request.fetchLimit = 1
        
        guard let member = try context.fetch(request).first else {
            throw IntentError.memberNotFound
        }
        
        // Generate the PDF
        let pdfGenerator = PDFGenerator()
        let actualStartDate = startDate ?? Calendar.current.date(byAdding: .month, value: -1, to: endDate) ?? endDate
        
        let pdfURL = try await pdfGenerator.generateReport(
            type: .memberStatement,
            dataManager: DataManager.shared,
            member: member,
            startDate: actualStartDate,
            endDate: endDate
        )
        
        // Read the PDF data
        let pdfData = try Data(contentsOf: pdfURL)
        
        // Record the generation
        try await StatementService.shared.recordWhatsAppShare(for: member, pdfData: pdfData)
        
        // Open WhatsApp with the statement
        await MainActor.run {
            if let window = NSApp.windows.first,
               let contentView = window.contentView {
                WhatsAppSharingService.shared.shareStatement(
                    pdfData: pdfData,
                    for: member,
                    in: contentView
                )
            }
        }
        
        // Clean up temporary file
        try? FileManager.default.removeItem(at: pdfURL)
        
        return .result(value: true)
    }
}

// MARK: - Generate All Statements Intent

struct GenerateAllStatementsIntent: AppIntent {
    static var title: LocalizedStringResource = "Generate All Monthly Statements"
    static var description = IntentDescription("Generate statements for all active members")
    
    @Parameter(title: "Statement Month", default: Date())
    var statementMonth: Date
    
    static var parameterSummary: some ParameterSummary {
        Summary("Generate statements for \(\.$statementMonth)")
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let statements = try await StatementService.shared.generateAllStatements()
        
        // Save statements to a folder
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let statementsFolder = documentsPath.appendingPathComponent("SolidarityFund/Statements/\(DateHelper.formatFileDate(statementMonth))")
        
        try FileManager.default.createDirectory(at: statementsFolder, withIntermediateDirectories: true)
        
        for (member, pdfData) in statements {
            let fileName = "\(member.name?.replacingOccurrences(of: " ", with: "_") ?? "Member")_Statement_\(DateHelper.formatFileDate(statementMonth)).pdf"
            let fileURL = statementsFolder.appendingPathComponent(fileName)
            try pdfData.write(to: fileURL)
        }
        
        // Open the folder in Finder
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: statementsFolder.path)
        
        return .result(value: statements.count)
    }
}

// MARK: - Get Member Balance Intent

struct GetMemberBalanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Member Balance"
    static var description = IntentDescription("Get a member's contribution balance and loan status")
    
    @Parameter(title: "Member Name")
    var memberName: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get balance for \(\.$memberName)")
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let context = PersistenceController.shared.container.viewContext
        
        // Find the member
        let request: NSFetchRequest<Member> = Member.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", memberName)
        request.fetchLimit = 1
        
        guard let member = try context.fetch(request).first else {
            throw IntentError.memberNotFound
        }
        
        let balance = CurrencyFormatter.shared.format(member.totalContributions)
        let loanBalance = member.hasActiveLoans ? CurrencyFormatter.shared.format(member.totalActiveLoanBalance) : "No active loans"
        
        let result = """
        \(member.name ?? "Member") Balance:
        Total Contributions: \(balance)
        Loan Balance: \(loanBalance)
        Net Position: \(CurrencyFormatter.shared.format(member.totalContributions - member.totalActiveLoanBalance))
        """
        
        return .result(value: result)
    }
}

// MARK: - App Shortcuts Provider

struct SolidarityFundShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendStatementIntent(),
            phrases: [
                "Send statement in \(.applicationName)",
                "Generate statement in \(.applicationName)",
                "WhatsApp statement in \(.applicationName)"
            ],
            shortTitle: "Send Statement",
            systemImageName: "paperplane.fill"
        )
        
        AppShortcut(
            intent: GenerateAllStatementsIntent(),
            phrases: [
                "Generate all statements in \(.applicationName)",
                "Create monthly statements in \(.applicationName)",
                "Batch generate statements in \(.applicationName)"
            ],
            shortTitle: "Generate All Statements",
            systemImageName: "doc.on.doc.fill"
        )
        
        AppShortcut(
            intent: GetMemberBalanceIntent(),
            phrases: [
                "Get balance in \(.applicationName)",
                "Check contributions in \(.applicationName)",
                "Show loan status in \(.applicationName)"
            ],
            shortTitle: "Get Balance",
            systemImageName: "dollarsign.circle.fill"
        )
    }
}

// MARK: - Intent Errors

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case memberNotFound
    case statementGenerationFailed
    case whatsAppNotInstalled
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .memberNotFound:
            return "Member not found. Please check the member name."
        case .statementGenerationFailed:
            return "Failed to generate statement. Please try again."
        case .whatsAppNotInstalled:
            return "WhatsApp Desktop is not installed."
        }
    }
}

