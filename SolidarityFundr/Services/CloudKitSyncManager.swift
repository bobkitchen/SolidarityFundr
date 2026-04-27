//
//  CloudKitSyncManager.swift
//  SolidarityFundr
//
//  Observes NSPersistentCloudKitContainer events and surfaces sync state
//  to the UI. Does NOT attempt to "force sync" — CloudKit propagates
//  changes via silent push automatically; there is no public API on
//  NSPersistentCloudKitContainer to trigger an on-demand fetch.
//

import Foundation
import CloudKit
import CoreData
import Combine
import Network

@MainActor
class CloudKitSyncManager: ObservableObject {
    static let shared = CloudKitSyncManager()

    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var isOnline: Bool = true
    @Published var setupErrorDescription: String?

    let containerIdentifier = "iCloud.com.bobk.SolidarityFundr"

    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    private var cancellables = Set<AnyCancellable>()

    /// Lazily resolved so the manager can subscribe to container events
    /// before `PersistenceController.shared` triggers `loadPersistentStores`.
    /// Touching `.shared` here would re-enter the controller during its own
    /// init, so we defer until the first action that actually needs it.
    private var container: NSPersistentCloudKitContainer {
        PersistenceController.shared.container
    }

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)

        var displayText: String {
            switch self {
            case .idle: return "Ready"
            case .syncing: return "Syncing…"
            case .success: return "Synced"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    private init() {
        setupNetworkMonitoring()
        setupCloudKitEventMonitoring()
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    // MARK: - CloudKit Event Monitoring

    private func setupCloudKitEventMonitoring() {
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleCloudKitEvent(notification)
            }
            .store(in: &cancellables)
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        switch event.type {
        case .setup:
            if event.succeeded {
                syncStatus = .success
                setupErrorDescription = nil
            } else {
                let errorMessage = event.error?.localizedDescription ?? "Setup failed"
                syncStatus = .error(errorMessage)
                syncError = errorMessage
                setupErrorDescription = errorMessage
            }

        case .import:
            if event.succeeded {
                lastSyncDate = Date()
                syncStatus = .success
            } else {
                let errorMessage = event.error?.localizedDescription ?? "Import failed"
                syncStatus = .error(errorMessage)
                syncError = errorMessage
            }

        case .export:
            if event.succeeded {
                lastSyncDate = Date()
                syncStatus = .success
            } else {
                let errorMessage = event.error?.localizedDescription ?? "Export failed"
                syncStatus = .error(errorMessage)
                syncError = errorMessage
            }

        @unknown default:
            break
        }
    }

    // MARK: - Manual Actions

    /// Surfaces the current state. There is no public API to force a
    /// CloudKit fetch on `NSPersistentCloudKitContainer` — the system
    /// propagates remote changes automatically via silent push. This
    /// method just saves any pending local changes (which DataManager
    /// also does on every mutation, so the call is mostly cosmetic).
    func saveAndSurfaceState() {
        guard isOnline else {
            syncStatus = .error("Offline")
            return
        }

        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                syncStatus = .error(error.localizedDescription)
                syncError = error.localizedDescription
                return
            }
        }
        // If the last event was a successful import/export, leave state alone.
        if case .error = syncStatus {
            // Keep the existing error visible until cleared.
        } else {
            syncStatus = .success
        }
    }

    func clearSyncError() {
        syncError = nil
        if case .error = syncStatus {
            syncStatus = .idle
        }
    }

    // MARK: - CloudKit Account Status

    func checkCloudKitStatus() async -> CKAccountStatus {
        do {
            let container = CKContainer(identifier: containerIdentifier)
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }

    /// Active probe — talks to CloudKit directly to verify connectivity and
    /// that the app's record zone exists. Useful when no events have fired
    /// yet (e.g., fresh install with empty store) and the user wants
    /// definitive confirmation that sync is wired up.
    struct ProbeResult {
        let accountStatus: CKAccountStatus
        let userRecordID: String?
        let zoneCount: Int?
        let error: String?
    }

    func probeCloudKit() async -> ProbeResult {
        let ckContainer = CKContainer(identifier: containerIdentifier)
        let accountStatus: CKAccountStatus
        do {
            accountStatus = try await ckContainer.accountStatus()
        } catch {
            return ProbeResult(accountStatus: .couldNotDetermine,
                               userRecordID: nil,
                               zoneCount: nil,
                               error: error.localizedDescription)
        }

        guard accountStatus == .available else {
            return ProbeResult(accountStatus: accountStatus,
                               userRecordID: nil,
                               zoneCount: nil,
                               error: nil)
        }

        do {
            let recordID = try await ckContainer.userRecordID()
            let zones = try await ckContainer.privateCloudDatabase.allRecordZones()
            return ProbeResult(accountStatus: accountStatus,
                               userRecordID: recordID.recordName,
                               zoneCount: zones.count,
                               error: nil)
        } catch {
            return ProbeResult(accountStatus: accountStatus,
                               userRecordID: nil,
                               zoneCount: nil,
                               error: error.localizedDescription)
        }
    }

    func getCloudKitStatusMessage() async -> String {
        let status = await checkCloudKitStatus()
        switch status {
        case .available: return "CloudKit Available"
        case .noAccount: return "No iCloud Account"
        case .restricted: return "iCloud Restricted"
        case .couldNotDetermine: return "CloudKit Status Unknown"
        case .temporarilyUnavailable: return "CloudKit Temporarily Unavailable"
        @unknown default: return "Unknown CloudKit Status"
        }
    }

    /// One-shot diagnostic snapshot — useful for "Copy Diagnostic Info" in
    /// the Settings sync panel.
    func diagnosticSummary(accountStatus: CKAccountStatus) -> String {
        let lines: [String] = [
            "CloudKit Diagnostic — \(Date().formatted(date: .abbreviated, time: .standard))",
            "Container: \(containerIdentifier)",
            "Account: \(accountStatusName(accountStatus))",
            "Online: \(isOnline ? "yes" : "no")",
            "Status: \(syncStatus.displayText)",
            "Last sync: \(lastSyncDate?.formatted(date: .abbreviated, time: .standard) ?? "never")",
            setupErrorDescription.map { "Setup error: \($0)" } ?? "Setup error: none",
            syncError.map { "Last error: \($0)" } ?? "Last error: none",
        ]
        return lines.joined(separator: "\n")
    }

    private func accountStatusName(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "available"
        case .noAccount: return "no account"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "unknown"
        case .temporarilyUnavailable: return "temporarily unavailable"
        @unknown default: return "unknown"
        }
    }
}
