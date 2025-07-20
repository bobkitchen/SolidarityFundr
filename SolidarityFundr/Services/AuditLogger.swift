//
//  AuditLogger.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import Foundation
import CoreData

class AuditLogger {
    static let shared = AuditLogger()
    private let context: NSManagedObjectContext
    
    enum AuditEventType: String {
        case authentication = "Authentication"
        case loanCreated = "Loan Created"
        case loanModified = "Loan Modified"
        case paymentCreated = "Payment Created"
        case memberCreated = "Member Created"
        case memberModified = "Member Modified"
        case dataExported = "Data Exported"
        case dataImported = "Data Imported"
        case settingsChanged = "Settings Changed"
        case interestApplied = "Interest Applied"
        case securitySettingsChanged = "Security Settings Changed"
        case sessionTimeout = "Session Timeout"
        case accessDenied = "Access Denied"
    }
    
    private init() {
        self.context = PersistenceController.shared.container.viewContext
    }
    
    // MARK: - Logging Methods
    
    func log(event: AuditEventType, 
             details: String? = nil,
             amount: Double? = nil,
             memberID: UUID? = nil,
             loanID: UUID? = nil) {
        
        let auditEntry = AuditLog(context: context)
        auditEntry.eventID = UUID()
        auditEntry.eventType = event.rawValue
        auditEntry.timestamp = Date()
        auditEntry.details = details
        auditEntry.amount = amount ?? 0
        auditEntry.memberID = memberID
        auditEntry.loanID = loanID
        auditEntry.deviceInfo = getDeviceInfo()
        
        do {
            try context.save()
        } catch {
            print("Failed to save audit log: \(error)")
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
            return try context.fetch(request)
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
            return try context.fetch(request)
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
    
    func cleanupOldLogs(olderThan days: Int = 90) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "AuditLog")
        request.predicate = NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        
        do {
            try context.execute(deleteRequest)
            try context.save()
        } catch {
            print("Failed to cleanup old logs: \(error)")
        }
    }
}