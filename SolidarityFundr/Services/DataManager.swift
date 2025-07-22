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
    func createMember(name: String, role: MemberRole, email: String? = nil, phoneNumber: String? = nil, joinDate: Date = Date()) -> Member {
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
        
        return payment
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
        
        do {
            recentTransactions = try context.fetch(request)
        } catch {
            print("Error fetching transactions: \(error)")
        }
    }
    
    @discardableResult
    private func createTransaction(for member: Member?, amount: Double, type: TransactionType, description: String? = nil) -> Transaction {
        let transaction = Transaction(context: context)
        transaction.transactionID = UUID()
        transaction.member = member
        transaction.amount = amount
        transaction.transactionType = type
        transaction.transactionDate = Date()
        transaction.transactionDescription = description
        
        // Calculate the new fund balance after this transaction
        let currentBalance = fundSettings?.calculateFundBalance() ?? 0
        transaction.balance = currentBalance
        
        transaction.createdAt = Date()
        transaction.updatedAt = Date()
        
        return transaction
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