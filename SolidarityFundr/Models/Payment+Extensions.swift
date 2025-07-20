//
//  Payment+Extensions.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import CoreData

extension Payment {
    var paymentType: PaymentType {
        get {
            return PaymentType(rawValue: type ?? "contribution") ?? .contribution
        }
        set {
            type = newValue.rawValue
        }
    }
    
    var paymentMethodType: PaymentMethod {
        get {
            return PaymentMethod(rawValue: paymentMethod ?? "cash") ?? .cash
        }
        set {
            paymentMethod = newValue.rawValue
        }
    }
    
    var displayAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "KES"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "KSH 0"
    }
    
    static func customFetchRequest(predicate: NSPredicate? = nil,
                                  sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \Payment.paymentDate, ascending: false)]) -> NSFetchRequest<Payment> {
        let request = NSFetchRequest<Payment>(entityName: "Payment")
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return request
    }
    
    static func paymentsForMember(_ member: Member) -> NSFetchRequest<Payment> {
        return customFetchRequest(predicate: NSPredicate(format: "member == %@", member))
    }
    
    static func paymentsForLoan(_ loan: Loan) -> NSFetchRequest<Payment> {
        return customFetchRequest(predicate: NSPredicate(format: "loan == %@", loan))
    }
    
    static func paymentsBetween(startDate: Date, endDate: Date) -> NSFetchRequest<Payment> {
        let predicate = NSPredicate(format: "paymentDate >= %@ AND paymentDate <= %@", startDate as NSDate, endDate as NSDate)
        return customFetchRequest(predicate: predicate)
    }
}

enum PaymentType: String, CaseIterable {
    case contribution = "contribution"
    case loanRepayment = "loan_repayment"
    case mixed = "mixed"
    
    var displayName: String {
        switch self {
        case .contribution:
            return "Contribution"
        case .loanRepayment:
            return "Loan Repayment"
        case .mixed:
            return "Loan + Contribution"
        }
    }
}

enum PaymentMethod: String, CaseIterable {
    case cash = "cash"
    case mpesa = "mpesa"
    case bankTransfer = "bank_transfer"
    case cheque = "cheque"
    
    var displayName: String {
        switch self {
        case .cash:
            return "Cash"
        case .mpesa:
            return "M-Pesa"
        case .bankTransfer:
            return "Bank Transfer"
        case .cheque:
            return "Cheque"
        }
    }
}