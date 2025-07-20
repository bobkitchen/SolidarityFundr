//
//  SettingsView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var syncManager = CloudKitSyncManager.shared
    
    init() {
        print("🔧 SettingsView: init called")
    }
    @State private var selectedTab = 0
    @State private var showingImport = false
    @State private var showingExport = false
    @State private var showingResetConfirmation = false
    @State private var showingSuccessAlert = false
    @State private var successMessage = ""
    
    // Fund Settings
    @State private var monthlyContribution: String = ""
    @State private var annualInterestRate: String = ""
    @State private var utilizationWarningThreshold: String = ""
    @State private var minimumFundBalance: String = ""
    @State private var bobRemainingInvestment: String = ""
    
    // Business Rules
    @State private var overrideUtilizationWarning = false
    @State private var overrideMinimumBalance = false
    @State private var allowPartialPayments = false
    
    // Sync Settings
    @State private var autoSyncEnabled = true
    @State private var syncInterval = 3 // minutes
    @State private var showingCloudKitDetails = false
    
    // Notification Settings
    @State private var paymentDueNotifications = true
    @State private var utilizationWarningNotifications = true
    @State private var interestNotifications = true
    @State private var syncStatusNotifications = false
    @State private var notificationDaysBefore = 3
    
    // Display Settings
    @State private var defaultStartupView = "overview"
    @State private var dateFormat = "medium"
    @State private var showCurrencySymbol = true
    @State private var compactReports = false
    
    var body: some View {
        let _ = print("🔧 SettingsView: body called")
        
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16) // Normal padding - traffic lights will overlay
            .padding(.bottom, 12)
            
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        iCloudSyncSection
                    }
                
                GroupBox {
                    notificationsSection
                }
                
                GroupBox {
                    displaySection
                }
                
                GroupBox {
                    fundConfigurationSection
                }
                
                GroupBox {
                    businessRulesSection
                }
                
                GroupBox {
                    interestApplicationSection
                }
                
                GroupBox {
                    securitySection
                }
                
                GroupBox {
                    dataManagementSection
                }
                
                GroupBox {
                    aboutSection
                }
            }
            .padding()
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
        print("🔧 SettingsView: onAppear called")
        loadSettings()
    }
    .alert("Success", isPresented: $showingSuccessAlert) {
        Button("OK") {}
    } message: {
        Text(successMessage)
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
    }
    
    // MARK: - View Sections
    
    private var iCloudSyncSection: some View {
        let _ = print("🔧 SettingsView: iCloudSyncSection called")
        return VStack(alignment: .leading, spacing: 12) {
            Text("iCloud & Sync")
                .font(.headline)
                .padding(.bottom, 4)
            // Sync Status Row
            HStack {
                Label("Sync Status", systemImage: "icloud")
                Spacer()
                Text(syncManager.syncStatus.displayText)
                    .foregroundColor(syncStatusColor)
                    .font(.subheadline)
                
                if case .syncing = syncManager.syncStatus {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .onTapGesture {
                showingCloudKitDetails = true
            }
            
            // Last Sync
            if let lastSync = syncManager.lastSyncDate {
                HStack {
                    Label("Last Sync", systemImage: "clock")
                    Spacer()
                    Text(formatSyncTime(lastSync))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
            
            // Network Status
            HStack {
                Label("Network", systemImage: syncManager.isOnline ? "wifi" : "wifi.slash")
                Spacer()
                Text(syncManager.isOnline ? "Online" : "Offline")
                    .foregroundColor(syncManager.isOnline ? .green : .gray)
                    .font(.subheadline)
            }
            
            // Auto Sync Toggle
            Toggle(isOn: $autoSyncEnabled) {
                Label("Automatic Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .onChange(of: autoSyncEnabled) { oldValue, newValue in
                UserDefaults.standard.set(newValue, forKey: "auto_sync_enabled")
            }
            
            // Sync Interval
            if autoSyncEnabled {
                Picker(selection: $syncInterval) {
                    Text("3 minutes").tag(3)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                } label: {
                    Label("Sync Frequency", systemImage: "timer")
                }
                .onChange(of: syncInterval) { oldValue, newValue in
                    UserDefaults.standard.set(newValue, forKey: "sync_interval_minutes")
                    // TODO: Update sync timer with new interval
                }
            }
            
            // Manual Sync Button
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
                        .foregroundColor(.red)
                        .font(.subheadline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .popover(isPresented: $showingCloudKitDetails) {
            CloudKitDetailsView()
        }
    }
    
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notifications & Alerts")
                .font(.headline)
                .padding(.bottom, 4)
            // Main notification toggles
            Toggle(isOn: $paymentDueNotifications) {
                Label("Payment Due Reminders", systemImage: "bell")
            }
            
            if paymentDueNotifications {
                Picker(selection: $notificationDaysBefore) {
                    Text("1 day before").tag(1)
                    Text("3 days before").tag(3)
                    Text("5 days before").tag(5)
                    Text("7 days before").tag(7)
                } label: {
                    Label("Remind Me", systemImage: "calendar")
                }
                .pickerStyle(.menu)
            }
            
            Toggle(isOn: $utilizationWarningNotifications) {
                Label("Fund Utilization Warnings", systemImage: "exclamationmark.triangle")
            }
            
            Toggle(isOn: $interestNotifications) {
                Label("Interest Application Reminders", systemImage: "percent")
            }
            
            Toggle(isOn: $syncStatusNotifications) {
                Label("Sync Status Notifications", systemImage: "icloud.and.arrow.up")
            }
            
            Text("Notifications help you stay on top of fund activities and member obligations")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onChange(of: paymentDueNotifications) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "payment_due_notifications")
        }
        .onChange(of: utilizationWarningNotifications) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "utilization_warning_notifications")
        }
        .onChange(of: interestNotifications) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "interest_notifications")
        }
        .onChange(of: syncStatusNotifications) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "sync_status_notifications")
        }
        .onChange(of: notificationDaysBefore) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "notification_days_before")
        }
    }
    
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display & Interface")
                .font(.headline)
                .padding(.bottom, 4)
            
            // Liquid Glass Toggle
            Toggle(isOn: .init(
                get: { UserDefaults.standard.bool(forKey: "useLiquidGlass") },
                set: { UserDefaults.standard.set($0, forKey: "useLiquidGlass") }
            )) {
                Label("Use Liquid Glass Design (Beta)", systemImage: "sparkles")
            }
            .help("Enable the new macOS Tahoe Liquid Glass design system")
            
            Picker(selection: $defaultStartupView) {
                Text("Overview").tag("overview")
                Text("Members").tag("members")
                Text("Loans").tag("loans")
                Text("Payments").tag("payments")
                Text("Reports").tag("reports")
            } label: {
                Label("Default Startup View", systemImage: "square.grid.2x2")
            }
            
            Picker(selection: $dateFormat) {
                Text("Short (7/20/25)").tag("short")
                Text("Medium (Jul 20, 2025)").tag("medium")
                Text("Long (July 20, 2025)").tag("long")
            } label: {
                Label("Date Format", systemImage: "calendar")
            }
            
            Toggle(isOn: $showCurrencySymbol) {
                Label("Show Currency Symbol", systemImage: "kipsign")
            }
            
            Toggle(isOn: $compactReports) {
                Label("Compact Report View", systemImage: "rectangle.compress.vertical")
            }
            
            Text("Customize how information is displayed throughout the app")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onChange(of: defaultStartupView) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "default_startup_view")
        }
        .onChange(of: dateFormat) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "date_format_preference")
        }
        .onChange(of: showCurrencySymbol) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "show_currency_symbol")
        }
        .onChange(of: compactReports) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "compact_reports")
        }
    }
    
    private var fundConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fund Configuration")
                .font(.headline)
                .padding(.bottom, 4)
            HStack {
                Label("Monthly Contribution", systemImage: "banknote")
                Spacer()
                TextField("2000", text: $monthlyContribution)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("KSH")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Annual Interest Rate", systemImage: "percent")
                Spacer()
                TextField("13", text: $annualInterestRate)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("%")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Utilization Warning", systemImage: "exclamationmark.triangle")
                Spacer()
                TextField("60", text: $utilizationWarningThreshold)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("%")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Minimum Fund Balance", systemImage: "chart.line.downtrend.xyaxis")
                Spacer()
                TextField("50000", text: $minimumFundBalance)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("KSH")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Bob's Remaining Investment", systemImage: "person.fill")
                Spacer()
                TextField("100000", text: $bobRemainingInvestment)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("KSH")
                    .foregroundColor(.secondary)
            }
            
            Button {
                saveSettings()
            } label: {
                Label("Save Changes", systemImage: "checkmark.circle.fill")
            }
        }
    }
    
    private var businessRulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Business Rules")
                .font(.headline)
                .padding(.bottom, 4)
            Toggle("Override Utilization Warning", isOn: $overrideUtilizationWarning)
                .tint(.orange)
            
            Toggle("Override Minimum Balance Warning", isOn: $overrideMinimumBalance)
                .tint(.orange)
            
            Toggle("Allow Partial Loan Payments", isOn: $allowPartialPayments)
                .tint(.blue)
            
            Text("Warning: Overriding business rules may compromise fund stability")
                .font(.caption)
                .foregroundColor(.orange)
        }
    }
    
    private var interestApplicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interest Management")
                .font(.headline)
                .padding(.bottom, 4)
            if let fundSettings = dataManager.fundSettings {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Total Interest Applied")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(CurrencyFormatter.shared.format(fundSettings.totalInterestApplied))
                            .fontWeight(.medium)
                    }
                    
                    if let lastApplied = fundSettings.lastInterestAppliedDate {
                        HStack {
                            Text("Last Applied")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(DateHelper.formatDate(lastApplied))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    let potentialInterest = FundCalculator.shared.calculateAnnualInterest(settings: fundSettings)
                    HStack {
                        Text("Potential Interest")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(CurrencyFormatter.shared.format(potentialInterest))
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    
                    Button {
                        applyAnnualInterest()
                    } label: {
                        Label("Apply Annual Interest", systemImage: "percent")
                    }
                    .disabled(potentialInterest <= 0)
                }
            }
        }
    }
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Security")
                .font(.headline)
                .padding(.bottom, 4)
            NavigationLink {
                SecuritySettingsView()
            } label: {
                Label("Security Settings", systemImage: "lock.shield")
            }
            
            Button {
                AuthenticationManager.shared.logout()
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundColor(.red)
            }
        }
    }
    
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reports & Data Export")
                .font(.headline)
                .padding(.bottom, 4)
            // Report Settings
            VStack(alignment: .leading, spacing: 12) {
                Label("Report Preferences", systemImage: "doc.text")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.bottom, 4)
                
                HStack {
                    Text("Default Date Range")
                        .foregroundColor(.secondary)
                    Spacer()
                    Menu {
                        Button("Last Month") { UserDefaults.standard.set("lastMonth", forKey: "default_report_range") }
                        Button("Last 3 Months") { UserDefaults.standard.set("last3Months", forKey: "default_report_range") }
                        Button("Last 6 Months") { UserDefaults.standard.set("last6Months", forKey: "default_report_range") }
                        Button("Year to Date") { UserDefaults.standard.set("yearToDate", forKey: "default_report_range") }
                        Button("All Time") { UserDefaults.standard.set("allTime", forKey: "default_report_range") }
                    } label: {
                        Text(UserDefaults.standard.string(forKey: "default_report_range") ?? "Last 3 Months")
                            .foregroundColor(.accentColor)
                    }
                }
                
                Toggle("Include Inactive Members", isOn: .init(
                    get: { UserDefaults.standard.bool(forKey: "include_inactive_in_reports") },
                    set: { UserDefaults.standard.set($0, forKey: "include_inactive_in_reports") }
                ))
                .font(.subheadline)
                
                Toggle("Auto-Open PDFs in Preview", isOn: .init(
                    get: { UserDefaults.standard.object(forKey: "auto_open_pdfs") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "auto_open_pdfs") }
                ))
                .font(.subheadline)
            }
            .padding(.vertical, 4)
            
            Divider()
            
            // Data Import/Export
            VStack(alignment: .leading, spacing: 12) {
                Label("Data Management", systemImage: "externaldrive")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.bottom, 4)
                
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
                
                // Auto-backup settings
                Toggle("Auto-Backup Weekly", isOn: .init(
                    get: { UserDefaults.standard.bool(forKey: "auto_backup_enabled") },
                    set: { UserDefaults.standard.set($0, forKey: "auto_backup_enabled") }
                ))
                .font(.subheadline)
                
                if UserDefaults.standard.bool(forKey: "auto_backup_enabled") {
                    HStack {
                        Text("Backup Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("~/Documents/SolidarityFund/Backups")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            
            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label("Reset All Data", systemImage: "trash")
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
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.headline)
                .padding(.bottom, 4)
            HStack {
                Text("Version")
                    .foregroundColor(.secondary)
                Spacer()
                Text("1.0.0")
            }
            
            HStack {
                Text("Developer")
                    .foregroundColor(.secondary)
                Spacer()
                Text("Bob Kitchen")
            }
            
            HStack {
                Text("Fund Started")
                    .foregroundColor(.secondary)
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
    
    // MARK: - Helper Methods
    
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
    
    private func loadSettings() {
        guard let settings = dataManager.fundSettings else { return }
        
        monthlyContribution = String(format: "%.0f", settings.monthlyContribution)
        annualInterestRate = String(format: "%.0f", settings.annualInterestRate * 100)
        utilizationWarningThreshold = String(format: "%.0f", settings.utilizationWarningThreshold * 100)
        minimumFundBalance = String(format: "%.0f", settings.minimumFundBalance)
        bobRemainingInvestment = String(format: "%.0f", settings.bobRemainingInvestment)
        
        // Load sync settings
        autoSyncEnabled = UserDefaults.standard.object(forKey: "auto_sync_enabled") as? Bool ?? true
        syncInterval = UserDefaults.standard.object(forKey: "sync_interval_minutes") as? Int ?? 3
        
        // Load notification settings
        paymentDueNotifications = UserDefaults.standard.object(forKey: "payment_due_notifications") as? Bool ?? true
        utilizationWarningNotifications = UserDefaults.standard.object(forKey: "utilization_warning_notifications") as? Bool ?? true
        interestNotifications = UserDefaults.standard.object(forKey: "interest_notifications") as? Bool ?? true
        syncStatusNotifications = UserDefaults.standard.object(forKey: "sync_status_notifications") as? Bool ?? false
        notificationDaysBefore = UserDefaults.standard.object(forKey: "notification_days_before") as? Int ?? 3
        
        // Load display settings
        defaultStartupView = UserDefaults.standard.string(forKey: "default_startup_view") ?? "overview"
        dateFormat = UserDefaults.standard.string(forKey: "date_format_preference") ?? "medium"
        showCurrencySymbol = UserDefaults.standard.object(forKey: "show_currency_symbol") as? Bool ?? true
        compactReports = UserDefaults.standard.object(forKey: "compact_reports") as? Bool ?? false
    }
    
    private func saveSettings() {
        guard let settings = dataManager.fundSettings else { return }
        
        if let contribution = Double(monthlyContribution) {
            settings.monthlyContribution = contribution
        }
        
        if let rate = Double(annualInterestRate) {
            settings.annualInterestRate = rate / 100
        }
        
        if let threshold = Double(utilizationWarningThreshold) {
            settings.utilizationWarningThreshold = threshold / 100
        }
        
        if let minBalance = Double(minimumFundBalance) {
            settings.minimumFundBalance = minBalance
        }
        
        if let bobInvestment = Double(bobRemainingInvestment) {
            settings.bobRemainingInvestment = bobInvestment
        }
        
        settings.updatedAt = Date()
        
        do {
            try PersistenceController.shared.container.viewContext.save()
            successMessage = "Settings saved successfully"
            showingSuccessAlert = true
        } catch {
            print("Error saving settings: \(error)")
        }
    }
    
    private func applyAnnualInterest() {
        dataManager.applyAnnualInterest()
        successMessage = "Annual interest applied successfully"
        showingSuccessAlert = true
        loadSettings()
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                let data = try Data(contentsOf: url)
                try DataImportExport.shared.importData(from: data)
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
            print("Export error: \(error)")
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

// MARK: - Export Document

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    let dataManager: DataManager
    var jsonData: Data
    
    init(dataManager: DataManager) {
        self.dataManager = dataManager
        do {
            self.jsonData = try DataImportExport.shared.exportData()
        } catch {
            self.jsonData = Data()
            print("Export error: \(error)")
        }
    }
    
    init(configuration: ReadConfiguration) throws {
        self.dataManager = DataManager.shared
        self.jsonData = configuration.file.regularFileContents ?? Data()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
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