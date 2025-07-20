//
//  Member+Extensions.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import CoreData

extension Member {
    var memberRole: MemberRole {
        get {
            return MemberRole(rawValue: role ?? "") ?? .partTime
        }
        set {
            role = newValue.rawValue
        }
    }
    
    var memberStatus: MemberStatus {
        get {
            return MemberStatus(rawValue: status ?? "active") ?? .active
        }
        set {
            status = newValue.rawValue
        }
    }
    
    var activeLoans: [Loan] {
        let loanArray = loans?.allObjects as? [Loan] ?? []
        return loanArray.filter { $0.loanStatus == .active }
    }
    
    var hasActiveLoans: Bool {
        return !activeLoans.isEmpty
    }
    
    var totalActiveLoanBalance: Double {
        return activeLoans.reduce(0) { $0 + $1.balance }
    }
    
    var availableContributions: Double {
        return totalContributions - totalActiveLoanBalance
    }
    
    var loanLimit: Double {
        switch memberRole {
        case .driver, .assistant:
            return 40000
        case .housekeeper, .groundsKeeper:
            return 19000
        case .securityGuard, .partTime:
            return min(totalContributions, 12000)
        }
    }
    
    var monthsAsMember: Int {
        guard let joinDate = joinDate else { return 0 }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: joinDate, to: Date())
        return components.month ?? 0
    }
    
    var isEligibleForLoan: Bool {
        guard memberStatus == .active else { return false }
        
        if memberRole == .securityGuard && monthsAsMember < 3 {
            return false
        }
        
        return true
    }
    
    var maximumLoanAmount: Double {
        guard isEligibleForLoan else { return 0 }
        let currentLoanBalance = totalActiveLoanBalance
        let availableLimit = loanLimit - currentLoanBalance
        return max(0, availableLimit)
    }
    
    func calculateCashOutAmount(interestRate: Double = 0.13) -> Double {
        let interest = totalContributions * interestRate
        return totalContributions + interest
    }
    
    static func customFetchRequest(predicate: NSPredicate? = nil,
                                  sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(keyPath: \Member.name, ascending: true)]) -> NSFetchRequest<Member> {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return request
    }
    
    static func activeMembers() -> NSFetchRequest<Member> {
        return customFetchRequest(predicate: NSPredicate(format: "status == %@", MemberStatus.active.rawValue))
    }
}

enum MemberRole: String, CaseIterable {
    case driver = "Driver"
    case assistant = "Assistant"
    case housekeeper = "Housekeeper"
    case groundsKeeper = "Grounds Keeper"
    case securityGuard = "Guard"
    case partTime = "Part-time"
    
    var displayName: String {
        return self.rawValue
    }
}

enum MemberStatus: String, CaseIterable {
    case active = "active"
    case suspended = "suspended"
    case inactive = "inactive"
    
    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .suspended:
            return "Suspended"
        case .inactive:
            return "Inactive"
        }
    }
}