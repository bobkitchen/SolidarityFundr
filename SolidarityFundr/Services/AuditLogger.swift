//
//  AuditLogger.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import Foundation
import CoreData
import SwiftUI

/// Audit entries are written via a dedicated background context so callers
/// can log from any thread without corrupting `viewContext`. Entries are
/// append-only by policy — there is no public delete API.
class AuditLogger {
    static let shared = AuditLogger()
    private let persistenceController: PersistenceController

    enum AuditEventType: String, CaseIterable {
        case authentication = "Authentication"
        case loanCreated = "Loan Created"
        case loanModified = "Loan Modified"
        case paymentCreated = "Payment Created"
        case memberCreated = "Member Created"
        case memberModified = "Member Modified"
        case memberSuspended = "Member Suspended"
        case memberReactivated = "Member Reactivated"
        case memberCashedOut = "Member Cashed Out"
        case memberDeleted = "Member Deleted"
        case dataExported = "Data Exported"
        case dataImported = "Data Imported"
        case settingsChanged = "Settings Changed"
        case interestApplied = "Interest Applied"
        case securitySettingsChanged = "Security Settings Changed"
        case sessionTimeout = "Session Timeout"
        case accessDenied = "Access Denied"

        /// Symbol used in the History timeline for this event type.
        var systemImage: String {
            switch self {
            case .authentication, .accessDenied, .sessionTimeout, .securitySettingsChanged:
                return "lock.shield"
            case .loanCreated, .loanModified:
                return "creditcard"
            case .paymentCreated:
                return "dollarsign.circle"
            case .memberCreated:
                return "person.crop.circle.badge.plus"
            case .memberModified:
                return "person.crop.circle.badge"
            case .memberSuspended:
                return "person.crop.circle.badge.minus"
            case .memberReactivated:
                return "person.crop.circle.badge.checkmark"
            case .memberCashedOut:
                return "banknote"
            case .memberDeleted:
                return "person.crop.circle.badge.xmark"
            case .dataExported:
                return "square.and.arrow.up"
            case .dataImported:
                return "square.and.arrow.down"
            case .settingsChanged:
                return "gear"
            case .interestApplied:
                return "percent"
            }
        }

        /// Tint colour for the timeline icon.
        var tint: Color {
            switch self {
            case .accessDenied, .sessionTimeout, .memberDeleted: return .red
            case .memberSuspended, .memberCashedOut, .interestApplied: return .orange
            case .loanCreated, .loanModified: return BrandColor.honey
            case .paymentCreated, .memberReactivated: return .green
            case .memberCreated, .memberModified: return BrandColor.olive
            case .dataExported, .dataImported, .settingsChanged: return .blue
            case .authentication, .securitySettingsChanged: return .purple
            }
        }
    }
    
    private init() {
        self.persistenceController = PersistenceController.shared
    }

    /// Read-only context used for fetches. Audit writes happen on background contexts.
    private var readContext: NSManagedObjectContext {
        persistenceController.container.viewContext
    }

    // MARK: - Logging Methods

    func log(event: AuditEventType,
             details: String? = nil,
             amount: Double? = nil,
             memberID: UUID? = nil,
             loanID: UUID? = nil) {
        let bgContext = persistenceController.container.newBackgroundContext()
        let device = getDeviceInfo()
        bgContext.perform {
            let auditEntry = AuditLog(context: bgContext)
            auditEntry.eventID = UUID()
            auditEntry.eventType = event.rawValue
            auditEntry.timestamp = Date()
            auditEntry.details = details
            auditEntry.amount = amount ?? 0
            auditEntry.memberID = memberID
            auditEntry.loanID = loanID
            auditEntry.deviceInfo = device

            do {
                try bgContext.save()
            } catch {
                print("Failed to save audit log: \(error)")
            }
        }
    }
    
    // MARK: - Query Methods
    
    func fetchLogs(for eventType: AuditEventType? = nil,
                   from startDate: Date? = nil,
                   to endDate: Date? = nil,
                   limit: Int = 100) -> [AuditLog] {
        
        let request = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        var predicates: [NSPredicate] = []
        
        if let eventType = eventType {
            predicates.append(NSPredicate(format: "eventType == %@", eventType.rawValue))
        }
        
        if let startDate = startDate {
            predicates.append(NSPredicate(format: "timestamp >= %@", startDate as NSDate))
        }
        
        if let endDate = endDate {
            predicates.append(NSPredicate(format: "timestamp <= %@", endDate as NSDate))
        }
        
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try readContext.fetch(request)
        } catch {
            print("Failed to fetch audit logs: \(error)")
            return []
        }
    }
    
    func fetchSecurityEvents(limit: Int = 50) -> [AuditLog] {
        let securityEventTypes = [
            AuditEventType.authentication.rawValue,
            AuditEventType.securitySettingsChanged.rawValue,
            AuditEventType.sessionTimeout.rawValue,
            AuditEventType.accessDenied.rawValue,
            AuditEventType.dataExported.rawValue,
            AuditEventType.dataImported.rawValue
        ]
        
        let request = NSFetchRequest<AuditLog>(entityName: "AuditLog")
        request.predicate = NSPredicate(format: "eventType IN %@", securityEventTypes)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try readContext.fetch(request)
        } catch {
            print("Failed to fetch security events: \(error)")
            return []
        }
    }
    
    // MARK: - Helper Methods
    
    private func getDeviceInfo() -> String {
        let processInfo = ProcessInfo.processInfo
        return "\(processInfo.hostName) - macOS \(processInfo.operatingSystemVersionString)"
    }
    
    // MARK: - Cleanup
    //
    // Audit logs are append-only by policy. There is no public delete API.
    // If retention pruning is ever required, add an explicit admin-confirmed
    // flow that signs the cleanup event into a separate tamper-evident store.
}