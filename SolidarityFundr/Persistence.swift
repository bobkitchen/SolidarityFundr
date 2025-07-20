//
//  Persistence.swift
//  SolidarityFundr
//
//  Created by Bob Kitchen on 7/19/25.
//

import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample data for previews
        let sampleMember = Member(context: viewContext)
        sampleMember.memberID = UUID()
        sampleMember.name = "John Doe"
        sampleMember.role = MemberRole.driver.rawValue
        sampleMember.status = MemberStatus.active.rawValue
        sampleMember.joinDate = Date()
        sampleMember.totalContributions = 10000
        sampleMember.createdAt = Date()
        sampleMember.updatedAt = Date()
        
        let sampleLoan = Loan(context: viewContext)
        sampleLoan.loanID = UUID()
        sampleLoan.member = sampleMember
        sampleLoan.amount = 20000
        sampleLoan.balance = 15000
        sampleLoan.repaymentMonths = 3
        sampleLoan.monthlyPayment = 8667
        sampleLoan.issueDate = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        sampleLoan.dueDate = Date().addingTimeInterval(60 * 24 * 60 * 60)
        sampleLoan.status = LoanStatus.active.rawValue
        sampleLoan.createdAt = Date()
        sampleLoan.updatedAt = Date()
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "SolidarityFundr")
        
        // Configure for CloudKit
        if let description = container.persistentStoreDescriptions.first {
            // Enable CloudKit syncing
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            } else {
                // Configure CloudKit container options
                let cloudKitOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.bobk.SolidarityFundr")
                cloudKitOptions.databaseScope = .private
                description.cloudKitContainerOptions = cloudKitOptions
            }
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // In production, handle this error gracefully
                print("Core Data failed to load: \(error.localizedDescription)")
                
                #if DEBUG
                fatalError("Unresolved error \(error), \(error.userInfo)")
                #endif
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Configure merge policy
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Set up CloudKit sync monitoring
        setupCloudKitSync()
    }
    
    private func setupCloudKitSync() {
        // Monitor CloudKit sync events
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }
            
            if event.type == .setup {
                print("CloudKit setup: \(event.succeeded ? "Succeeded" : "Failed")")
                if let error = event.error {
                    print("CloudKit setup error: \(error.localizedDescription)")
                }
            } else if event.type == .import {
                print("CloudKit import: \(event.succeeded ? "Succeeded" : "Failed")")
            } else if event.type == .export {
                print("CloudKit export: \(event.succeeded ? "Succeeded" : "Failed")")
            }
        }
    }
}