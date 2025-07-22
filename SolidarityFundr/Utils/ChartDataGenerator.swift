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
        
        // Fetch ALL transactions to properly calculate historical balances
        let allTransactionsRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        allTransactionsRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: true)]
        let allTransactions = (try? context.fetch(allTransactionsRequest)) ?? []
        
        // Get initial fund settings
        let fundSettings = FundSettings.fetchOrCreate(in: context)
        let initialBobInvestment = fundSettings.bobInitialInvestment
        
        // Debug logging
        print("📊 Chart Data Generator - Period: \(period)")
        print("   - Total Transactions: \(allTransactions.count)")
        print("   - Date Range: \(startDate) to \(endDate)")
        print("   - Initial Bob Investment: \(initialBobInvestment)")
        
        // Generate data points using forward calculation
        var dataPoints: [(date: Date, value: Double)] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            // Calculate fund balance at this point in time
            var balanceAtDate = initialBobInvestment // Start with Bob's initial investment
            
            // Add up all transactions up to this date
            for transaction in allTransactions {
                guard let transDate = transaction.transactionDate, transDate <= currentDate else { continue }
                
                // Apply transaction based on its impact on the fund
                let fundImpact = getFundImpact(for: transaction)
                balanceAtDate += fundImpact
                
                // Debug first few transactions
                if allTransactions.firstIndex(of: transaction) ?? 0 < 5 {
                    print("   Transaction: \(transaction.transactionType.displayName) - Amount: \(transaction.amount) - Fund Impact: \(fundImpact) - Running Balance: \(balanceAtDate)")
                }
            }
            
            dataPoints.append((date: currentDate, value: max(0, balanceAtDate)))
            currentDate = calendar.date(byAdding: interval, value: 1, to: currentDate) ?? endDate
        }
        
        // Add final point with current balance if needed
        if let lastPoint = dataPoints.last, lastPoint.date < endDate {
            // Calculate current actual balance
            var currentBalance = initialBobInvestment
            for transaction in allTransactions {
                currentBalance += getFundImpact(for: transaction)
            }
            dataPoints.append((date: endDate, value: max(0, currentBalance)))
        }
        
        print("   - Generated \(dataPoints.count) fund balance data points")
        
        // Now generate loan balance data for the same period
        let loanDataPoints = generateLoanBalanceData(for: period, startDate: startDate, endDate: endDate, interval: interval, context: context)
        
        return (fundBalance: dataPoints, loanBalance: loanDataPoints)
    }
    
    // Helper method to calculate how a transaction affects the fund balance
    private func getFundImpact(for transaction: Transaction) -> Double {
        switch transaction.transactionType {
        case .contribution:
            return transaction.amount  // Contributions increase fund
        case .loanDisbursement:
            return -abs(transaction.amount)  // Loans decrease fund (money goes out)
        case .loanRepayment:
            return abs(transaction.amount)  // Repayments increase fund (money comes back)
        case .interestApplied:
            return transaction.amount  // Interest increases fund
        case .cashOut:
            return -abs(transaction.amount)  // Cash outs decrease fund
        case .bobInvestment:
            return transaction.amount  // Bob's additional investments increase fund
        case .bobWithdrawal:
            return -abs(transaction.amount)  // Bob's withdrawals decrease fund
        }
    }
    
    private func generateLoanBalanceData(for period: String, startDate: Date, endDate: Date, interval: Calendar.Component, context: NSManagedObjectContext) -> [(date: Date, value: Double)] {
        let calendar = Calendar.current
        
        // Fetch all loan-related transactions
        let loanTransactionRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        loanTransactionRequest.predicate = NSPredicate(format: "type == %@ OR type == %@", 
                                                      TransactionType.loanDisbursement.rawValue,
                                                      TransactionType.loanRepayment.rawValue)
        loanTransactionRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: true)]
        let loanTransactions = (try? context.fetch(loanTransactionRequest)) ?? []
        
        print("📊 Loan Balance Data - Period: \(period)")
        print("   - Total Loan Transactions: \(loanTransactions.count)")
        
        var dataPoints: [(date: Date, value: Double)] = []
        var currentDate = startDate
        
        while currentDate <= endDate {
            var totalOutstanding = 0.0
            
            // Calculate total outstanding loans at this point in time
            for transaction in loanTransactions {
                guard let transDate = transaction.transactionDate, transDate <= currentDate else { continue }
                
                switch transaction.transactionType {
                case .loanDisbursement:
                    // Loan disbursements increase outstanding balance
                    totalOutstanding += abs(transaction.amount)
                    if loanTransactions.firstIndex(of: transaction) ?? 0 < 5 {
                        print("   Loan Disbursement: +\(abs(transaction.amount)) on \(transDate)")
                    }
                case .loanRepayment:
                    // Loan repayments decrease outstanding balance
                    totalOutstanding -= abs(transaction.amount)
                    if loanTransactions.firstIndex(of: transaction) ?? 0 < 5 {
                        print("   Loan Repayment: -\(abs(transaction.amount)) on \(transDate)")
                    }
                default:
                    break
                }
            }
            
            // Ensure we don't have negative outstanding loans
            totalOutstanding = max(0, totalOutstanding)
            
            dataPoints.append((date: currentDate, value: totalOutstanding))
            currentDate = calendar.date(byAdding: interval, value: 1, to: currentDate) ?? endDate
        }
        
        // Add final point with current balance if needed
        if let lastPoint = dataPoints.last, lastPoint.date < endDate {
            // Calculate current outstanding from all loan transactions
            var currentOutstanding = 0.0
            for transaction in loanTransactions {
                switch transaction.transactionType {
                case .loanDisbursement:
                    currentOutstanding += abs(transaction.amount)
                case .loanRepayment:
                    currentOutstanding -= abs(transaction.amount)
                default:
                    break
                }
            }
            dataPoints.append((date: endDate, value: max(0, currentOutstanding)))
        }
        
        print("   - Generated \(dataPoints.count) loan balance data points")
        print("   - Final outstanding: \(dataPoints.last?.value ?? 0)")
        
        return dataPoints
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