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
        let totalContributions = calculateTotalContributions()
        let activeLoans = calculateTotalActiveLoans()
        let withdrawnAmounts = calculateTotalWithdrawn()
        
        return totalContributions + bobRemainingInvestment + totalInterestApplied - activeLoans - withdrawnAmounts
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
        let context = self.managedObjectContext ?? PersistenceController.shared.container.viewContext
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
}