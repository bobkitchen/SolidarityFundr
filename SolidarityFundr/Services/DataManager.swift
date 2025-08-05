//
//  DataManager.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import CoreData
import Combine

class DataManager: ObservableObject {
    static let shared = DataManager()
    
    private let persistenceController: PersistenceController
    private let context: NSManagedObjectContext
    
    @Published var fundSettings: FundSettings?
    @Published var members: [Member] = []
    @Published var activeLoans: [Loan] = []
    @Published var recentTransactions: [Transaction] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.persistenceController = PersistenceController.shared
        self.context = persistenceController.container.viewContext
        
        setupFundSettings()
        setupObservers()
        // Defer initial data fetch to avoid publishing changes during initialization
        DispatchQueue.main.async { [weak self] in
            self?.fetchInitialData()
            // Ensure transaction balances are correct on startup
            self?.recalculateAllTransactionBalances()
        }
    }
    
    func setupFundSettings() {
        fundSettings = FundSettings.fetchOrCreate(in: context)
        saveContext()
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                self?.fetchInitialData()
            }
            .store(in: &cancellables)
    }
    
    private func fetchInitialData() {
        fetchMembers()
        fetchActiveLoans()
        fetchRecentTransactions()
        createMissingTransactions()
    }
    
    // MARK: - Member Operations
    
    func fetchMembers(predicate: NSPredicate? = nil) {
        let request = Member.customFetchRequest(predicate: predicate)
        do {
            members = try context.fetch(request)
        } catch {
            print("Error fetching members: \(error)")
        }
    }
    
    @discardableResult
    func createMember(name: String, role: MemberRole, email: String? = nil, phoneNumber: String? = nil, joinDate: Date = Date(), smsOptIn: Bool = false) -> Member {
        let member = Member(context: context)
        member.memberID = UUID()
        member.name = name
        member.memberRole = role
        member.email = email
        member.phoneNumber = phoneNumber
        member.joinDate = joinDate
        member.createdAt = Date()
        member.updatedAt = Date()
        member.memberStatus = .active
        member.totalContributions = 0
        member.smsOptIn = smsOptIn && phoneNumber != nil && PhoneNumberValidator.validate(phoneNumber ?? "")
        
        saveContext()
        fetchMembers()
        
        return member
    }
    
    func updateMember(_ member: Member) {
        member.updatedAt = Date()
        saveContext()
        fetchMembers()
    }
    
    func suspendMember(_ member: Member) {
        member.memberStatus = .suspended
        member.suspendedDate = Date()
        member.updatedAt = Date()
        saveContext()
        fetchMembers()
    }
    
    func reactivateMember(_ member: Member) {
        member.memberStatus = .active
        member.suspendedDate = nil
        member.updatedAt = Date()
        saveContext()
        fetchMembers()
    }
    
    func deleteMember(_ member: Member) throws {
        guard !member.hasActiveLoans else {
            throw DataManagerError.memberHasActiveLoans
        }
        
        context.delete(member)
        saveContext()
        fetchMembers()
    }
    
    func deleteTestUsers() {
        let testUserNames = ["Test User", "John Doe", "Jane Doe", "Test Member", "Sample Member"]
        
        let request: NSFetchRequest<Member> = Member.fetchRequest()
        request.predicate = NSPredicate(format: "name IN %@", testUserNames)
        
        do {
            let testMembers = try context.fetch(request)
            for member in testMembers {
                // Delete associated transactions, loans, and payments
                if let transactions = member.transactions as? Set<Transaction> {
                    for transaction in transactions {
                        context.delete(transaction)
                    }
                }
                if let loans = member.loans as? Set<Loan> {
                    for loan in loans {
                        if let payments = loan.payments as? Set<Payment> {
                            for payment in payments {
                                context.delete(payment)
                            }
                        }
                        context.delete(loan)
                    }
                }
                if let payments = member.payments as? Set<Payment> {
                    for payment in payments {
                        context.delete(payment)
                    }
                }
                
                context.delete(member)
            }
            
            try context.save()
            fetchInitialData() // Refresh all data after deletion
            print("Deleted \(testMembers.count) test users")
        } catch {
            print("Failed to delete test users: \(error)")
        }
    }
    
    // MARK: - Loan Operations
    
    func fetchActiveLoans() {
        let request = Loan.activeLoans()
        do {
            activeLoans = try context.fetch(request)
        } catch {
            print("Error fetching active loans: \(error)")
        }
    }
    
    func createLoan(for member: Member, amount: Double, repaymentMonths: Int, issueDate: Date = Date(), notes: String? = nil) throws -> Loan {
        guard member.isEligibleForLoan else {
            throw DataManagerError.memberNotEligibleForLoan
        }
        
        guard amount <= member.maximumLoanAmount else {
            throw DataManagerError.loanAmountExceedsLimit
        }
        
        let loan = Loan(context: context)
        loan.loanID = UUID()
        loan.member = member
        loan.amount = amount
        loan.balance = amount
        loan.repaymentMonths = Int16(repaymentMonths)
        loan.monthlyPayment = loan.calculateMonthlyPayment()
        loan.issueDate = issueDate
        loan.dueDate = Calendar.current.date(byAdding: .month, value: repaymentMonths, to: issueDate)
        loan.notes = notes
        loan.loanStatus = .active
        loan.createdAt = Date()
        loan.updatedAt = Date()
        
        _ = createTransaction(
            for: member,
            amount: -amount,
            type: .loanDisbursement,
            description: "Loan disbursement of KSH \(Int(amount))"
        )
        
        saveContext()
        fetchActiveLoans()
        
        // Audit log
        AuditLogger.shared.log(
            event: .loanCreated,
            details: "Loan of \(CurrencyFormatter.shared.format(amount)) for \(repaymentMonths) months",
            amount: amount,
            memberID: member.memberID,
            loanID: loan.loanID
        )
        
        return loan
    }
    
    func completeLoan(_ loan: Loan) {
        loan.loanStatus = .completed
        loan.completedDate = Date()
        loan.balance = 0
        loan.updatedAt = Date()
        saveContext()
        fetchActiveLoans()
    }
    
    // MARK: - Payment Operations
    
    func recalculateLoanBalance(_ loan: Loan) {
        // Get all payments for this loan
        let request = Payment.paymentsForLoan(loan)
        let payments = (try? context.fetch(request)) ?? []
        
        // Calculate total paid
        let totalPaid = payments.reduce(0) { $0 + $1.loanRepaymentAmount }
        
        // Update loan balance
        loan.balance = max(0, loan.amount - totalPaid)
        loan.updatedAt = Date()
        
        // Check if loan should be completed
        if loan.balance == 0 && loan.loanStatus == .active {
            completeLoan(loan)
        }
        
        saveContext()
        
        // Notify that loan balance was updated
        NotificationCenter.default.post(name: .loanBalanceUpdated, object: loan)
    }
    
    @discardableResult
    func processPayment(for member: Member, amount: Double, loan: Loan? = nil, method: PaymentMethod = .cash, paymentDate: Date = Date(), notes: String? = nil) throws -> Payment {
        let payment = Payment(context: context)
        payment.paymentID = UUID()
        payment.member = member
        payment.amount = amount
        payment.paymentDate = paymentDate
        payment.paymentMethodType = method
        payment.notes = notes
        payment.createdAt = Date()
        payment.updatedAt = Date()
        
        if let loan = loan, loan.loanStatus == .active {
            // For loan payments, entire amount goes to loan
            payment.loan = loan
            payment.loanRepaymentAmount = amount
            payment.contributionAmount = 0
            payment.paymentType = .loanRepayment
            
            loan.balance = max(0, loan.balance - amount)
            loan.updatedAt = Date()
            
            if loan.balance == 0 {
                completeLoan(loan)
            }
            
            let transaction = createTransaction(
                for: member,
                amount: -amount,  // Negative for loan repayments
                type: .loanRepayment,
                description: "Loan payment: KSH \(Int(amount))"
            )
            payment.transaction = transaction
            
        } else {
            payment.contributionAmount = amount
            payment.paymentType = .contribution
            
            member.totalContributions += amount
            
            let transaction = createTransaction(
                for: member,
                amount: amount,
                type: .contribution,
                description: "Monthly contribution"
            )
            payment.transaction = transaction
        }
        
        member.updatedAt = Date()
        saveContext()
        
        // Refresh recent transactions
        fetchRecentTransactions()
        
        return payment
    }
    
    func recalculateAllMemberContributions() {
        let request: NSFetchRequest<Member> = Member.fetchRequest()
        
        do {
            let allMembers = try context.fetch(request)
            
            for member in allMembers {
                recalculateMemberContributions(member)
            }
            
            print("✅ Recalculated contributions for \(allMembers.count) members")
            
        } catch {
            print("Error recalculating all member contributions: \(error)")
        }
    }
    
    // MARK: - Transaction Operations
    
    func fixIncorrectTransactions() {
        let request: NSFetchRequest<Payment> = Payment.fetchRequest()
        
        do {
            let allPayments = try context.fetch(request)
            var fixedCount = 0
            
            for payment in allPayments {
                guard let transaction = payment.transaction else { continue }
                
                // Check if transaction type matches payment type
                let expectedType: TransactionType = payment.paymentType == .loanRepayment ? .loanRepayment : .contribution
                let expectedAmount = payment.paymentType == .loanRepayment ? -payment.amount : payment.amount
                let expectedDescription = payment.paymentType == .loanRepayment ? "Loan payment: KSH \(Int(payment.amount))" : "Monthly contribution"
                
                if transaction.transactionType != expectedType || transaction.amount != expectedAmount {
                    print("🔧 Fixing transaction for \(payment.member?.name ?? "Unknown")")
                    print("   - Old type: \(transaction.transactionType.displayName), New type: \(expectedType.displayName)")
                    print("   - Old amount: \(transaction.amount), New amount: \(expectedAmount)")
                    
                    transaction.transactionType = expectedType
                    transaction.amount = expectedAmount
                    transaction.transactionDescription = expectedDescription
                    transaction.updatedAt = Date()
                    
                    fixedCount += 1
                }
            }
            
            if fixedCount > 0 {
                saveContext()
                print("✅ Fixed \(fixedCount) incorrect transactions")
            } else {
                print("✓ All transactions are correct")
            }
        } catch {
            print("❌ Error fixing transactions: \(error)")
        }
    }
    
    func createMissingTransactions() {
        let request: NSFetchRequest<Payment> = Payment.fetchRequest()
        request.predicate = NSPredicate(format: "transaction == nil")
        
        do {
            let paymentsWithoutTransactions = try context.fetch(request)
            print("🔍 Found \(paymentsWithoutTransactions.count) payments without transactions")
            
            for payment in paymentsWithoutTransactions {
                let transactionType: TransactionType = payment.paymentType == .loanRepayment ? .loanRepayment : .contribution
                let amount = payment.paymentType == .loanRepayment ? -payment.amount : payment.amount
                let description = payment.paymentType == .loanRepayment ? "Loan payment: KSH \(Int(payment.amount))" : "Monthly contribution"
                
                let transaction = Transaction(context: context)
                transaction.transactionID = UUID()
                transaction.member = payment.member
                transaction.amount = amount
                transaction.transactionType = transactionType
                transaction.transactionDate = payment.paymentDate ?? Date()
                transaction.transactionDescription = description
                transaction.balance = fundSettings?.calculateFundBalance() ?? 0
                transaction.createdAt = payment.createdAt ?? Date()
                transaction.updatedAt = Date()
                
                payment.transaction = transaction
                print("✅ Created transaction for payment: \(payment.member?.name ?? "Unknown") - \(transactionType.displayName)")
            }
            
            if !paymentsWithoutTransactions.isEmpty {
                saveContext()
                print("💾 Saved \(paymentsWithoutTransactions.count) new transactions")
            }
        } catch {
            print("❌ Error creating missing transactions: \(error)")
        }
    }
    
    func fetchRecentTransactions(limit: Int = 50) {
        let request = Transaction.fetchRequest()
        request.fetchLimit = limit
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: false)]
        
        do {
            recentTransactions = try context.fetch(request)
            print("📋 Fetched \(recentTransactions.count) recent transactions")
            if let first = recentTransactions.first {
                print("   Most recent: \(first.transactionType.displayName) - \(first.amount) on \(first.transactionDate ?? Date())")
            }
            
            // Post notification that transactions have been updated
            NotificationCenter.default.post(name: .transactionsUpdated, object: nil)
        } catch {
            print("Error fetching transactions: \(error)")
        }
    }
    
    @discardableResult
    private func createTransaction(for member: Member?, amount: Double, type: TransactionType, description: String? = nil) -> Transaction {
        // Get the previous balance from the most recent transaction
        let previousBalanceRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        previousBalanceRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: false)]
        previousBalanceRequest.fetchLimit = 1
        
        let lastTransaction = try? context.fetch(previousBalanceRequest).first
        let previousFundBalance = lastTransaction?.balance ?? (fundSettings?.bobInitialInvestment ?? 100000)
        let previousLoanBalance = lastTransaction?.loanBalance ?? 0
        
        // Create the new transaction
        let transaction = Transaction(context: context)
        transaction.transactionID = UUID()
        transaction.member = member
        transaction.amount = amount
        transaction.transactionType = type
        transaction.transactionDate = Date()
        transaction.transactionDescription = description
        transaction.previousBalance = previousFundBalance
        
        // Calculate the impact on fund balance
        var fundBalanceChange: Double = 0
        var loanBalanceChange: Double = 0
        
        switch type {
        case .contribution:
            fundBalanceChange = amount  // Increases fund
        case .loanDisbursement:
            fundBalanceChange = -abs(amount)  // Decreases fund
            loanBalanceChange = abs(amount)   // Increases loans
        case .loanRepayment:
            fundBalanceChange = abs(amount)   // Increases fund
            loanBalanceChange = -abs(amount)  // Decreases loans
        case .interestApplied:
            fundBalanceChange = amount  // Increases fund
        case .cashOut:
            fundBalanceChange = -abs(amount)  // Decreases fund
        case .bobInvestment:
            fundBalanceChange = amount  // Increases fund
        case .bobWithdrawal:
            fundBalanceChange = -abs(amount)  // Decreases fund
        }
        
        // Set the new balances
        transaction.balance = previousFundBalance + fundBalanceChange
        transaction.loanBalance = previousLoanBalance + loanBalanceChange
        
        transaction.createdAt = Date()
        transaction.updatedAt = Date()
        
        print("📝 Transaction created: \(type.displayName) - Amount: \(amount)")
        print("   Previous Fund Balance: \(previousFundBalance) -> New: \(transaction.balance)")
        print("   Previous Loan Balance: \(previousLoanBalance) -> New: \(transaction.loanBalance)")
        
        return transaction
    }
    
    // MARK: - Transaction Balance Recalculation
    
    func recalculateAllTransactionBalances() {
        // Fetch all transactions ordered by date
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: true)]
        
        do {
            let transactions = try context.fetch(request)
            
            var currentFundBalance = fundSettings?.bobInitialInvestment ?? 100000
            var currentLoanBalance: Double = 0
            
            for transaction in transactions {
                // Store previous balance
                transaction.previousBalance = currentFundBalance
                
                // Calculate the impact on fund balance
                var fundBalanceChange: Double = 0
                var loanBalanceChange: Double = 0
                
                switch transaction.transactionType {
                case .contribution:
                    fundBalanceChange = transaction.amount
                case .loanDisbursement:
                    fundBalanceChange = -abs(transaction.amount)
                    loanBalanceChange = abs(transaction.amount)
                case .loanRepayment:
                    fundBalanceChange = abs(transaction.amount)
                    loanBalanceChange = -abs(transaction.amount)
                case .interestApplied:
                    fundBalanceChange = transaction.amount
                case .cashOut:
                    fundBalanceChange = -abs(transaction.amount)
                case .bobInvestment:
                    fundBalanceChange = transaction.amount
                case .bobWithdrawal:
                    fundBalanceChange = -abs(transaction.amount)
                }
                
                // Update balances
                currentFundBalance += fundBalanceChange
                currentLoanBalance += loanBalanceChange
                
                transaction.balance = currentFundBalance
                transaction.loanBalance = currentLoanBalance
                transaction.updatedAt = Date()
            }
            
            // Save all changes
            saveContext()
            
            // Force refresh
            objectWillChange.send()
            
            // Refresh recent transactions
            fetchRecentTransactions()
            
            print("✅ Recalculated balances for \(transactions.count) transactions")
            print("   Final Fund Balance: \(currentFundBalance)")
            print("   Final Loan Balance: \(currentLoanBalance)")
            
        } catch {
            print("Error recalculating transaction balances: \(error)")
        }
    }
    
    // MARK: - Transaction Reconciliation
    
    func reconcileAllTransactions() {
        print("🔄 Starting transaction reconciliation...")
        
        // Fetch all transactions ordered by date
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: true)]
        
        do {
            let allTransactions = try context.fetch(request)
            print("   Found \(allTransactions.count) transactions to reconcile")
            
            // Start with initial balances
            var runningFundBalance = fundSettings?.bobInitialInvestment ?? 100000
            var runningLoanBalance: Double = 0
            
            for (index, transaction) in allTransactions.enumerated() {
                // Store previous balance
                transaction.previousBalance = index > 0 ? allTransactions[index - 1].balance : fundSettings?.bobInitialInvestment ?? 100000
                
                // Calculate balance changes based on transaction type
                switch transaction.transactionType {
                case .contribution:
                    runningFundBalance += transaction.amount
                case .loanDisbursement:
                    runningFundBalance -= abs(transaction.amount)
                    runningLoanBalance += abs(transaction.amount)
                case .loanRepayment:
                    runningFundBalance += abs(transaction.amount)
                    runningLoanBalance -= abs(transaction.amount)
                case .interestApplied:
                    runningFundBalance += transaction.amount
                case .cashOut:
                    runningFundBalance -= abs(transaction.amount)
                case .bobInvestment:
                    runningFundBalance += transaction.amount
                case .bobWithdrawal:
                    runningFundBalance -= abs(transaction.amount)
                }
                
                // Update transaction with correct balances
                transaction.balance = runningFundBalance
                transaction.loanBalance = runningLoanBalance
                transaction.reconciled = true
                transaction.reconciledDate = Date()
                
                print("   [\(index + 1)/\(allTransactions.count)] \(transaction.transactionType.displayName): \(transaction.amount)")
                print("      Fund: \(transaction.previousBalance ?? 0) -> \(transaction.balance)")
                print("      Loans: \(transaction.loanBalance)")
            }
            
            saveContext()
            print("✅ Reconciliation complete!")
            print("   Final Fund Balance: \(runningFundBalance)")
            print("   Final Loan Balance: \(runningLoanBalance)")
            
            // Verify against calculated balance
            let calculatedBalance = fundSettings?.calculateFundBalance() ?? 0
            print("   Calculated Fund Balance: \(calculatedBalance)")
            
            if abs(runningFundBalance - calculatedBalance) > 0.01 {
                print("⚠️ WARNING: Reconciled balance doesn't match calculated balance!")
            }
            
        } catch {
            print("❌ Error reconciling transactions: \(error)")
        }
    }
    
    // MARK: - Fund Operations
    
    func applyAnnualInterest() {
        fundSettings?.applyAnnualInterest()
        
        let interestAmount = (fundSettings?.totalInterestApplied ?? 0) - ((fundSettings?.totalInterestApplied ?? 0) - (fundSettings?.calculateFundBalance() ?? 0) * (fundSettings?.annualInterestRate ?? 0.13))
        
        createTransaction(
            for: nil,
            amount: interestAmount,
            type: .interestApplied,
            description: "Annual interest applied at \(Int((fundSettings?.annualInterestRate ?? 0.13) * 100))%"
        )
        
        saveContext()
    }
    
    func cashOutMember(_ member: Member, amount: Double) throws {
        guard member.memberStatus != .active else {
            throw DataManagerError.cannotCashOutActiveMember
        }
        
        guard !member.hasActiveLoans else {
            throw DataManagerError.memberHasActiveLoans
        }
        
        member.cashOutAmount = amount
        member.cashOutDate = Date()
        member.memberStatus = .inactive
        member.updatedAt = Date()
        
        createTransaction(
            for: member,
            amount: -amount,
            type: .cashOut,
            description: "Member cash out"
        )
        
        saveContext()
    }
    
    // MARK: - Reports
    
    func generateMemberReport(for member: Member) -> MemberReport {
        let payments = fetchPayments(for: member)
        let transactions = fetchTransactions(for: member)
        let loans = member.loans?.allObjects as? [Loan] ?? []
        
        return MemberReport(
            member: member,
            payments: payments,
            transactions: transactions,
            loans: loans,
            totalContributions: member.totalContributions,
            activeLoanBalance: member.totalActiveLoanBalance,
            cashOutAmount: member.cashOutAmount
        )
    }
    
    private func fetchPayments(for member: Member) -> [Payment] {
        let request = Payment.paymentsForMember(member)
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching payments: \(error)")
            return []
        }
    }
    
    private func fetchTransactions(for member: Member) -> [Transaction] {
        let request = Transaction.transactionsForMember(member)
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching transactions: \(error)")
            return []
        }
    }
    
    // MARK: - Member Calculations
    
    func recalculateMemberContributions(_ member: Member) {
        // Get all contribution payments for this member
        let request = Payment.paymentsForMember(member)
        request.predicate = NSPredicate(format: "member == %@ AND type == %@", member, PaymentType.contribution.rawValue)
        
        do {
            let payments = try context.fetch(request)
            
            // Calculate total contributions
            let totalContributions = payments.reduce(0) { $0 + $1.contributionAmount }
            
            print("📊 Recalculating contributions for \(member.name ?? "Unknown")")
            print("   Found \(payments.count) contribution payments")
            print("   Previous total: \(member.totalContributions)")
            print("   New total: \(totalContributions)")
            
            // Update member's total contributions
            member.totalContributions = totalContributions
            member.updatedAt = Date()
            
            // Save context
            saveContext()
            
            // Force refresh
            objectWillChange.send()
            
            // Post notification
            NotificationCenter.default.post(name: .memberDataUpdated, object: member)
            
        } catch {
            print("Error recalculating member contributions: \(error)")
        }
    }
    
    // MARK: - Core Data
    
    private func saveContext() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
}

// MARK: - Error Types

enum DataManagerError: LocalizedError {
    case memberHasActiveLoans
    case memberNotEligibleForLoan
    case loanAmountExceedsLimit
    case cannotCashOutActiveMember
    case insufficientFunds
    
    var errorDescription: String? {
        switch self {
        case .memberHasActiveLoans:
            return "Cannot perform this action. Member has active loans."
        case .memberNotEligibleForLoan:
            return "Member is not eligible for a loan."
        case .loanAmountExceedsLimit:
            return "Loan amount exceeds the member's limit."
        case .cannotCashOutActiveMember:
            return "Cannot cash out an active member."
        case .insufficientFunds:
            return "Insufficient funds in the solidarity fund."
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let memberDataUpdated = Notification.Name("memberDataUpdated")
    static let transactionsUpdated = Notification.Name("transactionsUpdated")
}

// MARK: - Report Models

struct MemberReport {
    let member: Member
    let payments: [Payment]
    let transactions: [Transaction]
    let loans: [Loan]
    let totalContributions: Double
    let activeLoanBalance: Double
    let cashOutAmount: Double
}