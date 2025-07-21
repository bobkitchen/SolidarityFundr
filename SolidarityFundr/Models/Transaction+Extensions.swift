//
//  Transaction+Extensions.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import CoreData

extension Transaction {
    var transactionType: TransactionType {
        get {
            return TransactionType(rawValue: type ?? "contribution") ?? .contribution
        }
        set {
            type = newValue.rawValue
        }
    }
    
    var displayAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "KES"
        formatter.maximumFractionDigits = 0
        
        let prefix = transactionType.isCredit ? "+" : "-"
        return prefix + (formatter.string(from: NSNumber(value: abs(amount))) ?? "KSH 0")
    }
    
    var displayBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "KES"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balance)) ?? "KSH 0"
    }
    
    static func customFetchRequest(predicate: NSPredicate? = nil,
                                  sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: false)]) -> NSFetchRequest<Transaction> {
        let request = NSFetchRequest<Transaction>(entityName: "Transaction")
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return request
    }
    
    static func transactionsForMember(_ member: Member) -> NSFetchRequest<Transaction> {
        return customFetchRequest(predicate: NSPredicate(format: "member == %@", member))
    }
    
    static func transactionsBetween(startDate: Date, endDate: Date) -> NSFetchRequest<Transaction> {
        let predicate = NSPredicate(format: "transactionDate >= %@ AND transactionDate <= %@", startDate as NSDate, endDate as NSDate)
        return customFetchRequest(predicate: predicate)
    }
}

enum TransactionType: String, CaseIterable {
    case contribution = "contribution"
    case loanDisbursement = "loan_disbursement"
    case loanRepayment = "loan_repayment"
    case interestApplied = "interest_applied"
    case cashOut = "cash_out"
    case bobInvestment = "bob_investment"
    case bobWithdrawal = "bob_withdrawal"
    
    var displayName: String {
        switch self {
        case .contribution:
            return "Contribution"
        case .loanDisbursement:
            return "Loan Disbursement"
        case .loanRepayment:
            return "Loan Repayment"
        case .interestApplied:
            return "Interest Applied"
        case .cashOut:
            return "Cash Out"
        case .bobInvestment:
            return "Bob's Investment"
        case .bobWithdrawal:
            return "Bob's Withdrawal"
        }
    }
    
    var isCredit: Bool {
        switch self {
        case .contribution, .interestApplied, .bobInvestment:
            return true
        case .loanDisbursement, .loanRepayment, .cashOut, .bobWithdrawal:
            return false
        }
    }
}