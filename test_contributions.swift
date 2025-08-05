#!/usr/bin/swift

import Foundation
import CoreData

// This is a test script to check contribution calculations
// Run from Xcode's debugger console or Swift REPL

print("Testing contribution recalculation...")

// Get DataManager instance
let dataManager = DataManager.shared

// Find Solomon
let solomonPredicate = NSPredicate(format: "name CONTAINS[cd] %@", "Solomon")
dataManager.fetchMembers(predicate: solomonPredicate)

if let solomon = dataManager.members.first(where: { $0.name?.contains("Solomon") ?? false }) {
    print("\nFound member: \(solomon.name ?? "Unknown")")
    print("Current totalContributions: KSH \(solomon.totalContributions)")
    
    // Fetch all payments for Solomon
    let paymentRequest = Payment.paymentsForMember(solomon)
    let context = dataManager.persistenceController.container.viewContext
    
    do {
        let allPayments = try context.fetch(paymentRequest)
        print("\nAll payments for Solomon:")
        for (index, payment) in allPayments.enumerated() {
            print("  Payment \(index + 1):")
            print("    - Date: \(payment.paymentDate ?? Date())")
            print("    - Amount: KSH \(payment.amount)")
            print("    - Type: \(payment.paymentType.displayName)")
            print("    - Contribution Amount: KSH \(payment.contributionAmount)")
        }
        
        // Now fetch only contribution payments
        let contributionRequest = Payment.paymentsForMember(solomon)
        contributionRequest.predicate = NSPredicate(format: "member == %@ AND type == %@", solomon, PaymentType.contribution.rawValue)
        
        let contributionPayments = try context.fetch(contributionRequest)
        print("\nContribution payments only:")
        let totalContributions = contributionPayments.reduce(0) { $0 + $1.contributionAmount }
        print("  Found \(contributionPayments.count) contributions")
        print("  Total: KSH \(totalContributions)")
        
        // Recalculate
        print("\nRecalculating contributions...")
        dataManager.recalculateMemberContributions(solomon)
        
        print("\nAfter recalculation:")
        print("  totalContributions: KSH \(solomon.totalContributions)")
        
    } catch {
        print("Error fetching payments: \(error)")
    }
} else {
    print("Solomon not found in members list")
}