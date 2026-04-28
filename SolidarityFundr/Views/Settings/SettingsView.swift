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
        case security = "Security"
        case dataSync = "Data & Sync"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .security: return "lock.shield"
            case .dataSync: return "icloud.and.arrow.up"
            case .about: return "info.circle"
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
            tab(AboutSettingsView(dataManager: dataManager), .about)
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
    @State private var showingInterestAppliedAlert = false

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

        Section {
            if let fundSettings = dataManager.fundSettings {
                LabeledContent("Total Interest Applied") {
                    Text(CurrencyFormatter.shared.format(fundSettings.totalInterestApplied))
                }
                if let lastApplied = fundSettings.lastInterestAppliedDate {
                    LabeledContent("Last Applied") {
                        Text(DateHelper.formatDate(lastApplied))
                            .foregroundStyle(.secondary)
                    }
                }
                let potentialInterest = FundCalculator.shared.calculateAnnualInterest(settings: fundSettings)
                LabeledContent("Potential Interest") {
                    Text(CurrencyFormatter.shared.format(potentialInterest))
                        .foregroundStyle(potentialInterest > 0 ? .green : .secondary)
                }
                Button {
                    dataManager.applyAnnualInterest()
                    showingInterestAppliedAlert = true
                } label: {
                    Label("Apply Annual Interest", systemImage: "percent")
                }
                .disabled(potentialInterest <= 0)
            }
        } header: {
            Text("Fund Operations")
        } footer: {
            Text("Applies the configured annual rate to the fund's total value. Once-yearly action.")
        }
        .alert("Annual interest applied", isPresented: $showingInterestAppliedAlert) {
            Button("OK") {}
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

// MARK: - Security Settings Tab

struct SecuritySettingsTabView: View {
    var body: some View {
        Section("Authentication") {
            NavigationLink {
                SecuritySettingsView()
            } label: {
                Label("Security Settings", systemImage: "lock.shield")
            }

            Button {
                AuthenticationManager.shared.logout()
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Data & Sync Settings Tab

struct DataSyncSettingsView: View {
    let dataManager: DataManager
    @ObservedObject var syncManager: CloudKitSyncManager
    @Binding var showingImport: Bool
    @Binding var showingExport: Bool
    @Binding var showingResetConfirmation: Bool

    @State private var showingCloudKitDetails = false
    @State private var showingMessage = false
    @State private var alertMessage = ""
    @State private var showingReconcileConfirmation = false
    @State private var showingReconcileResult = false
    @State private var reconcileResultMessage = ""

    var body: some View {
        // iCloud Sync — surfaces state. NSPersistentCloudKitContainer
        // propagates changes via APNs silent push automatically; there
        // is no public API to schedule polling, so the previous
        // "Automatic Sync" / "Sync Frequency" toggles wrote to dead
        // UserDefaults keys and have been removed.
        Section("iCloud Sync") {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Text(syncManager.syncStatus.displayText)
                        .foregroundStyle(syncStatusColor)
                    if case .syncing = syncManager.syncStatus {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showingCloudKitDetails = true }

            if let lastSync = syncManager.lastSyncDate {
                LabeledContent("Last Sync", value: formatSyncTime(lastSync))
            }

            LabeledContent("Network") {
                Text(syncManager.isOnline ? "Online" : "Offline")
                    .foregroundStyle(syncManager.isOnline ? .green : .secondary)
            }

            Button {
                syncManager.saveAndSurfaceState()
            } label: {
                Label("Save Local Changes", systemImage: "arrow.clockwise")
            }
            .disabled(syncManager.syncStatus == .syncing || !syncManager.isOnline)

            if let error = syncManager.syncError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }

        Section("Backup & Restore") {
            Button {
                showingImport = true
            } label: {
                Label("Import Data…", systemImage: "square.and.arrow.down")
            }

            Button {
                showingExport = true
            } label: {
                Label("Export Backup…", systemImage: "square.and.arrow.up")
            }
        }

        Section {
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

            Button {
                showingReconcileConfirmation = true
            } label: {
                Label("Reconcile Ledger…", systemImage: "scalemass")
            }
            .help("Rebuilds the entire transaction ledger from Member, Loan, and Payment records. Use when the Fund Balance has drifted from what the underlying entities say.")

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
        } header: {
            Text("Maintenance")
        } footer: {
            Text("These actions modify or destroy data. They cannot be undone — make sure a backup exists first.")
        }
        .popover(isPresented: $showingCloudKitDetails) {
            CloudKitDetailsView()
        }
        .alert("Information", isPresented: $showingMessage) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "Reconcile ledger?",
            isPresented: $showingReconcileConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reconcile", role: .destructive) {
                runReconcileLedger()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every Transaction record and rebuilds the ledger from Members, Loans, and Payments. Use this when the Fund Balance has drifted from what the underlying entities say. The action is recorded in History.")
        }
        .alert("Ledger reconciled", isPresented: $showingReconcileResult) {
            Button("OK") {}
        } message: {
            Text(reconcileResultMessage)
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

    private func runReconcileLedger() {
        do {
            let report = try dataManager.reconcileLedger()
            let drift = report.driftAmount
            let driftLine: String
            if abs(drift) < 0.01 {
                driftLine = "No drift — the ledger already matched ground truth."
            } else if drift < 0 {
                driftLine = "Fund Balance corrected from \(CurrencyFormatter.shared.format(report.oldFundBalance)) → \(CurrencyFormatter.shared.format(report.newFundBalance)). The ledger was overstated by \(CurrencyFormatter.shared.format(-drift))."
            } else {
                driftLine = "Fund Balance corrected from \(CurrencyFormatter.shared.format(report.oldFundBalance)) → \(CurrencyFormatter.shared.format(report.newFundBalance)). The ledger was understated by \(CurrencyFormatter.shared.format(drift))."
            }
            reconcileResultMessage = """
            \(driftLine)

            \(report.transactionsDeleted) transactions removed, \
            \(report.transactionsCreated) recreated from Members, Loans, and Payments. \
            Recorded in History.
            """
        } catch {
            reconcileResultMessage = "Reconciliation failed: \(error.localizedDescription)"
        }
        showingReconcileResult = true
    }
}

// MARK: - About Tab
//
// Replaces the old "Advanced" tab, which had grown into a graveyard of
// UserDefaults toggles that nothing actually read (notifications that
// were never scheduled, display prefs that no formatter consulted, a
// "Use Liquid Glass" toggle that pointed at a code path stripped months
// ago). The one consequential action that lived here — Apply Annual
// Interest — has moved into General → Fund Operations where it sits
// alongside the rates and balances it depends on.

struct AboutSettingsView: View {
    let dataManager: DataManager

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        Section("Solidarity Fundr") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Developer", value: "Bob Kitchen")
            if let createdAt = dataManager.fundSettings?.createdAt {
                LabeledContent("Fund Started", value: DateHelper.formatDate(createdAt))
            }
        }

        Section {
            NavigationLink {
                DocumentationView()
            } label: {
                Label("Documentation", systemImage: "doc.text")
            }
        }
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