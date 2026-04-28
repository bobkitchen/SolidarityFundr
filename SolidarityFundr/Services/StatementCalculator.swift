//
//  StatementCalculator.swift
//  SolidarityFundr
//
//  As-of-month math for the Monthly Statement and Member Statement
//  reports. Lives separately from FundCalculator (which always reports
//  "now" values) because the statements need point-in-time figures: a
//  member's contributions as of the end of March, their loan balance
//  as of the end of March, the fund balance as of the end of March.
//

import Foundation
import CoreData

// MARK: - Month identity

/// A single calendar month, used as the period for both reports.
struct StatementMonth: Hashable, Identifiable {
    let year: Int
    let month: Int  // 1-12

    var id: String { "\(year)-\(String(format: "%02d", month))" }

    /// Midnight on the 1st.
    var startDate: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    /// Last instant of the month (one second before next month's start).
    var endDate: Date {
        let cal = Calendar.current
        let nextMonth = cal.date(byAdding: .month, value: 1, to: startDate)!
        return cal.date(byAdding: .second, value: -1, to: nextMonth)!
    }

    /// The end-of-the-prior-month date — used as the "opening balance"
    /// reference point for member statements.
    var priorMonthEndDate: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .second, value: -1, to: startDate)!
    }

    var displayName: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: startDate)
    }

    /// Underscore-friendly label for filenames ("April-2026").
    var fileNameLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM-yyyy"
        return f.string(from: startDate)
    }

    static var current: StatementMonth {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        return StatementMonth(year: comps.year!, month: comps.month!)
    }

    /// Most-recent-first list of months for the picker.
    static func recent(count: Int = 24) -> [StatementMonth] {
        let cal = Calendar.current
        return (0..<count).compactMap { offset in
            guard let date = cal.date(byAdding: .month, value: -offset, to: Date()) else { return nil }
            let comps = cal.dateComponents([.year, .month], from: date)
            return StatementMonth(year: comps.year!, month: comps.month!)
        }
    }
}

// MARK: - Calculator

/// Point-in-time financial math against the live Core Data store.
/// Always run on the main thread (uses viewContext).
struct StatementCalculator {
    let context: NSManagedObjectContext
    let asOf: Date

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
         asOf: Date) {
        self.context = context
        self.asOf = asOf
    }

    // MARK: Per-member values

    /// Total contributions made by `member` on or before `asOf`.
    func contributions(for member: Member) -> Double {
        let payments = (member.payments?.allObjects as? [Payment]) ?? []
        return payments.reduce(0) { sum, p in
            guard let date = p.paymentDate, date <= asOf else { return sum }
            return sum + p.contributionAmount
        }
    }

    /// Outstanding loan balance for `member` as of `asOf`, summed across
    /// all of their loans. Loans not yet issued or already completed by
    /// `asOf` contribute zero.
    func outstandingLoanBalance(for member: Member) -> Double {
        let loans = (member.loans?.allObjects as? [Loan]) ?? []
        return loans.reduce(0) { $0 + balance(for: $1) }
    }

    /// Sum of `monthlyPayment` across `member`'s loans that are still
    /// active as of `asOf` (issued by then, not yet completed). Used as
    /// the "next month's loan portion due" column in the monthly table.
    func monthlyLoanPaymentDue(for member: Member) -> Double {
        let loans = (member.loans?.allObjects as? [Loan]) ?? []
        return loans.reduce(0) { sum, loan in
            guard let issued = loan.issueDate, issued <= asOf else { return sum }
            if let completed = loan.completedDate, completed <= asOf { return sum }
            // Cap the loan portion at the outstanding balance — a member
            // never owes more than what's left.
            let remaining = balance(for: loan)
            return sum + min(loan.monthlyPayment, remaining)
        }
    }

    /// Outstanding balance for a single loan as of `asOf`.
    func balance(for loan: Loan) -> Double {
        guard let issued = loan.issueDate, issued <= asOf else { return 0 }
        if let completed = loan.completedDate, completed <= asOf { return 0 }

        let payments = (loan.payments as? Set<Payment>) ?? []
        let repaid = payments.reduce(0.0) { sum, p in
            guard let date = p.paymentDate, date <= asOf else { return sum }
            return sum + p.loanRepaymentAmount
        }
        return max(0, loan.amount - repaid)
    }

    /// Was this member active (joined, not suspended, not cashed out) at
    /// `asOf`? Used to filter the monthly statement table.
    func wasActive(_ member: Member) -> Bool {
        if let joined = member.joinDate, joined > asOf { return false }
        if let cashOut = member.cashOutDate, cashOut <= asOf { return false }
        if let suspended = member.suspendedDate, suspended <= asOf { return false }
        return true
    }

    // MARK: Fund-wide aggregates

    /// Latest transaction balance with `transactionDate <= asOf`. Falls
    /// back to Bob's initial investment if no transactions exist yet.
    func fundBalance() -> Double {
        let request: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "transactionDate <= %@", asOf as NSDate)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Transaction.transactionDate, ascending: false),
            NSSortDescriptor(keyPath: \Transaction.createdAt, ascending: false)
        ]
        request.fetchLimit = 1
        if let last = try? context.fetch(request).first {
            return last.balance
        }
        let settings = FundSettings.fetchOrCreate(in: context)
        return settings.bobInitialInvestment
    }

    func totalContributions() -> Double {
        let members = (try? context.fetch(Member.fetchRequest())) ?? []
        return members.reduce(0) { $0 + contributions(for: $1) }
    }

    func totalOutstandingLoans() -> Double {
        let loans = (try? context.fetch(Loan.fetchRequest())) ?? []
        return loans.reduce(0) { $0 + balance(for: $1) }
    }

    func activeMembersCount() -> Int {
        let members = (try? context.fetch(Member.fetchRequest())) ?? []
        return members.filter(wasActive).count
    }

    // MARK: Recognition math (this-month deltas)

    /// True if the member made any contribution in the statement month.
    /// Used by the reference list's ✓/— indicator.
    func contributedThisMonth(_ member: Member, monthStart: Date, monthEnd: Date) -> Bool {
        let payments = (member.payments?.allObjects as? [Payment]) ?? []
        return payments.contains { p in
            guard p.contributionAmount > 0,
                  let date = p.paymentDate else { return false }
            return date >= monthStart && date <= monthEnd
        }
    }

    /// Aggregate "what happened in the fund this month" — the four
    /// numbers that drive the spotlight strip.
    ///
    /// We do NOT use historical month-by-month payment dates for
    /// recognition (the data has gaps where dates were entered
    /// approximately or in batch), but the *current* statement month
    /// is reliable: payments entered in the live app this month carry
    /// the actual paymentDate. This aggregate sums only that window.
    func thisMonthActivity(monthStart: Date, monthEnd: Date) -> ThisMonthActivity {
        let allPayments = (try? context.fetch(Payment.fetchRequest())) ?? []

        var contributed: Double = 0
        var repaid: Double = 0
        var contributingMembers = Set<UUID>()

        for p in allPayments {
            guard let date = p.paymentDate, date >= monthStart, date <= monthEnd else { continue }
            if p.contributionAmount > 0 {
                contributed += p.contributionAmount
                if let id = p.member?.memberID {
                    contributingMembers.insert(id)
                }
            }
            if p.loanRepaymentAmount > 0 {
                repaid += p.loanRepaymentAmount
            }
        }

        let allLoans = (try? context.fetch(Loan.fetchRequest())) ?? []
        let newLoans = allLoans.filter { loan in
            guard let issued = loan.issueDate else { return false }
            return issued >= monthStart && issued <= monthEnd
        }

        return ThisMonthActivity(
            contributed: contributed,
            repaid: repaid,
            contributingMembersCount: contributingMembers.count,
            newLoansCount: newLoans.count
        )
    }
}

/// "What happened this month" — drives the collective stat strip
/// under the spotlight cards. All four values come from explicit
/// entries dated within the statement month, so the numbers are
/// reliable even though older historical dates may not be.
struct ThisMonthActivity {
    let contributed: Double
    let repaid: Double
    let contributingMembersCount: Int
    let newLoansCount: Int
}
