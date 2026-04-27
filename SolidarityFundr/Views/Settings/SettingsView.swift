//
//  SettingsView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI
import UniformTypeIdentifiers
import LocalAuthentication

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var syncManager = CloudKitSyncManager.shared

    // Alert states
    @State private var showingSuccessAlert = false
    @State private var successMessage = ""
    @State private var showingMessage = false
    @State private var alertMessage = ""
    @State private var showingResetConfirmation = false

    // Import/Export states
    @State private var showingImport = false
    @State private var showingExport = false

    enum SettingsTab: String, CaseIterable, Hashable {
        case general = "General"
        case messaging = "Messaging"
        case security = "Security"
        case dataSync = "Data & Sync"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .messaging: return "message"
            case .security: return "lock.shield"
            case .dataSync: return "icloud.and.arrow.up"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    var body: some View {
        // Stock macOS Settings: a TabView at the window root, each tab wrapped
        // in a Form with `.formStyle(.grouped)` so it renders with the system
        // Settings appearance (grouped GroupBox sections, proper spacing,
        // Liquid Glass on macOS 26).
        TabView {
            tab(GeneralSettingsView(dataManager: dataManager), .general)
            tab(MessagingSettingsView(dataManager: dataManager), .messaging)
            tab(SecuritySettingsTabView(), .security)
            tab(
                DataSyncSettingsView(
                    dataManager: dataManager,
                    syncManager: syncManager,
                    showingImport: $showingImport,
                    showingExport: $showingExport,
                    showingResetConfirmation: $showingResetConfirmation
                ),
                .dataSync
            )
            tab(AdvancedSettingsView(dataManager: dataManager), .advanced)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 460, idealHeight: 560)
        .alert("Success", isPresented: $showingSuccessAlert) {
            Button("OK") {}
        } message: {
            Text(successMessage)
        }
        .alert("Information", isPresented: $showingMessage) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .fileImporter(
            isPresented: $showingImport,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .fileExporter(
            isPresented: $showingExport,
            document: ExportDocument(dataManager: dataManager),
            contentType: .json,
            defaultFilename: "solidarity_fund_backup_\(Date().ISO8601Format())"
        ) { result in
            handleFileExport(result)
        }
        .confirmationDialog(
            "Reset All Data",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all members, loans, payments, and transactions. This action cannot be undone.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func tab<Content: View>(_ content: Content, _ tab: SettingsTab) -> some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .tabItem { Label(tab.rawValue, systemImage: tab.icon) }
    }

    // MARK: - Removed in stock-Settings refactor
    //
    // The previous wrapper had a custom horizontal tab bar (TabButton),
    // a search field with live results (SearchResult/performSearch), a
    // quick-actions menu in the header, and Material-backed "card" frames
    // around tab content. All of that is now provided by stock SwiftUI's
    // TabView + Form on macOS, so it's been removed.

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                let data = try Data(contentsOf: url)
                try DataImportExport.shared.importData(from: data)
                // Recalculate all balances after import to ensure correctness
                dataManager.setupFundSettings()
                dataManager.recalculateAllTransactionBalances()
                dataManager.recalculateAllMemberContributions()
                dataManager.fetchMembers()
                dataManager.fetchActiveLoans()
                dataManager.fetchRecentTransactions()
                successMessage = "Data imported successfully"
                showingSuccessAlert = true
            } catch {
                successMessage = "Import failed: \(error.localizedDescription)"
                showingSuccessAlert = true
            }
        case .failure(let error):
            successMessage = "Import failed: \(error.localizedDescription)"
            showingSuccessAlert = true
        }
    }
    
    private func handleFileExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            successMessage = "Data exported successfully"
            showingSuccessAlert = true
        case .failure(let error):
            showingSuccessAlert = true
            successMessage = "Export failed: \(error.localizedDescription)"
        }
    }
    
    private func resetAllData() {
        do {
            try DataImportExport.shared.importData(from: Data("{}".utf8))
            dataManager.fetchMembers()
            dataManager.fetchActiveLoans()
            dataManager.fetchRecentTransactions()
            dataManager.setupFundSettings()
            successMessage = "All data has been reset"
            showingSuccessAlert = true
        } catch {
            successMessage = "Reset failed: \(error.localizedDescription)"
            showingSuccessAlert = true
        }
    }
}


// MARK: - General Settings Tab

struct GeneralSettingsView: View {
    let dataManager: DataManager
    @State private var monthlyContribution: Double = 2000
    @State private var annualInterestRatePct: Double = 13
    @State private var utilizationWarningPct: Double = 60
    @State private var minimumFundBalance: Double = 50000
    @State private var bobRemainingInvestment: Double = 100000
    @State private var overrideUtilizationWarning = false
    @State private var overrideMinimumBalance = false
    @State private var allowPartialPayments = false

    var body: some View {
        Section("Fund Configuration") {
            LabeledContent("Monthly Contribution") {
                TextField("Monthly Contribution", value: $monthlyContribution, format: .number)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                Text("KSH").foregroundStyle(.secondary)
            }
            LabeledContent("Annual Interest Rate") {
                TextField("Annual Interest Rate", value: $annualInterestRatePct, format: .number)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                Text("%").foregroundStyle(.secondary)
            }
            LabeledContent("Bob's Remaining Investment") {
                TextField("Bob's Remaining Investment", value: $bobRemainingInvestment, format: .number)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                Text("KSH").foregroundStyle(.secondary)
            }
        }

        Section("Business Rules") {
            LabeledContent("Utilization Warning") {
                TextField("Utilization Warning", value: $utilizationWarningPct, format: .number)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                Text("%").foregroundStyle(.secondary)
            }
            LabeledContent("Minimum Fund Balance") {
                TextField("Minimum Fund Balance", value: $minimumFundBalance, format: .number)
                    .multilineTextAlignment(.trailing)
                    .labelsHidden()
                Text("KSH").foregroundStyle(.secondary)
            }
        }

        Section("Overrides") {
            Toggle("Override Utilization Warning", isOn: $overrideUtilizationWarning)
            Toggle("Override Minimum Balance Warning", isOn: $overrideMinimumBalance)
            Toggle("Allow Partial Loan Payments", isOn: $allowPartialPayments)

            if overrideUtilizationWarning || overrideMinimumBalance {
                Label("Overriding business rules may compromise fund stability.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        }
        .onAppear { loadSettings() }
        // Auto-save on every change — macOS Settings convention.
        .onChange(of: monthlyContribution) { saveSettings() }
        .onChange(of: annualInterestRatePct) { saveSettings() }
        .onChange(of: utilizationWarningPct) { saveSettings() }
        .onChange(of: minimumFundBalance) { saveSettings() }
        .onChange(of: bobRemainingInvestment) { saveSettings() }
    }

    private func loadSettings() {
        guard let settings = dataManager.fundSettings else { return }
        monthlyContribution = settings.monthlyContribution
        annualInterestRatePct = settings.annualInterestRate * 100
        utilizationWarningPct = settings.utilizationWarningThreshold * 100
        minimumFundBalance = settings.minimumFundBalance
        bobRemainingInvestment = settings.bobRemainingInvestment
    }

    private func saveSettings() {
        guard let settings = dataManager.fundSettings else { return }
        settings.monthlyContribution = monthlyContribution
        settings.annualInterestRate = annualInterestRatePct / 100
        settings.utilizationWarningThreshold = utilizationWarningPct / 100
        settings.minimumFundBalance = minimumFundBalance
        settings.bobRemainingInvestment = bobRemainingInvestment
        settings.updatedAt = Date()
        try? PersistenceController.shared.container.viewContext.save()
    }
}

// MARK: - Messaging Settings Tab

struct MessagingSettingsView: View {
    let dataManager: DataManager
    @State private var whatsAppStatementsEnabled = false
    @State private var statementDay = 1
    @State private var testModeEnabled = false
    @State private var testPhoneNumber = ""
    @State private var showingSuccessAlert = false
    @State private var successMessage = ""
    @State private var showingNotificationHistory = false
    @State private var isWhatsAppInstalled = false
    
    var body: some View {
            // WhatsApp Configuration
            SettingsSection(title: "WhatsApp Configuration", icon: "message.fill") {
                VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                    // Check WhatsApp Installation
                    HStack {
                        Label("WhatsApp Desktop", systemImage: "desktopcomputer")
                        Spacer()
                        if isWhatsAppInstalled {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Not Installed", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    
                    Toggle("Enable Monthly WhatsApp Statements", isOn: $whatsAppStatementsEnabled)
                        .onChange(of: whatsAppStatementsEnabled) { _, newValue in
                            if let fundSettings = dataManager.fundSettings {
                                fundSettings.smsNotificationsEnabled = newValue
                                saveSettings()
                            }
                        }
                        .disabled(!isWhatsAppInstalled)
                    
                    if whatsAppStatementsEnabled {
                        // Statement Delivery Method
                        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                            Text("Delivery Method")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("Statements will be shared via WhatsApp Desktop with PDFs attached directly")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            
            // Statement Settings
            if whatsAppStatementsEnabled {
                SettingsSection(title: "Statement Settings", icon: "calendar.badge.plus") {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                        SettingsRow(label: "Send Statements On", systemImage: "calendar") {
                            Picker("", selection: $statementDay) {
                                ForEach(1...28, id: \.self) { day in
                                    Text("Day \(day)").tag(day)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: statementDay) { _, newValue in
                                if let fundSettings = dataManager.fundSettings {
                                    fundSettings.smsStatementDay = Int16(newValue)
                                    saveSettings()
                                }
                            }
                        }
                        
                        if let fundSettings = dataManager.fundSettings,
                           let nextDate = fundSettings.getNextStatementDate() {
                            HStack {
                                Text("Next Statement Date")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(DateHelper.formatDate(nextDate))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Button {
                            sendMonthlyStatements()
                        } label: {
                            Label("Send Statements Now", systemImage: "paperplane.fill")
                        }
                        .help("Manually trigger monthly statement delivery")
                    }
                }
                
                // Testing & Monitoring
                SettingsSection(title: "Testing & Monitoring", icon: "wrench.and.screwdriver") {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                        Toggle("Enable Test Mode", isOn: $testModeEnabled)
                            .onChange(of: testModeEnabled) { _, newValue in
                                if let fundSettings = dataManager.fundSettings {
                                    fundSettings.smsTestModeEnabled = newValue
                                    saveSettings()
                                }
                            }
                        
                        if testModeEnabled {
                            HStack {
                                TextField("Test Phone Number", text: $testPhoneNumber)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button {
                                    sendTestMessage()
                                } label: {
                                    Label("Send Test", systemImage: "paperplane")
                                }
                                .disabled(testPhoneNumber.isEmpty || !PhoneNumberValidator.validate(testPhoneNumber))
                            }
                            
                            if !testPhoneNumber.isEmpty && !PhoneNumberValidator.validate(testPhoneNumber) {
                                Text("Please enter a valid Kenyan phone number")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        Button {
                            showingNotificationHistory = true
                        } label: {
                            Label("View Delivery History", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }
            
            // How It Works
            SettingsSection(title: "How WhatsApp Delivery Works", icon: "info.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("1. Statements are generated as PDF files", systemImage: "doc.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label("2. You select members to send statements to", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label("3. The macOS sharing service opens with WhatsApp pre-selected", systemImage: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label("4. PDF is attached with a pre-formatted message", systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label("5. You review and send directly in WhatsApp", systemImage: "paperplane.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Info Section
            VStack(alignment: .leading, spacing: 8) {
                Label("WhatsApp statements include the full PDF report with all transaction details", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Label("Statements can be sent individually or in batches through WhatsApp Desktop", systemImage: "desktopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            loadSettings()
            checkWhatsAppInstallation()
        }
        .alert("WhatsApp Service", isPresented: $showingSuccessAlert) {
            Button("OK") {}
        } message: {
            Text(successMessage)
        }
        .sheet(isPresented: $showingNotificationHistory) {
            NavigationStack {
                NotificationHistoryView()
            }
        }
    }
    
    private func loadSettings() {
        guard let settings = dataManager.fundSettings else { return }
        whatsAppStatementsEnabled = settings.smsNotificationsEnabled
        statementDay = Int(settings.smsStatementDay)
        testModeEnabled = settings.smsTestModeEnabled
    }
    
    private func checkWhatsAppInstallation() {
        isWhatsAppInstalled = WhatsAppSharingService.shared.isWhatsAppAvailable()
    }
    
    private func saveSettings() {
        do {
            try PersistenceController.shared.container.viewContext.save()
        } catch {
            print("Error saving SMS settings: \(error)")
        }
    }
    
    private func sendTestMessage() {
        Task {
            do {
                let context = PersistenceController.shared.container.viewContext
                let testMember = Member(context: context)
                testMember.memberID = UUID()
                testMember.name = "Test User"
                testMember.phoneNumber = testPhoneNumber
                testMember.smsOptIn = true
                testMember.totalContributions = 24000
                testMember.status = "active"
                
                let pdfData = try await StatementService.shared.testStatementForMember(testMember)
                context.rollback()
                
                await MainActor.run {
                    if let window = NSApp.windows.first,
                       let contentView = window.contentView {
                        WhatsAppSharingService.shared.shareStatement(
                            pdfData: pdfData,
                            for: testMember,
                            in: contentView
                        )
                        successMessage = "Test statement prepared for WhatsApp"
                        showingSuccessAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    successMessage = "Test message failed: \(error.localizedDescription)"
                    showingSuccessAlert = true
                }
            }
        }
    }
    
    // Balance check no longer needed for WhatsApp
    
    private func sendMonthlyStatements() {
        Task {
            do {
                let statements = try await StatementService.shared.generateMonthlyStatements()
                
                if !statements.isEmpty {
                    await MainActor.run {
                        if let window = NSApp.windows.first,
                           let contentView = window.contentView {
                            // Share statements in batch
                            WhatsAppSharingService.shared.shareBatchStatements(
                                statements,
                                in: contentView
                            )
                            successMessage = "\(statements.count) statements prepared for WhatsApp"
                            showingSuccessAlert = true
                        }
                    }
                } else {
                    await MainActor.run {
                        successMessage = "No statements to send"
                        showingSuccessAlert = true
                    }
                }
                await MainActor.run {
                    successMessage = "Monthly statements sent successfully"
                    showingSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    successMessage = "Statement delivery failed: \(error.localizedDescription)"
                    showingSuccessAlert = true
                }
            }
        }
    }
    
    // API key saving no longer needed for WhatsApp
}

// MARK: - Security Settings Tab

struct SecuritySettingsTabView: View {
    var body: some View {
            SettingsSection(title: "Authentication", icon: "lock.shield") {
                VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                    NavigationLink {
                        SecuritySettingsView()
                    } label: {
                        HStack {
                            Label("Security Settings", systemImage: "lock.shield")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        AuthenticationManager.shared.logout()
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.red)
                    }
                }
            }
            
            // Privacy section could go here
    }
}

// MARK: - Data & Sync Settings Tab

struct DataSyncSettingsView: View {
    let dataManager: DataManager
    @ObservedObject var syncManager: CloudKitSyncManager
    @Binding var showingImport: Bool
    @Binding var showingExport: Bool
    @Binding var showingResetConfirmation: Bool
    
    @State private var autoSyncEnabled = true
    @State private var syncInterval = 3
    @State private var showingCloudKitDetails = false
    @State private var showingMessage = false
    @State private var alertMessage = ""
    
    var body: some View {
            // iCloud Sync
            SettingsSection(title: "iCloud Sync", icon: "icloud") {
                VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                    // Sync Status
                    HStack {
                        Label("Sync Status", systemImage: "icloud")
                        Spacer()
                        Text(syncManager.syncStatus.displayText)
                            .foregroundStyle(syncStatusColor)
                            .font(.subheadline)
                        
                        if case .syncing = syncManager.syncStatus {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingCloudKitDetails = true
                    }
                    
                    // Last Sync
                    if let lastSync = syncManager.lastSyncDate {
                        HStack {
                            Label("Last Sync", systemImage: "clock")
                            Spacer()
                            Text(formatSyncTime(lastSync))
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                    
                    // Network Status
                    HStack {
                        Label("Network", systemImage: syncManager.isOnline ? "wifi" : "wifi.slash")
                        Spacer()
                        Text(syncManager.isOnline ? "Online" : "Offline")
                            .foregroundStyle(syncManager.isOnline ? .green : .gray)
                            .font(.subheadline)
                    }
                    
                    Divider()
                    
                    // Auto Sync
                    Toggle(isOn: $autoSyncEnabled) {
                        Label("Automatic Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .onChange(of: autoSyncEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "auto_sync_enabled")
                    }
                    
                    if autoSyncEnabled {
                        SettingsRow(label: "Sync Frequency", systemImage: "timer") {
                            Picker("", selection: $syncInterval) {
                                Text("3 minutes").tag(3)
                                Text("5 minutes").tag(5)
                                Text("10 minutes").tag(10)
                                Text("15 minutes").tag(15)
                            }
                            .labelsHidden()
                            .onChange(of: syncInterval) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "sync_interval_minutes")
                            }
                        }
                    }
                    
                    Button {
                        syncManager.forceSyncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.clockwise")
                    }
                    .disabled(syncManager.syncStatus == .syncing || !syncManager.isOnline)
                    
                    // Error Display
                    if let error = syncManager.syncError {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Sync Error", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.subheadline)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            // Data Management
            SettingsSection(title: "Data Management", icon: "externaldrive") {
                VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                    }
                    
                    Button {
                        showingExport = true
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }
                    
                    Divider()
                    
                    // Auto-backup
                    Toggle("Auto-Backup Weekly", isOn: .init(
                        get: { UserDefaults.standard.bool(forKey: "auto_backup_enabled") },
                        set: { UserDefaults.standard.set($0, forKey: "auto_backup_enabled") }
                    ))
                    
                    if UserDefaults.standard.bool(forKey: "auto_backup_enabled") {
                        HStack {
                            Text("Backup Location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("~/Documents/SolidarityFund/Backups")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // Maintenance
                    Button {
                        dataManager.createMissingTransactions()
                        alertMessage = "Transaction linking process completed"
                        showingMessage = true
                    } label: {
                        Label("Fix Missing Transactions", systemImage: "link.badge.plus")
                    }
                    .help("Creates transaction records for any payments that don't have them")
                    
                    Button {
                        dataManager.fixIncorrectTransactions()
                        alertMessage = "Transaction correction process completed"
                        showingMessage = true
                    } label: {
                        Label("Fix Incorrect Transactions", systemImage: "exclamationmark.arrow.circlepath")
                    }
                    .help("Fixes transactions that don't match their payment type")
                    
                    Divider()
                    
                    Button {
                        DataManager.shared.deleteTestUsers()
                        alertMessage = "Test users have been deleted"
                        showingMessage = true
                    } label: {
                        Label("Delete Test Users", systemImage: "person.3.sequence.fill")
                            .foregroundStyle(.orange)
                    }
                    .help("Removes users named: Test User, John Doe, Jane Doe, Test Member, Sample Member")
                    
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                }
            }
        .onAppear {
            autoSyncEnabled = UserDefaults.standard.object(forKey: "auto_sync_enabled") as? Bool ?? true
            syncInterval = UserDefaults.standard.object(forKey: "sync_interval_minutes") as? Int ?? 3
        }
        .popover(isPresented: $showingCloudKitDetails) {
            CloudKitDetailsView()
        }
        .alert("Information", isPresented: $showingMessage) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private var syncStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle:
            return syncManager.isOnline ? .blue : .gray
        case .syncing:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        }
    }
    
    private func formatSyncTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Advanced Settings Tab

struct AdvancedSettingsView: View {
    let dataManager: DataManager
    @State private var paymentDueNotifications = true
    @State private var utilizationWarningNotifications = true
    @State private var interestNotifications = true
    @State private var syncStatusNotifications = false
    @State private var notificationDaysBefore = 3
    @State private var defaultStartupView = "overview"
    @State private var dateFormat = "medium"
    @State private var showCurrencySymbol = true
    @State private var compactReports = false
    @State private var showingSuccessAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.spacingLarge) {
                interestManagementSection
                notificationsSection
                displayPreferencesSection
                aboutSection
            }
            .padding()
        }
        .onAppear {
            loadSettings()
        }
        .alert("Success", isPresented: $showingSuccessAlert) {
            Button("OK") {}
        } message: {
            Text("Annual interest applied successfully")
        }
    }
    
    // MARK: - View Sections
    
    private var interestManagementSection: some View {
        SettingsSection(title: "Interest Management", icon: "percent") {
            if let fundSettings = dataManager.fundSettings {
                    HStack {
                        Text("Total Interest Applied")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CurrencyFormatter.shared.format(fundSettings.totalInterestApplied))
                            .fontWeight(.medium)
                    }
                    
                    if let lastApplied = fundSettings.lastInterestAppliedDate {
                        HStack {
                            Text("Last Applied")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(DateHelper.formatDate(lastApplied))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    let potentialInterest = FundCalculator.shared.calculateAnnualInterest(settings: fundSettings)
                    HStack {
                        Text("Potential Interest")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CurrencyFormatter.shared.format(potentialInterest))
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    }
                    
                    Button {
                        dataManager.applyAnnualInterest()
                        showingSuccessAlert = true
                    } label: {
                        Label("Apply Annual Interest", systemImage: "percent")
                    }
                    .disabled(potentialInterest <= 0)
            } else {
                Text("No fund settings available")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var notificationsSection: some View {
        SettingsSection(title: "Notifications & Alerts", icon: "bell") {
            VStack(spacing: DesignSystem.spacingMedium) {
                    Toggle(isOn: $paymentDueNotifications) {
                        Label("Payment Due Reminders", systemImage: "bell")
                    }
                    .onChange(of: paymentDueNotifications) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "payment_due_notifications")
                    }
                    
                    if paymentDueNotifications {
                        SettingsRow(label: "Remind Me", systemImage: "calendar") {
                            Picker("", selection: $notificationDaysBefore) {
                                Text("1 day before").tag(1)
                                Text("3 days before").tag(3)
                                Text("5 days before").tag(5)
                                Text("7 days before").tag(7)
                            }
                            .labelsHidden()
                        }
                        .onChange(of: notificationDaysBefore) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "notification_days_before")
                        }
                    }
                    
                    Toggle(isOn: $utilizationWarningNotifications) {
                        Label("Fund Utilization Warnings", systemImage: "exclamationmark.triangle")
                    }
                    .onChange(of: utilizationWarningNotifications) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "utilization_warning_notifications")
                    }
                    
                    Toggle(isOn: $interestNotifications) {
                        Label("Interest Application Reminders", systemImage: "percent")
                    }
                    .onChange(of: interestNotifications) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "interest_notifications")
                    }
                    
                    Toggle(isOn: $syncStatusNotifications) {
                        Label("Sync Status Notifications", systemImage: "icloud.and.arrow.up")
                    }
                    .onChange(of: syncStatusNotifications) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "sync_status_notifications")
                    }
            }
        }
    }
    
    private var displayPreferencesSection: some View {
        SettingsSection(title: "Display & Interface", icon: "paintbrush") {
                    Toggle(isOn: .init(
                        get: { UserDefaults.standard.bool(forKey: "useLiquidGlass") },
                        set: { UserDefaults.standard.set($0, forKey: "useLiquidGlass") }
                    )) {
                        Label("Use Liquid Glass Design (Beta)", systemImage: "sparkles")
                    }
                    .help("Enable the new macOS Tahoe Liquid Glass design system")
                    
                    SettingsRow(label: "Default Startup View", systemImage: "square.grid.2x2") {
                        Picker("", selection: $defaultStartupView) {
                            Text("Overview").tag("overview")
                            Text("Members").tag("members")
                            Text("Loans").tag("loans")
                            Text("Payments").tag("payments")
                            Text("Reports").tag("reports")
                        }
                        .labelsHidden()
                        .onChange(of: defaultStartupView) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "default_startup_view")
                        }
                    }
                    
                    SettingsRow(label: "Date Format", systemImage: "calendar") {
                        Picker("", selection: $dateFormat) {
                            Text("Short (7/20/25)").tag("short")
                            Text("Medium (Jul 20, 2025)").tag("medium")
                            Text("Long (July 20, 2025)").tag("long")
                        }
                        .labelsHidden()
                        .onChange(of: dateFormat) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "date_format_preference")
                        }
                    }
                    
                    Toggle(isOn: $showCurrencySymbol) {
                        Label("Show Currency Symbol", systemImage: "kipsign")
                    }
                    .onChange(of: showCurrencySymbol) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "show_currency_symbol")
                    }
                    
                    Toggle(isOn: $compactReports) {
                        Label("Compact Report View", systemImage: "rectangle.compress.vertical")
                    }
                    .onChange(of: compactReports) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "compact_reports")
                    }
            
        }
    }
    
    private var aboutSection: some View {
        SettingsSection(title: "About", icon: "info.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Version")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("1.0.0")
                    }
                    
                    HStack {
                        Text("Developer")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Bob Kitchen")
                    }
                    
                    HStack {
                        Text("Fund Started")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let fundSettings = dataManager.fundSettings,
                           let createdAt = fundSettings.createdAt {
                            Text(DateHelper.formatDate(createdAt))
                        }
                    }
                    
                    NavigationLink {
                        DocumentationView()
                    } label: {
                        Label("Documentation", systemImage: "doc.text")
                    }
            }
        }
    }
    
    private func loadSettings() {
        paymentDueNotifications = UserDefaults.standard.object(forKey: "payment_due_notifications") as? Bool ?? true
        utilizationWarningNotifications = UserDefaults.standard.object(forKey: "utilization_warning_notifications") as? Bool ?? true
        interestNotifications = UserDefaults.standard.object(forKey: "interest_notifications") as? Bool ?? true
        syncStatusNotifications = UserDefaults.standard.object(forKey: "sync_status_notifications") as? Bool ?? false
        notificationDaysBefore = UserDefaults.standard.object(forKey: "notification_days_before") as? Int ?? 3
        defaultStartupView = UserDefaults.standard.string(forKey: "default_startup_view") ?? "overview"
        dateFormat = UserDefaults.standard.string(forKey: "date_format_preference") ?? "medium"
        showCurrencySymbol = UserDefaults.standard.object(forKey: "show_currency_symbol") as? Bool ?? true
        compactReports = UserDefaults.standard.object(forKey: "compact_reports") as? Bool ?? false
    }
}

// MARK: - Settings Section / Row
//
// Transparent wrappers. The previous versions wrapped content in GroupBox
// + Label header + Material backgrounds, double-stacking on Form/.grouped.
// They also put leading icons on every row, which Apple's own Settings
// don't do. These now emit stock `Section` and `LabeledContent` so tab
// bodies render as canonical macOS Settings groups.

struct SettingsSection<Content: View>: View {
    let title: String
    /// Retained for source compatibility but ignored — Apple's Settings
    /// section headers are plain text, not labels with icons.
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section(title) { content() }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    /// Retained for source compatibility but ignored — Apple's Settings
    /// rows don't have leading icons in the General/Messaging/etc. tabs.
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        LabeledContent(label) { content() }
    }
}

// MARK: - Export Document

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let dataManager: DataManager
    var jsonData: Data
    var exportError: Error?

    init(dataManager: DataManager) {
        self.dataManager = dataManager
        do {
            self.jsonData = try DataImportExport.shared.exportData()
            self.exportError = nil
        } catch {
            self.jsonData = Data()
            self.exportError = error
            print("❌ Export failed: \(error.localizedDescription)")
        }
    }

    init(configuration: ReadConfiguration) throws {
        self.dataManager = DataManager.shared
        self.jsonData = configuration.file.regularFileContents ?? Data()
        self.exportError = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let error = exportError {
            throw error
        }
        if jsonData.isEmpty {
            throw NSError(domain: "ExportDocument", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No data to export. The database may be empty or inaccessible."])
        }
        return FileWrapper(regularFileWithContents: jsonData)
    }
}

// MARK: - Documentation View

struct DocumentationView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Solidarity Fund Documentation")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Section {
                    Text("Overview")
                        .font(.headline)
                    Text("The Parachichi House Solidarity Fund provides interest-free emergency loans to household staff while encouraging regular savings through monthly contributions.")
                        .padding(.bottom)
                }
                
                Section {
                    Text("Member Roles & Loan Limits")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        bulletPoint("Driver/Assistant: KSH 40,000")
                        bulletPoint("Housekeeper: KSH 19,000")
                        bulletPoint("Grounds Keeper: KSH 19,000")
                        bulletPoint("Guards/Part-time: Contributions to date, max KSH 12,000")
                    }
                    .padding(.bottom)
                }
                
                Section {
                    Text("Business Rules")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        bulletPoint("Monthly contribution: KSH 2,000")
                        bulletPoint("Loan repayment: 3 or 4 months")
                        bulletPoint("Guards need 3 months of contributions before loans")
                        bulletPoint("13% annual interest applied to fund")
                        bulletPoint("60% utilization warning threshold")
                        bulletPoint("KSH 50,000 minimum fund balance")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Documentation")
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text("•")
            Text(text)
        }
    }
}



#Preview {
    SettingsView()
        .environmentObject(DataManager.shared)
}