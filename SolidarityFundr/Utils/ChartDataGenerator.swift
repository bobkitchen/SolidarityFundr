//
//  ChartDataGenerator.swift
//  SolidarityFundr
//
//  Generates accurate chart data based on actual transaction history
//

import Foundation
import CoreData

class ChartDataGenerator {
    static let shared = ChartDataGenerator()
    private init() {}
    
    // MARK: - Fund Activity Chart Data
    
    func generateFundActivityData(for period: String, context: NSManagedObjectContext) -> (fundBalance: [(date: Date, value: Double)], loanBalance: [(date: Date, value: Double)]) {
        let calendar = Calendar.current
        let endDate = Date()
        var startDate: Date
        var interval: Calendar.Component
        
        // Determine time range and interval based on period
        switch period {
        case "Day":
            startDate = calendar.date(byAdding: .day, value: -1, to: endDate)!
            interval = .hour
        case "Week":
            startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
            interval = .day
        case "Month":
            startDate = calendar.date(byAdding: .month, value: -1, to: endDate)!
            interval = .day
        case "Year":
            startDate = calendar.date(byAdding: .year, value: -1, to: endDate)!
            interval = .month
        default:
            startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!
            interval = .day
        }
        
        // Fetch transactions within the date range
        let transactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        transactionRequest.predicate = NSPredicate(format: "transactionDate >= %@ AND transactionDate <= %@", startDate as NSDate, endDate as NSDate)
        transactionRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: true)]
        let transactions = (try? context.fetch(transactionRequest)) ?? []
        
        // Get the last transaction before the period for starting balance
        let beforePeriodRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        beforePeriodRequest.predicate = NSPredicate(format: "transactionDate < %@", startDate as NSDate)
        beforePeriodRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: false)]
        beforePeriodRequest.fetchLimit = 1
        let lastTransactionBefore = try? context.fetch(beforePeriodRequest).first
        
        let startingFundBalance = lastTransactionBefore?.balance ?? (FundSettings.fetchOrCreate(in: context).bobInitialInvestment)
        let startingLoanBalance = lastTransactionBefore?.loanBalance ?? 0
        
        // Debug logging commented out to reduce console noise
        // print("📊 Chart Data Generator - Period: \(period)")
        // print("   - Transactions in period: \(transactions.count)")
        // print("   - Starting Fund Balance: \(startingFundBalance)")
        // print("   - Starting Loan Balance: \(startingLoanBalance)")
        
        // Generate data points
        var fundDataPoints: [(date: Date, value: Double)] = []
        var loanDataPoints: [(date: Date, value: Double)] = []
        
        // Add starting point
        fundDataPoints.append((date: startDate, value: startingFundBalance))
        loanDataPoints.append((date: startDate, value: startingLoanBalance))
        
        // Add a data point for each transaction to capture all balance changes
        var lastFundBalance = startingFundBalance
        var lastLoanBalance = startingLoanBalance
        
        for transaction in transactions {
            if let transactionDate = transaction.transactionDate {
                // Add the data point at the exact transaction time
                fundDataPoints.append((date: transactionDate, value: transaction.balance))
                loanDataPoints.append((date: transactionDate, value: transaction.loanBalance))
                
                lastFundBalance = transaction.balance
                lastLoanBalance = transaction.loanBalance
            }
        }
        
        // If we don't have enough data points, add intermediate points
        if fundDataPoints.count < 10 {
            var currentDate = startDate
            while currentDate <= endDate {
                // Find the last transaction up to this date
                let lastTransaction = transactions
                    .filter { ($0.transactionDate ?? Date.distantPast) <= currentDate }
                    .last
                
                let fundBalance = lastTransaction?.balance ?? lastFundBalance
                let loanBalance = lastTransaction?.loanBalance ?? lastLoanBalance
                
                // Only add if we don't already have a point at this date
                let hasPoint = fundDataPoints.contains { abs($0.date.timeIntervalSince(currentDate)) < 60 }
                if !hasPoint {
                    fundDataPoints.append((date: currentDate, value: fundBalance))
                    loanDataPoints.append((date: currentDate, value: loanBalance))
                }
                
                currentDate = calendar.date(byAdding: interval, value: 1, to: currentDate) ?? endDate
            }
        }
        
        // Add final point with current balance
        fundDataPoints.append((date: endDate, value: lastFundBalance))
        loanDataPoints.append((date: endDate, value: lastLoanBalance))
        
        // Sort by date to ensure proper chart rendering
        fundDataPoints.sort { $0.date < $1.date }
        loanDataPoints.sort { $0.date < $1.date }
        
        // Debug logging commented out to reduce console noise
        // print("   - Generated \(fundDataPoints.count) fund balance data points")
        // print("   - Generated \(loanDataPoints.count) loan balance data points")
        
        return (fundBalance: fundDataPoints, loanBalance: loanDataPoints)
    }
    
    
    // MARK: - Fund Growth Trend Data
    
    func generateFundGrowthData(months: Int, context: NSManagedObjectContext) -> [(month: String, balance: Double)] {
        let calendar = Calendar.current
        let endDate = Date()
        var dataPoints: [(month: String, balance: Double)] = []
        
        // Go through each month
        for i in (0..<months).reversed() {
            let monthDate = calendar.date(byAdding: .month, value: -i, to: endDate) ?? endDate
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthDate) ?? monthDate
            
            // Get the last transaction of the month
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            request.predicate = NSPredicate(format: "transactionDate < %@", monthEnd as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: false)]
            request.fetchLimit = 1
            
            let lastTransaction = try? context.fetch(request).first
            let balance = lastTransaction?.balance ?? 0
            
            // Format month name
            let monthName = DateFormatter().monthSymbols[calendar.component(.month, from: monthDate) - 1].prefix(3)
            
            if balance > 0 {
                dataPoints.append((month: String(monthName), balance: balance))
            }
        }
        
        // If no historical data, use current balance
        if dataPoints.isEmpty {
            let currentBalance = FundCalculator.shared.generateFundSummary().fundBalance
            let currentMonth = DateFormatter().monthSymbols[calendar.component(.month, from: endDate) - 1].prefix(3)
            dataPoints.append((month: String(currentMonth), balance: currentBalance))
        }
        
        return dataPoints
    }
    
    // MARK: - Monthly Contribution Trend
    
    func generateMonthlyContributionData(months: Int, context: NSManagedObjectContext) -> [(month: String, amount: Double)] {
        let calendar = Calendar.current
        let endDate = Date()
        var dataPoints: [(month: String, amount: Double)] = []
        
        for i in (0..<months).reversed() {
            let monthDate = calendar.date(byAdding: .month, value: -i, to: endDate) ?? endDate
            let monthStart = calendar.startOfDay(for: calendar.dateComponents([.year, .month], from: monthDate).date!)
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            
            // Fetch contributions for this month
            let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
            request.predicate = NSPredicate(format: "transactionDate >= %@ AND transactionDate < %@ AND type == %@", 
                                           monthStart as NSDate, 
                                           monthEnd as NSDate,
                                           TransactionType.contribution.rawValue)
            
            let transactions = (try? context.fetch(request)) ?? []
            let totalContributions = transactions.reduce(0) { $0 + $1.amount }
            
            let monthName = DateFormatter().monthSymbols[calendar.component(.month, from: monthDate) - 1].prefix(3)
            dataPoints.append((month: String(monthName), amount: totalContributions))
        }
        
        return dataPoints
    }
}