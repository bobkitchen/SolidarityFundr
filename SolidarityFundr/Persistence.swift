//
//  Persistence.swift
//  SolidarityFundr
//
//  Created by Bob Kitchen on 7/19/25.
//

import CoreData
import CloudKit
import os.log

private let cloudKitLog = Logger(subsystem: "com.solidarityfundr.app", category: "CloudKit")

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

        if let description = container.persistentStoreDescriptions.first {
            // Persistent history tracking + remote-change notifications are
            // both required for NSPersistentCloudKitContainer to mirror to
            // CloudKit correctly.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            } else {
                let cloudKitOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: "iCloud.com.bobk.SolidarityFundr"
                )
                cloudKitOptions.databaseScope = .private
                description.cloudKitContainerOptions = cloudKitOptions
            }
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                cloudKitLog.fault("Core Data failed to load: \(error.localizedDescription, privacy: .public)")
                #if DEBUG
                fatalError("Unresolved error \(error), \(error.userInfo)")
                #endif
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Schema deployment — only in debug builds, only once per run, only
        // for the configured CloudKit store. This pushes the local Core Data
        // schema to CloudKit's Development environment so a fresh iCloud
        // account on a new device sees the right record types and can sync.
        // Production users will hit the already-promoted Production schema.
        #if DEBUG
        if !inMemory {
            initializeCloudKitSchema()
        }
        #endif

        // Note: NSPersistentCloudKitContainer.eventChangedNotification is
        // observed by CloudKitSyncManager — the canonical place to surface
        // setup/import/export events to the UI. We don't observe it here to
        // avoid duplicate handlers.
    }

    /// Pushes the local Core Data schema to the CloudKit Development
    /// container. Idempotent — safe to call on every debug launch.
    /// Apple recommends running this in DEBUG only; production apps should
    /// promote the schema to Production via the CloudKit Dashboard.
    #if DEBUG
    private func initializeCloudKitSchema() {
        do {
            try container.initializeCloudKitSchema(options: [])
            cloudKitLog.info("CloudKit schema initialized")
        } catch {
            cloudKitLog.error("CloudKit schema initialization failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}
