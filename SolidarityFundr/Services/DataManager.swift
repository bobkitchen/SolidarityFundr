//
//  DataManager.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import CoreData
import Combine
import os.log

class DataManager: ObservableObject {
    static let shared = DataManager()
    
    private let persistenceController: PersistenceController
    private let context: NSManagedObjectContext
    
    @Published var fundSettings: FundSettings?
    @Published var members: [Member] = []
    @Published var activeLoans: [Loan] = []
    @Published var allLoans: [Loan] = []
    @Published var recentTransactions: [Transaction] = []
    /// Most recent Core Data save error. UI can observe this to surface failures
    /// instead of letting them fail silently into stderr.
    @Published var lastSaveError: Error?
    
    private var cancellables = Set<AnyCancellable>()
    private var isSaving = false
    
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
                guard let self = self, !self.isSaving else { return }
                self.fetchInitialData()
            }
            .store(in: &cancellables)

        // CloudKit imports arrive as `.NSPersistentStoreRemoteChange`
        // notifications. The viewContext silently merges them in (we set
        // `automaticallyMergesChangesFromParent = true` on Persistence),
        // but no `contextDidSave` fires for a remote merge — so our
        // @Published arrays go stale. This was invisible on macOS because
        // the local store was already populated from prior runs; iPhone's
        // first-launch scenario surfaced it (Outstanding Loans card empty
        // until the user re-triggered Recalculate or restarted).
        //
        // Debounced because remote-change can arrive in bursts during a
        // heavy sync; we want one refetch at the end, not 20 mid-flight.
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.fetchMembers()
                self.fetchActiveLoans()
                self.fetchAllLoans()
                self.fetchRecentTransactions()
            }
            .store(in: &cancellables)
    }
    
    private func fetchInitialData() {
        fetchMembers()
        fetchActiveLoans()
        fetchAllLoans()
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
    func createMember(name: String, role: MemberRole, joinDate: Date = Date()) -> Member {
        let member = Member(context: context)
        member.memberID = UUID()
        member.name = name
        member.memberRole = role
        member.joinDate = joinDate
        member.createdAt = Date()
        member.updatedAt = Date()
        member.memberStatus = .active
        member.totalContributions = 0

        saveContext()
        fetchMembers()

        AuditLogger.shared.log(
            event: .memberCreated,
            details: "\(name) — \(role.displayName)",
            memberID: member.memberID
        )

        return member
    }

    func updateMember(_ member: Member) {
        member.updatedAt = Date()
        saveContext()
        fetchMembers()

        AuditLogger.shared.log(
            event: .memberModified,
            details: member.name ?? "Unknown",
            memberID: member.memberID
        )
    }

    func suspendMember(_ member: Member) {
        member.memberStatus = .suspended
        member.suspendedDate = Date()
        member.updatedAt = Date()
        saveContext()
        fetchMembers()

        AuditLogger.shared.log(
            event: .memberSuspended,
            details: member.name ?? "Unknown",
            memberID: member.memberID
        )
    }

    func reactivateMember(_ member: Member) {
        member.memberStatus = .active
        member.suspendedDate = nil
        member.updatedAt = Date()
        saveContext()
        fetchMembers()

        AuditLogger.shared.log(
            event: .memberReactivated,
            details: member.name ?? "Unknown",
            memberID: member.memberID
        )
    }

    func deleteMember(_ member: Member) throws {
        guard !member.hasActiveLoans else {
            throw DataManagerError.memberHasActiveLoans
        }

        // Snapshot identifiers before delete so the audit entry survives.
        let memberID = member.memberID
        let name = member.name ?? "Unknown"

        // CloudKit doesn't support Cascade delete rules — relationships are
        // Nullify. Walk the member's owned graph and delete dependents
        // explicitly so they don't become orphans on iCloud.
        deleteRelatedRecords(for: member)

        context.delete(member)
        saveContext()
        fetchMembers()

        AuditLogger.shared.log(
            event: .memberDeleted,
            details: name,
            memberID: memberID
        )
    }

    /// Walks every record that previously cascaded from a Member and deletes
    /// it explicitly. Safe to call before `context.delete(member)` —
    /// Nullify-rule relationships will otherwise leave these records as
    /// orphans (no member, but still in CloudKit).
    private func deleteRelatedRecords(for member: Member) {
        if let loans = member.loans as? Set<Loan> {
            for loan in loans {
                if let payments = loan.payments as? Set<Payment> {
                    for payment in payments {
                        if let txn = payment.transaction {
                            context.delete(txn)
                        }
                        context.delete(payment)
                    }
                }
                context.delete(loan)
            }
        }
        if let payments = member.payments as? Set<Payment> {
            for payment in payments {
                if let txn = payment.transaction {
                    context.delete(txn)
                }
                context.delete(payment)
            }
        }
        if let transactions = member.transactions as? Set<Transaction> {
            for transaction in transactions {
                context.delete(transaction)
            }
        }
        if let notifications = member.notificationHistory as? Set<NotificationHistory> {
            for note in notifications {
                context.delete(note)
            }
        }
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

    func fetchAllLoans() {
        let request = Loan.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Loan.issueDate, ascending: false)]
        do {
            allLoans = try context.fetch(request)
        } catch {
            print("Error fetching all loans: \(error)")
        }
    }
    
    func createLoan(for member: Member, amount: Double, repaymentMonths: Int, issueDate: Date = Date(), notes: String? = nil, wasOverridden: Bool = false, overrideReason: String? = nil, overriddenRules: [String] = []) throws -> Loan {
        // Skip eligibility checks if admin override is active
        if !wasOverridden {
            guard member.isEligibleForLoan else {
                throw DataManagerError.memberNotEligibleForLoan
            }

            guard amount <= member.maximumLoanAmount else {
                throw DataManagerError.loanAmountExceedsLimit
            }
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

        // Set override fields
        loan.wasOverridden = wasOverridden
        loan.overrideReason = overrideReason

        _ = createTransaction(
            for: member,
            amount: -amount,
            type: .loanDisbursement,
            description: "Loan disbursement of KSH \(Int(amount))\(wasOverridden ? " [OVERRIDE]" : "")",
            date: issueDate
        )

        saveContext()
        fetchActiveLoans()

        // Audit log - include override information
        var auditDetails = "Loan of \(CurrencyFormatter.shared.format(amount)) for \(repaymentMonths) months"
        if wasOverridden {
            auditDetails += " [ADMIN OVERRIDE: \(overrideReason ?? "No reason provided")]"
            if !overriddenRules.isEmpty {
                auditDetails += " Rules overridden: \(overriddenRules.joined(separator: ", "))"
            }
        }
        AuditLogger.shared.log(
            event: .loanCreated,
            details: auditDetails,
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
        
        // Check if loan should be completed (use epsilon for floating-point comparison)
        if loan.balance < 0.01 && loan.loanStatus == .active {
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

            // Use epsilon for floating-point comparison
            if loan.balance < 0.01 {
                completeLoan(loan)
            }
            
            let transaction = createTransaction(
                for: member,
                amount: -amount,  // Negative for loan repayments
                type: .loanRepayment,
                description: "Loan payment: KSH \(Int(amount))",
                date: paymentDate
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
                description: "Monthly contribution",
                date: paymentDate
            )
            payment.transaction = transaction
        }
        
        member.updatedAt = Date()
        saveContext()

        // Refresh recent transactions
        fetchRecentTransactions()

        let kind = loan != nil ? "Loan repayment" : "Contribution"
        AuditLogger.shared.log(
            event: .paymentCreated,
            details: "\(kind) — \(member.name ?? "Unknown")",
            amount: amount,
            memberID: member.memberID,
            loanID: loan?.loanID
        )

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
            // Debug logging commented out
            // print("🔍 Found \(paymentsWithoutTransactions.count) payments without transactions")
            
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
        // Sort by createdAt (insertion order) so recently entered transactions appear first
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.createdAt, ascending: false)]
        
        do {
            recentTransactions = try context.fetch(request)
            // Debug logging commented out
            // print("📋 Fetched \(recentTransactions.count) recent transactions")
            // if let first = recentTransactions.first {
            //     print("   Most recent: \(first.transactionType.displayName) - \(first.amount) on \(first.transactionDate ?? Date())")
            // }
            
            // Post notification that transactions have been updated
            NotificationCenter.default.post(name: .transactionsUpdated, object: nil)
        } catch {
            print("Error fetching transactions: \(error)")
        }
    }
    
    @discardableResult
    private func createTransaction(for member: Member?, amount: Double, type: TransactionType, description: String? = nil, date: Date = Date()) -> Transaction {
        // Get the previous balance from the most recently created transaction
        // Sort by createdAt (insertion order) instead of transactionDate to handle backdated entries correctly
        let previousBalanceRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        previousBalanceRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.createdAt, ascending: false)]
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
        transaction.transactionDate = date
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
        // Fetch all transactions ordered by creation time (insertion order)
        // Sort by createdAt instead of transactionDate to handle backdated entries correctly
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.createdAt, ascending: true)]
        
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
            
            // Debug logging commented out
            // print("✅ Recalculated balances for \(transactions.count) transactions")
            // print("   Final Fund Balance: \(currentFundBalance)")
            // print("   Final Loan Balance: \(currentLoanBalance)")
            
        } catch {
            print("Error recalculating transaction balances: \(error)")
        }
    }
    
    // MARK: - Transaction Reconciliation
    
    func reconcileAllTransactions() {
        // Debug logging commented out to reduce console noise
        // print("🔄 Starting transaction reconciliation...")

        // Fetch all transactions ordered by creation time (insertion order)
        // Sort by createdAt instead of transactionDate to handle backdated entries correctly
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.createdAt, ascending: true)]
        
        do {
            let allTransactions = try context.fetch(request)
            // print("   Found \(allTransactions.count) transactions to reconcile")
            
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
                
                // Verbose transaction logging commented out
                // print("   [\(index + 1)/\(allTransactions.count)] \(transaction.transactionType.displayName): \(transaction.amount)")
                // print("      Fund: \(transaction.previousBalance ?? 0) -> \(transaction.balance)")
                // print("      Loans: \(transaction.loanBalance)")
            }
            
            saveContext()
            // Summary logging commented out
            // print("✅ Reconciliation complete!")
            // print("   Final Fund Balance: \(runningFundBalance)")
            // print("   Final Loan Balance: \(runningLoanBalance)")
            
            // Verify against calculated balance
            let calculatedBalance = fundSettings?.calculateFundBalance() ?? 0
            // print("   Calculated Fund Balance: \(calculatedBalance)")
            
            if abs(runningFundBalance - calculatedBalance) > 0.01 {
                print("⚠️ WARNING: Reconciled balance doesn't match calculated balance!")
            }
            
        } catch {
            print("❌ Error reconciling transactions: \(error)")
        }
    }
    
    // MARK: - Fund Operations
    
    func applyAnnualInterest() {
        guard let settings = fundSettings else { return }

        // Compute interest from the PRE-mutation balance so the recorded
        // transaction amount equals the actual accrual. The previous
        // double-subtraction formula happened to cancel arithmetically but
        // read post-mutation state.
        let preInterestBalance = settings.calculateFundBalance()
        let rate = settings.annualInterestRate
        let interestAmount = preInterestBalance * rate

        settings.applyAnnualInterest()

        createTransaction(
            for: nil,
            amount: interestAmount,
            type: .interestApplied,
            description: "Annual interest applied at \(Int(rate * 100))%"
        )

        saveContext()

        AuditLogger.shared.log(
            event: .interestApplied,
            details: String(format: "Applied at %.0f%% on KSH %.0f balance",
                            rate * 100, preInterestBalance),
            amount: interestAmount
        )
    }

    /// Records a member's formal departure from the fund.
    ///
    /// Settles the member's account by paying out their contributions plus
    /// interest, transitions them to the terminal `.cashedOut` status, and
    /// preserves their historical records. Eligible from any non-cashedOut
    /// state (the previous "must be suspended first" requirement was
    /// busywork).
    ///
    /// - Parameters:
    ///   - member: The departing member.
    ///   - amount: The settlement amount (typically `member.calculateCashOutAmount()`).
    ///   - reason: Free-text reason captured for the audit log.
    ///   - paymentMethod: How the payout was delivered (cash / M-Pesa / bank).
    ///   - date: The effective cash-out date. Defaults to now.
    func cashOutMember(_ member: Member,
                       amount: Double,
                       reason: String,
                       paymentMethod: PaymentMethod,
                       date: Date = Date()) throws {
        guard member.memberStatus != .cashedOut else {
            throw DataManagerError.cannotCashOutActiveMember
        }

        guard !member.hasActiveLoans else {
            throw DataManagerError.memberHasActiveLoans
        }

        member.cashOutAmount = amount
        member.cashOutDate = date
        member.memberStatus = .cashedOut
        member.updatedAt = Date()

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptionParts = ["Cash out via \(paymentMethod.displayName)",
                                trimmedReason.isEmpty ? nil : "— \(trimmedReason)"]
            .compactMap { $0 }
        createTransaction(
            for: member,
            amount: -amount,
            type: .cashOut,
            description: descriptionParts.joined(separator: " "),
            date: date
        )

        saveContext()
        fetchMembers()

        AuditLogger.shared.log(
            event: .memberCashedOut,
            details: "\(member.name ?? "Unknown") — \(paymentMethod.displayName)\(trimmedReason.isEmpty ? "" : " (\(trimmedReason))")",
            amount: amount,
            memberID: member.memberID
        )
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
            let totalContributions = payments.reduce(0) {
                let contribution = $1.contributionAmount > 0 ? $1.contributionAmount : $1.amount
                return $0 + contribution
            }
            
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
        guard context.hasChanges else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try context.save()
            // Clear any prior error on successful save.
            if lastSaveError != nil {
                DispatchQueue.main.async { [weak self] in self?.lastSaveError = nil }
            }
        } catch {
            // Surface to UI so the user sees a financial-data save failure rather
            // than continuing with diverged in-memory state. Logged at fault level.
            os_log(.fault, log: .dataManager, "Core Data save failed: %{public}@", error.localizedDescription)
            DispatchQueue.main.async { [weak self] in
                self?.lastSaveError = error
            }
            assertionFailure("Core Data save failed: \(error)")
        }
    }
}

extension OSLog {
    static let dataManager = OSLog(subsystem: "com.solidarityfundr.app", category: "DataManager")
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