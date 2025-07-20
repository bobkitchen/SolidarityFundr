//
//  FundCalculator.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import CoreData

class FundCalculator {
    static let shared = FundCalculator()
    
    private let context: NSManagedObjectContext
    
    private init() {
        self.context = PersistenceController.shared.container.viewContext
    }
    
    // MARK: - Fund Balance Calculations
    
    func calculateFundBalance(settings: FundSettings? = nil) -> Double {
        let fundSettings = settings ?? FundSettings.fetchOrCreate(in: context)
        
        let totalContributions = calculateTotalContributions()
        let totalActiveLoans = calculateTotalActiveLoans()
        let totalWithdrawn = calculateTotalWithdrawn()
        let bobInvestment = fundSettings.bobRemainingInvestment
        let totalInterest = fundSettings.totalInterestApplied
        
        return totalContributions + bobInvestment + totalInterest - totalActiveLoans - totalWithdrawn
    }
    
    func calculateTotalContributions() -> Double {
        let request = NSFetchRequest<NSDictionary>(entityName: "Member")
        request.resultType = .dictionaryResultType
        
        let sumExpression = NSExpression(forKeyPath: "totalContributions")
        let sumDescription = NSExpressionDescription()
        sumDescription.name = "sum"
        sumDescription.expression = NSExpression(forFunction: "sum:", arguments: [sumExpression])
        sumDescription.expressionResultType = .doubleAttributeType
        
        request.propertiesToFetch = [sumDescription]
        
        do {
            let results = try context.fetch(request)
            return (results.first?["sum"] as? Double) ?? 0
        } catch {
            print("Error calculating total contributions: \(error)")
            return 0
        }
    }
    
    func calculateTotalActiveLoans() -> Double {
        let request = NSFetchRequest<NSDictionary>(entityName: "Loan")
        request.predicate = NSPredicate(format: "status == %@", LoanStatus.active.rawValue)
        request.resultType = .dictionaryResultType
        
        let sumExpression = NSExpression(forKeyPath: "balance")
        let sumDescription = NSExpressionDescription()
        sumDescription.name = "sum"
        sumDescription.expression = NSExpression(forFunction: "sum:", arguments: [sumExpression])
        sumDescription.expressionResultType = .doubleAttributeType
        
        request.propertiesToFetch = [sumDescription]
        
        do {
            let results = try context.fetch(request)
            return (results.first?["sum"] as? Double) ?? 0
        } catch {
            print("Error calculating total active loans: \(error)")
            return 0
        }
    }
    
    func calculateTotalWithdrawn() -> Double {
        let request = NSFetchRequest<NSDictionary>(entityName: "Member")
        request.resultType = .dictionaryResultType
        
        let sumExpression = NSExpression(forKeyPath: "cashOutAmount")
        let sumDescription = NSExpressionDescription()
        sumDescription.name = "sum"
        sumDescription.expression = NSExpression(forFunction: "sum:", arguments: [sumExpression])
        sumDescription.expressionResultType = .doubleAttributeType
        
        request.propertiesToFetch = [sumDescription]
        
        do {
            let results = try context.fetch(request)
            return (results.first?["sum"] as? Double) ?? 0
        } catch {
            print("Error calculating total withdrawn: \(error)")
            return 0
        }
    }
    
    // MARK: - Utilization Calculations
    
    func calculateUtilizationPercentage(settings: FundSettings? = nil) -> Double {
        let fundBalance = calculateFundBalance(settings: settings)
        guard fundBalance > 0 else { return 0 }
        
        let activeLoans = calculateTotalActiveLoans()
        return activeLoans / fundBalance
    }
    
    func calculateUtilizationAfterLoan(loanAmount: Double, settings: FundSettings? = nil) -> Double {
        let fundBalance = calculateFundBalance(settings: settings)
        guard fundBalance > 0 else { return 0 }
        
        let currentActiveLoans = calculateTotalActiveLoans()
        let newActiveLoans = currentActiveLoans + loanAmount
        
        return newActiveLoans / fundBalance
    }
    
    // MARK: - Member Calculations
    
    func calculateMemberCashOut(member: Member, interestRate: Double = 0.13) -> Double {
        let contributions = member.totalContributions
        let interest = contributions * interestRate
        return contributions + interest
    }
    
    func calculateMemberMonthlyContributions(member: Member) -> [MonthlyContribution] {
        let request = Payment.paymentsForMember(member)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "member == %@", member),
            NSPredicate(format: "contributionAmount > 0")
        ])
        
        do {
            let payments = try context.fetch(request)
            return aggregatePaymentsByMonth(payments)
        } catch {
            print("Error fetching member contributions: \(error)")
            return []
        }
    }
    
    private func aggregatePaymentsByMonth(_ payments: [Payment]) -> [MonthlyContribution] {
        let calendar = Calendar.current
        var contributionsByMonth: [String: Double] = [:]
        
        for payment in payments {
            guard let date = payment.paymentDate else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)
            let key = "\(components.year ?? 0)-\(String(format: "%02d", components.month ?? 0))"
            contributionsByMonth[key, default: 0] += payment.contributionAmount
        }
        
        return contributionsByMonth.map { MonthlyContribution(monthKey: $0.key, amount: $0.value) }
            .sorted { $0.monthKey < $1.monthKey }
    }
    
    // MARK: - Loan Calculations
    
    func calculateLoanSchedule(amount: Double, months: Int, startDate: Date = Date()) -> [LoanPaymentSchedule] {
        let monthlyLoanPayment = amount / Double(months)
        
        var schedule: [LoanPaymentSchedule] = []
        var remainingBalance = amount
        
        for month in 1...months {
            let dueDate = Calendar.current.date(byAdding: .month, value: month, to: startDate)!
            let principalPayment = min(monthlyLoanPayment, remainingBalance)
            remainingBalance -= principalPayment
            
            schedule.append(LoanPaymentSchedule(
                paymentNumber: month,
                dueDate: dueDate,
                totalPayment: monthlyLoanPayment,
                principalPayment: principalPayment,
                contributionAmount: 0,
                remainingBalance: remainingBalance
            ))
        }
        
        return schedule
    }
    
    // MARK: - Interest Calculations
    
    func calculateAnnualInterest(settings: FundSettings? = nil) -> Double {
        let fundSettings = settings ?? FundSettings.fetchOrCreate(in: context)
        let fundBalance = calculateFundBalance(settings: fundSettings)
        return fundBalance * fundSettings.annualInterestRate
    }
    
    func calculateInterestToDate(member: Member, interestRate: Double = 0.13) -> Double {
        guard let joinDate = member.joinDate else { return 0 }
        
        let monthsSinceJoining = Calendar.current.dateComponents([.month], from: joinDate, to: Date()).month ?? 0
        let yearsAsDecimal = Double(monthsSinceJoining) / 12.0
        
        // Simple interest calculation
        return member.totalContributions * interestRate * yearsAsDecimal
    }
    
    // MARK: - Report Calculations
    
    func generateFundSummary(settings: FundSettings? = nil) -> FundSummary {
        let fundSettings = settings ?? FundSettings.fetchOrCreate(in: context)
        
        return FundSummary(
            totalContributions: calculateTotalContributions(),
            bobInvestment: fundSettings.bobInitialInvestment,
            bobRemainingInvestment: fundSettings.bobRemainingInvestment,
            totalInterestApplied: fundSettings.totalInterestApplied,
            totalActiveLoans: calculateTotalActiveLoans(),
            totalWithdrawn: calculateTotalWithdrawn(),
            fundBalance: calculateFundBalance(settings: fundSettings),
            utilizationPercentage: calculateUtilizationPercentage(settings: fundSettings),
            activeMembers: countActiveMembers(),
            totalMembers: countTotalMembers(),
            activeLoansCount: countActiveLoans()
        )
    }
    
    private func countActiveMembers() -> Int {
        let request = NSFetchRequest<Member>(entityName: "Member")
        request.predicate = NSPredicate(format: "status == %@", MemberStatus.active.rawValue)
        
        do {
            return try context.count(for: request)
        } catch {
            print("Error counting active members: \(error)")
            return 0
        }
    }
    
    private func countTotalMembers() -> Int {
        let request = NSFetchRequest<Member>(entityName: "Member")
        
        do {
            return try context.count(for: request)
        } catch {
            print("Error counting total members: \(error)")
            return 0
        }
    }
    
    private func countActiveLoans() -> Int {
        let request = NSFetchRequest<Loan>(entityName: "Loan")
        request.predicate = NSPredicate(format: "status == %@", LoanStatus.active.rawValue)
        
        do {
            return try context.count(for: request)
        } catch {
            print("Error counting active loans: \(error)")
            return 0
        }
    }
}

// MARK: - Data Models

struct MonthlyContribution {
    let monthKey: String
    let amount: Double
    
    var displayMonth: String {
        let components = monthKey.split(separator: "-")
        guard components.count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]) else {
            return monthKey
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"
        
        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = 1
        
        if let date = Calendar.current.date(from: dateComponents) {
            return dateFormatter.string(from: date)
        }
        
        return monthKey
    }
}

struct LoanPaymentSchedule {
    let paymentNumber: Int
    let dueDate: Date
    let totalPayment: Double
    let principalPayment: Double
    let contributionAmount: Double
    let remainingBalance: Double
}

struct FundSummary {
    let totalContributions: Double
    let bobInvestment: Double
    let bobRemainingInvestment: Double
    let totalInterestApplied: Double
    let totalActiveLoans: Double
    let totalWithdrawn: Double
    let fundBalance: Double
    let utilizationPercentage: Double
    let activeMembers: Int
    let totalMembers: Int
    let activeLoansCount: Int
}