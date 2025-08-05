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
        let fundBalance = calculateFundBalance()
        guard fundBalance > 0 else { return 0 }
        
        let activeLoans = calculateTotalActiveLoans()
        return (activeLoans / fundBalance)
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
    
    private func calculateTotalActiveLoans() -> Double {
        // Get the loan balance from the most recent transaction
        let context = self.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: false)]
        request.fetchLimit = 1
        
        do {
            if let lastTransaction = try context.fetch(request).first {
                return lastTransaction.loanBalance
            }
        } catch {
            print("Error fetching last transaction for loan balance: \(error)")
        }
        
        return 0
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