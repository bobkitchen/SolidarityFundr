//
//  CloudKitSyncManager.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
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
    
    private let container: NSPersistentCloudKitContainer
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    private var syncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)
        
        var displayText: String {
            switch self {
            case .idle:
                return "Ready"
            case .syncing:
                return "Syncing..."
            case .success:
                return "Synced"
            case .error(let message):
                return "Error: \(message)"
            }
        }
        
        static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.syncing, .syncing), (.success, .success):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
    private init() {
        self.container = PersistenceController.shared.container
        setupNetworkMonitoring()
        setupCloudKitEventMonitoring()
        startBackgroundSync()
    }
    
    deinit {
        Task { @MainActor in
            stopBackgroundSync()
        }
        networkMonitor.cancel()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    Task {
                        await self?.triggerSync()
                    }
                }
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
            } else {
                let errorMessage = event.error?.localizedDescription ?? "Setup failed"
                syncStatus = .error(errorMessage)
                syncError = errorMessage
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
    
    // MARK: - Background Sync
    
    private func startBackgroundSync() {
        // Sync every 3 minutes when app is active
        syncTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.triggerSync()
            }
        }
        
        // Initial sync
        Task { @MainActor in
            await triggerSync()
        }
    }
    
    private func stopBackgroundSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    func triggerSync() async {
        guard isOnline else {
            return
        }
        
        guard syncStatus != .syncing else {
            return
        }
        
        await MainActor.run {
            syncStatus = .syncing
            syncError = nil
        }
        
        do {
            // Trigger CloudKit sync by saving the context
            let context = container.viewContext
            if context.hasChanges {
                try context.save()
            }
            
            // Force a remote sync check by accessing the coordinator
            _ = container.persistentStoreCoordinator
            
        } catch {
            let errorMessage = error.localizedDescription
            
            await MainActor.run {
                syncStatus = .error(errorMessage)
                syncError = errorMessage
            }
        }
    }
    
    // MARK: - Manual Actions
    
    func forceSyncNow() {
        Task { @MainActor in
            await triggerSync()
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
            let container = CKContainer(identifier: "iCloud.com.bobk.SolidarityFundr")
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }
    
    func getCloudKitStatusMessage() async -> String {
        let status = await checkCloudKitStatus()
        
        switch status {
        case .available:
            return "CloudKit Available"
        case .noAccount:
            return "No iCloud Account"
        case .restricted:
            return "iCloud Restricted"
        case .couldNotDetermine:
            return "CloudKit Status Unknown"
        case .temporarilyUnavailable:
            return "CloudKit Temporarily Unavailable"
        @unknown default:
            return "Unknown CloudKit Status"
        }
    }
}