//
//  iPhoneSettingsView.swift
//  SolidarityFundr
//
//  iOS Settings root. macOS uses a separate `Settings` Scene — that's
//  not available on iOS. The four content views (General, Security,
//  Data & Sync, About) are reused as-is; they're written as `Section`
//  composers, so wrapping them in a Form here gives the standard iOS
//  grouped-form chrome.
//

#if !os(macOS)

import SwiftUI
import UniformTypeIdentifiers

struct iPhoneSettingsView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var syncManager = CloudKitSyncManager.shared

    // Import / Export bindings used by DataSyncSettingsView.
    @State private var showingImport = false
    @State private var showingExport = false
    @State private var showingResetConfirmation = false
    @State private var resultMessage = ""
    @State private var showingResultAlert = false

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    Form { GeneralSettingsView(dataManager: dataManager) }
                        .formStyle(.grouped)
                        .navigationTitle("General")
                } label: {
                    Label("General", systemImage: "gear")
                }

                NavigationLink {
                    Form { SecuritySettingsTabView() }
                        .formStyle(.grouped)
                        .navigationTitle("Security")
                } label: {
                    Label("Security", systemImage: "lock.shield")
                }

                NavigationLink {
                    Form {
                        DataSyncSettingsView(
                            dataManager: dataManager,
                            syncManager: syncManager,
                            showingImport: $showingImport,
                            showingExport: $showingExport,
                            showingResetConfirmation: $showingResetConfirmation
                        )
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Data & Sync")
                } label: {
                    Label("Data & Sync", systemImage: "icloud.and.arrow.up")
                }

                NavigationLink {
                    Form { AboutSettingsView(dataManager: dataManager) }
                        .formStyle(.grouped)
                        .navigationTitle("About")
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
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
                "Reset all data?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Everything", role: .destructive) {
                    resetAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all members, loans, payments, and transactions. This action cannot be undone.")
            }
            .alert("Result", isPresented: $showingResultAlert) {
                Button("OK") {}
            } message: {
                Text(resultMessage)
            }
        }
    }

    // MARK: - Import / Export / Reset

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try DataImportExport.shared.importData(from: data)
                dataManager.setupFundSettings()
                dataManager.recalculateAllTransactionBalances()
                dataManager.recalculateAllMemberContributions()
                dataManager.fetchMembers()
                dataManager.fetchActiveLoans()
                dataManager.fetchRecentTransactions()
                resultMessage = "Data imported successfully."
            } catch {
                resultMessage = "Import failed: \(error.localizedDescription)"
            }
            showingResultAlert = true
        case .failure(let error):
            resultMessage = "Import failed: \(error.localizedDescription)"
            showingResultAlert = true
        }
    }

    private func handleFileExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            resultMessage = "Backup exported successfully."
        case .failure(let error):
            resultMessage = "Export failed: \(error.localizedDescription)"
        }
        showingResultAlert = true
    }

    private func resetAllData() {
        do {
            // Same recipe as SettingsView.resetAllData on macOS:
            // import an empty document, then resync all aggregates.
            try DataImportExport.shared.importData(from: Data("{}".utf8))
            dataManager.fetchMembers()
            dataManager.fetchActiveLoans()
            dataManager.fetchRecentTransactions()
            dataManager.setupFundSettings()
            resultMessage = "All data has been reset."
        } catch {
            resultMessage = "Reset failed: \(error.localizedDescription)"
        }
        showingResultAlert = true
    }
}

#endif
