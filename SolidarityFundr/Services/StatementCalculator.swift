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

    // MARK: Recognition math

    /// Number of *distinct calendar months* between the member's join
    /// month and `asOf`, inclusive. Floor of 1 so a brand-new member
    /// doesn't divide by zero in `consistencyRate(for:)`.
    func monthsExpected(for member: Member) -> Int {
        guard let join = member.joinDate else { return 0 }
        let cal = Calendar.current
        let joinMonth = cal.dateInterval(of: .month, for: join)?.start ?? join
        let asOfMonth = cal.dateInterval(of: .month, for: asOf)?.start ?? asOf
        guard joinMonth <= asOfMonth else { return 0 }
        let comps = cal.dateComponents([.month], from: joinMonth, to: asOfMonth)
        return max(1, (comps.month ?? 0) + 1)
    }

    /// Distinct calendar months in which the member made any
    /// contribution payment, between their join month and `asOf`.
    func monthsContributed(for member: Member) -> Int {
        let cal = Calendar.current
        let payments = (member.payments?.allObjects as? [Payment]) ?? []
        var months = Set<DateComponents>()
        for p in payments {
            guard p.contributionAmount > 0,
                  let date = p.paymentDate,
                  date <= asOf else { continue }
            months.insert(cal.dateComponents([.year, .month], from: date))
        }
        return months.count
    }

    /// Fraction of expected months in which the member contributed.
    /// Capped at 1.0 (a double-payment in one month doesn't credit you
    /// for a month you didn't pay).
    func consistencyRate(for member: Member) -> Double {
        let expected = monthsExpected(for: member)
        guard expected > 0 else { return 0 }
        let actual = monthsContributed(for: member)
        return min(1.0, Double(actual) / Double(expected))
    }

    /// Consecutive months of contribution counted backwards from the
    /// statement month. Stops at the first month with no contribution.
    /// `asOf` is treated as the most recent month — if the statement
    /// month itself has no contribution yet, the streak is whatever
    /// it was through the previous month.
    func currentStreak(for member: Member) -> Int {
        let cal = Calendar.current
        let payments = (member.payments?.allObjects as? [Payment]) ?? []

        // Index distinct (year, month) pairs the member has contributed in.
        var paidMonths = Set<String>()
        for p in payments {
            guard p.contributionAmount > 0,
                  let date = p.paymentDate, date <= asOf else { continue }
            let comps = cal.dateComponents([.year, .month], from: date)
            paidMonths.insert("\(comps.year ?? 0)-\(comps.month ?? 0)")
        }

        // Walk backwards from the statement month until we hit a miss.
        var streak = 0
        var cursor = asOf
        while true {
            let comps = cal.dateComponents([.year, .month], from: cursor)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if paidMonths.contains(key) {
                streak += 1
                guard let prev = cal.date(byAdding: .month, value: -1, to: cursor) else { break }
                cursor = prev
            } else {
                break
            }
        }

        // Don't count months from before the member joined.
        if let join = member.joinDate {
            let joinComps = cal.dateComponents([.year, .month], from: join)
            let asOfComps = cal.dateComponents([.year, .month], from: asOf)
            let totalMonthsSinceJoin = ((asOfComps.year ?? 0) - (joinComps.year ?? 0)) * 12
                + ((asOfComps.month ?? 0) - (joinComps.month ?? 0)) + 1
            streak = min(streak, max(0, totalMonthsSinceJoin))
        }
        return streak
    }

    /// True if the member made any contribution in the statement month.
    func contributedThisMonth(_ member: Member, monthStart: Date, monthEnd: Date) -> Bool {
        let payments = (member.payments?.allObjects as? [Payment]) ?? []
        return payments.contains { p in
            guard p.contributionAmount > 0,
                  let date = p.paymentDate else { return false }
            return date >= monthStart && date <= monthEnd
        }
    }
}
