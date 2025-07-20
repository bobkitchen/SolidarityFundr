//
//  Loan+Extensions.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import CoreData

extension Loan {
    var loanStatus: LoanStatus {
        get {
            return LoanStatus(rawValue: status ?? "active") ?? .active
        }
        set {
            status = newValue.rawValue
        }
    }
    
    var isOverdue: Bool {
        guard loanStatus == .active,
              let dueDate = dueDate else { return false }
        return Date() > dueDate
    }
    
    var remainingPayments: Int {
        guard monthlyPayment > 0 else { return 0 }
        return Int(ceil(balance / monthlyPayment))
    }
    
    var nextPaymentDue: Date? {
        guard loanStatus == .active,
              let issueDate = issueDate else { return nil }
        
        let calendar = Calendar.current
        let paidMonths = Int((amount - balance) / monthlyPayment)
        return calendar.date(byAdding: .month, value: paidMonths + 1, to: issueDate)
    }
    
    var completionPercentage: Double {
        guard amount > 0 else { return 0 }
        return ((amount - balance) / amount) * 100
    }
    
    func calculateMonthlyPayment() -> Double {
        return amount / Double(repaymentMonths)
    }
    
    func processPayment(amount: Double) -> (loanRepayment: Double, contribution: Double) {
        // For loan payments, the entire amount goes to loan repayment
        // Contributions are handled separately
        return (amount, 0)
    }
    
    static func customFetchRequest(predicate: NSPredicate? = nil,
                                  sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \Loan.issueDate, ascending: false)]) -> NSFetchRequest<Loan> {
        let request = NSFetchRequest<Loan>(entityName: "Loan")
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return request
    }
    
    static func activeLoans() -> NSFetchRequest<Loan> {
        return customFetchRequest(predicate: NSPredicate(format: "status == %@", LoanStatus.active.rawValue))
    }
    
    static func overdueLoans() -> NSFetchRequest<Loan> {
        let predicate = NSPredicate(format: "status == %@ AND dueDate < %@", LoanStatus.active.rawValue, Date() as NSDate)
        return customFetchRequest(predicate: predicate)
    }
}

enum LoanStatus: String, CaseIterable {
    case active = "active"
    case completed = "completed"
    case defaulted = "defaulted"
    
    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .completed:
            return "Completed"
        case .defaulted:
            return "Defaulted"
        }
    }
}