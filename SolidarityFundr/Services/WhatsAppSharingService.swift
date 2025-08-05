import Foundation
import AppKit
import CoreData

// MARK: - WhatsApp Sharing Service

class WhatsAppSharingService: NSObject {
    static let shared = WhatsAppSharingService()
    
    override private init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Check if WhatsApp desktop is installed
    func isWhatsAppAvailable() -> Bool {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp") {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return false
    }
    
    /// Share a statement PDF via WhatsApp
    func shareStatement(pdfData: Data, for member: Member, in view: NSView) {
        // Save PDF temporarily
        let tempURL = savePDFTemporarily(pdfData, memberName: member.name ?? "Member")
        
        // Create pre-formatted message
        let message = createStatementMessage(for: member)
        
        // Check if WhatsApp is installed
        if isWhatsAppAvailable() {
            // Try to open WhatsApp with the message
            if let phoneNumber = member.whatsAppFormattedPhone {
                openWhatsAppWithMessage(phoneNumber: phoneNumber, message: message, pdfURL: tempURL)
            } else {
                // No phone number, just save PDF and show instructions
                showPDFLocationAlert(pdfURL: tempURL, memberName: member.name ?? "Member")
            }
        } else {
            // WhatsApp not installed, show alternative options
            showWhatsAppNotInstalledAlert(pdfURL: tempURL, in: view)
        }
    }
    
    /// Share multiple statements (saves to folder and opens in Finder)
    func shareBatchStatements(_ statements: [(member: Member, pdfData: Data)], in view: NSView) {
        // Create a folder for all statements
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let statementsFolder = documentsPath.appendingPathComponent("SolidarityFund/WhatsApp_Statements_\(DateHelper.formatFileDate(Date()))")
        
        do {
            try FileManager.default.createDirectory(at: statementsFolder, withIntermediateDirectories: true)
            
            // Save all PDFs to the folder
            for statement in statements {
                let fileName = "\(statement.member.name?.replacingOccurrences(of: " ", with: "_") ?? "Member")_Statement_\(DateHelper.formatFileDate(Date())).pdf"
                let fileURL = statementsFolder.appendingPathComponent(fileName)
                try statement.pdfData.write(to: fileURL)
            }
            
            // Open the folder in Finder
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: statementsFolder.path)
            
            // Show instructions
            showBatchInstructions(count: statements.count, folderPath: statementsFolder.path)
            
        } catch {
            print("Error creating statements folder: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func savePDFTemporarily(_ pdfData: Data, memberName: String) -> URL {
        let fileName = "\(memberName.replacingOccurrences(of: " ", with: "_"))_Statement_\(DateHelper.formatFileDate(Date())).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try pdfData.write(to: tempURL)
        } catch {
            print("Error saving PDF temporarily: \(error)")
        }
        
        // Schedule cleanup after 1 hour
        DispatchQueue.main.asyncAfter(deadline: .now() + 3600) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        return tempURL
    }
    
    private func createStatementMessage(for member: Member) -> String {
        let currentMonth = DateHelper.formatMonth(Date())
        let fundSettings = FundSettings.fetchOrCreate(in: PersistenceController.shared.container.viewContext)
        
        var message = """
        Dear \(member.name ?? "Member"),
        
        Please find attached your Parachichi House Solidarity Fund statement for \(currentMonth).
        
        Summary:
        • Total Contributions: \(CurrencyFormatter.shared.format(member.totalContributions))
        """
        
        if member.hasActiveLoans {
            message += "\n• Active Loan Balance: \(CurrencyFormatter.shared.format(member.totalActiveLoanBalance))"
        }
        
        message += """
        
        
        Fund Status:
        • Total Fund Balance: \(CurrencyFormatter.shared.format(fundSettings.calculateFundBalance()))
        • Active Loans: \(CurrencyFormatter.shared.format(FundCalculator.shared.generateFundSummary().totalActiveLoans))
        
        Thank you for your continued participation in the Solidarity Fund.
        
        Best regards,
        Parachichi House Management
        """
        
        return message
    }
    
    private func openWhatsAppWithMessage(phoneNumber: String, message: String, pdfURL: URL) {
        // First, copy the message to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)
        
        // Save PDF location to a more permanent location
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let permanentFolder = documentsPath.appendingPathComponent("SolidarityFund/WhatsApp_Statements")
        
        do {
            try FileManager.default.createDirectory(at: permanentFolder, withIntermediateDirectories: true)
            let fileName = pdfURL.lastPathComponent
            let permanentURL = permanentFolder.appendingPathComponent(fileName)
            
            // Copy to permanent location
            try? FileManager.default.removeItem(at: permanentURL) // Remove if exists
            try FileManager.default.copyItem(at: pdfURL, to: permanentURL)
            
            // Show simple alert without trying to open WhatsApp
            showManualWhatsAppInstructions(pdfURL: permanentURL, phoneNumber: phoneNumber)
            
        } catch {
            // Fall back to temporary location
            showPDFLocationAlert(pdfURL: pdfURL, memberName: "")
        }
    }
    
    private func showManualWhatsAppInstructions(pdfURL: URL, phoneNumber: String) {
        let alert = NSAlert()
        alert.messageText = "WhatsApp Statement Ready"
        alert.informativeText = """
        The statement has been prepared. To send via WhatsApp:
        
        1. Open WhatsApp manually
        2. Find or add contact: \(phoneNumber)
        3. The message has been copied - paste it (⌘V)
        4. Attach the PDF from:
        
        \(pdfURL.path)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Show PDF in Finder")
        alert.addButton(withTitle: "OK")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.selectFile(pdfURL.path, inFileViewerRootedAtPath: pdfURL.deletingLastPathComponent().path)
        }
    }
    
    private func showWhatsAppInstructions(pdfURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Complete WhatsApp Message"
        alert.informativeText = """
        WhatsApp has been opened. To complete sending the statement:
        
        1. The message has been copied to your clipboard - paste it (⌘V)
        2. Click the paperclip icon to attach a file
        3. Select 'Document'
        4. Navigate to the PDF location shown below
        5. Select and send the PDF
        
        PDF Location: \(pdfURL.path)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Show PDF in Finder")
        alert.addButton(withTitle: "OK")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.selectFile(pdfURL.path, inFileViewerRootedAtPath: pdfURL.deletingLastPathComponent().path)
        }
    }
    
    private func showPDFLocationAlert(pdfURL: URL, memberName: String) {
        let alert = NSAlert()
        alert.messageText = "Statement Ready"
        alert.informativeText = """
        The statement PDF has been saved to:
        
        \(pdfURL.path)
        
        You can now:
        1. Open WhatsApp manually
        2. Select the contact
        3. Attach this PDF as a document
        4. Send with the pre-formatted message
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.selectFile(pdfURL.path, inFileViewerRootedAtPath: pdfURL.deletingLastPathComponent().path)
        }
    }
    
    private func showWhatsAppNotInstalledAlert(pdfURL: URL, in view: NSView) {
        let alert = NSAlert()
        alert.messageText = "WhatsApp Not Found"
        alert.informativeText = """
        WhatsApp Desktop doesn't appear to be installed on this Mac.
        
        The statement PDF has been saved and you can:
        1. Install WhatsApp Desktop from whatsapp.com
        2. Use the web version at web.whatsapp.com
        3. Share the PDF using another method
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Show PDF")
        alert.addButton(withTitle: "Share via Other App")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.selectFile(pdfURL.path, inFileViewerRootedAtPath: pdfURL.deletingLastPathComponent().path)
        case .alertSecondButtonReturn:
            showSharingPicker(items: [pdfURL], in: view)
        default:
            break
        }
    }
    
    private func showBatchInstructions(count: Int, folderPath: String) {
        let alert = NSAlert()
        alert.messageText = "Statements Ready for WhatsApp"
        alert.informativeText = """
        \(count) statements have been saved to:
        
        \(folderPath)
        
        To send via WhatsApp:
        1. Open WhatsApp Desktop
        2. Select a contact
        3. Click the paperclip icon
        4. Choose 'Document'
        5. Navigate to the folder above
        6. Select and send the appropriate PDF
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showSharingPicker(items: [Any], in view: NSView) {
        let picker = NSSharingServicePicker(items: items)
        picker.delegate = self
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

// MARK: - NSSharingServicePickerDelegate

extension WhatsAppSharingService: NSSharingServicePickerDelegate {
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
        return proposedServices
    }
    
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if let service = service {
            print("User selected sharing service: \(service.title)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let statementSharedViaWhatsApp = Notification.Name("statementSharedViaWhatsApp")
}

// MARK: - Helper Extensions

extension Member {
    /// Check if member can receive WhatsApp messages
    var canReceiveWhatsApp: Bool {
        return phoneNumber != nil && !phoneNumber!.isEmpty && memberStatus == .active
    }
    
    /// Format phone number for WhatsApp
    var whatsAppFormattedPhone: String? {
        guard let phone = phoneNumber else { return nil }
        
        // Remove any non-numeric characters
        let cleaned = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // Add country code if not present
        if cleaned.hasPrefix("254") {
            return cleaned
        } else if cleaned.hasPrefix("0") {
            return "254" + String(cleaned.dropFirst())
        } else {
            return "254" + cleaned
        }
    }
}