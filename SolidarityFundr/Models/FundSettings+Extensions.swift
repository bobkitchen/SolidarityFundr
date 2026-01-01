//
//  FundSettings+Extensions.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import CoreData

extension FundSettings {
    var shouldWarnUtilization: Bool {
        return calculateUtilizationPercentage() >= utilizationWarningThreshold
    }
    
    var shouldWarnMinimumBalance: Bool {
        return calculateFundBalance() < minimumFundBalance
    }
    
    func calculateUtilizationPercentage() -> Double {
        // Calculate utilization as active loans divided by total capital
        // Total capital = initial investment + all contributions
        let totalCapital = calculateTotalCapital()
        guard totalCapital > 0 else {
            print("⚠️ WARNING: Total capital is 0 in calculateUtilizationPercentage")
            return 0
        }
        
        let activeLoans = calculateTotalActiveLoans()
        let utilization = activeLoans / totalCapital
        // Debug logging commented out to reduce console noise
        // print("📊 Utilization calc - Capital: \(totalCapital), Loans: \(activeLoans), Util: \(utilization * 100)%")
        return utilization
    }
    
    func calculateFundBalance() -> Double {
        // Get the balance from the most recent transaction
        let context = self.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: false)]
        request.fetchLimit = 1
        
        do {
            if let lastTransaction = try context.fetch(request).first {
                return lastTransaction.balance
            }
        } catch {
            print("Error fetching last transaction: \(error)")
        }
        
        // Fallback to Bob's initial investment if no transactions exist
        return bobInitialInvestment
    }
    
    func calculateTotalCapital() -> Double {
        // Total capital is the initial investment plus all contributions
        // This represents the total funds put into the system
        let totalContributions = calculateTotalContributions()
        let capital = bobInitialInvestment + totalContributions
        // Debug logging commented out to reduce console noise
        // print("💵 Total capital calculation - Initial: \(bobInitialInvestment), Contributions: \(totalContributions), Total: \(capital)")
        return capital
    }
    
    private func calculateTotalContributions() -> Double {
        let context = self.managedObjectContext ?? PersistenceController.shared.container.viewContext
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
        // Calculate by summing balance from all active Loan entities (ground truth)
        // This is more reliable than the transaction ledger which can drift
        let context = self.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Loan> = Loan.fetchRequest()
        request.predicate = NSPredicate(format: "status == %@", LoanStatus.active.rawValue)

        do {
            let activeLoans = try context.fetch(request)
            let totalBalance = activeLoans.reduce(0) { $0 + $1.balance }
            return totalBalance
        } catch {
            print("Error fetching active loans: \(error)")
            return 0
        }
    }
    
    private func calculateTotalWithdrawn() -> Double {
        let context = self.managedObjectContext ?? PersistenceController.shared.container.viewContext
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
    
    func applyAnnualInterest() {
        let fundBalance = calculateFundBalance()
        let interestAmount = fundBalance * annualInterestRate
        
        totalInterestApplied += interestAmount
        lastInterestAppliedDate = Date()
        updatedAt = Date()
    }
    
    static func fetchOrCreate(in context: NSManagedObjectContext) -> FundSettings {
        let request = NSFetchRequest<FundSettings>(entityName: "FundSettings")
        request.fetchLimit = 1
        
        do {
            if let existing = try context.fetch(request).first {
                return existing
            }
        } catch {
            print("Error fetching fund settings: \(error)")
        }
        
        let settings = FundSettings(context: context)
        settings.createdAt = Date()
        settings.updatedAt = Date()
        
        return settings
    }
    
    // MARK: - Statement Settings
    
    var statementDayOfMonth: Int {
        get {
            return Int(smsStatementDay)
        }
        set {
            smsStatementDay = Int16(max(1, min(28, newValue))) // Ensure valid day
        }
    }
    
    var isTimeToSendStatements: Bool {
        let calendar = Calendar.current
        let today = Date()
        let currentDay = calendar.component(.day, from: today)
        return currentDay == statementDayOfMonth && smsNotificationsEnabled
    }
    
    func getNextStatementDate() -> Date? {
        let calendar = Calendar.current
        let today = Date()
        let currentDay = calendar.component(.day, from: today)
        
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = Int(smsStatementDay)
        
        if let nextDate = calendar.date(from: components), nextDate > today {
            return nextDate
        } else {
            // Next month
            components.month! += 1
            return calendar.date(from: components)
        }
    }
}