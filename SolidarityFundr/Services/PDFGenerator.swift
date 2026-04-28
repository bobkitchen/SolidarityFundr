//
//  PDFGenerator.swift
//  SolidarityFundr
//
//  PDF generation for the two reports the fund actually ships:
//
//    1. Monthly Statement — period-bounded, fund-wide compiled
//       statement: header + as-of metrics + active loans + member
//       summary table.
//
//    2. Member Statement — period-bounded, single-member statement:
//       header + opening/closing balances + chronological activity.
//
//  PDF drawing depends on AppKit (NSGraphicsContext, NSFont, NSImage,
//  NSBezierPath) so this whole file is macOS-only. iPhone shows a
//  placeholder in ReportsView rather than carrying a UIKit drawing
//  stack.
//

#if os(macOS)

import Foundation
import PDFKit
import AppKit
import CoreData

// MARK: - Snapshots (main-thread captures, drawn from background safely)

struct MonthlyStatementSnapshot {
    let month: StatementMonth
    let fundBalance: Double
    let totalContributions: Double
    let totalOutstandingLoans: Double
    let activeMembersCount: Int
    let activeLoansCount: Int
    let memberRows: [MemberRow]
    let activeLoans: [LoanRow]

    struct MemberRow {
        let name: String
        let role: String
        let contributions: Double
        let joinDate: Date?  // tiebreak for ranking
    }

    struct LoanRow {
        let memberName: String
        let originalAmount: Double
        let balance: Double
        let monthlyPayment: Double
        let issueDate: Date?
        let dueDate: Date?
        let nextPaymentDue: Date?
        let isOverdue: Bool

        var amountRepaid: Double { max(0, originalAmount - balance) }
        var percentRepaid: Double {
            guard originalAmount > 0 else { return 0 }
            return min(1.0, amountRepaid / originalAmount)
        }
        var marker: LoanProgressMarker {
            LoanProgressMarker.evaluate(percentRepaid: percentRepaid, isOverdue: isOverdue)
        }
    }
}

/// Progress emoji applied to a loan card. The order is exclusive:
/// overdue dominates everything; otherwise the highest-progress
/// threshold wins. Below 50% no marker is shown — silence beats
/// fake cheer.
enum LoanProgressMarker {
    case overdue       // ⚠️
    case finalStretch  // ✅ (≥ 90%)
    case onFire        // 🔥 (≥ 75%)
    case halfway       // 🎯 (≥ 50%)
    case none

    var emoji: String {
        switch self {
        case .overdue:      return "⚠️"
        case .finalStretch: return "✅"
        case .onFire:       return "🔥"
        case .halfway:      return "🎯"
        case .none:         return ""
        }
    }

    static func evaluate(percentRepaid: Double, isOverdue: Bool) -> LoanProgressMarker {
        if isOverdue { return .overdue }
        if percentRepaid >= 0.90 { return .finalStretch }
        if percentRepaid >= 0.75 { return .onFire }
        if percentRepaid >= 0.50 { return .halfway }
        return .none
    }
}

struct MemberStatementSnapshot {
    let month: StatementMonth
    let memberName: String
    let memberRole: String
    let joinDate: Date?

    let openingContributions: Double
    let closingContributions: Double
    let openingLoanBalance: Double
    let closingLoanBalance: Double

    let entries: [Entry]
    let activeLoans: [ActiveLoan]

    struct Entry {
        let date: Date
        let kind: String     // "Contribution" / "Loan Repayment" / "Loan Disbursed"
        let detail: String
        let signedAmount: Double  // + into fund, - out of fund (from member's perspective)
    }

    struct ActiveLoan {
        let originalAmount: Double
        let balance: Double
        let monthlyPayment: Double
        let nextDueDate: Date?
    }
}

// MARK: - PDF errors

enum PDFError: LocalizedError {
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed: return "Failed to create PDF graphics context"
        }
    }
}

// MARK: - Generator

final class PDFGenerator {

    // MARK: Public entry points

    /// Build the fund-wide compiled statement for `month`.
    func generateMonthlyStatement(month: StatementMonth,
                                  dataManager: DataManager) async throws -> URL {
        try await MainActor.run {
            let snapshot = self.snapshotMonthly(month: month, dataManager: dataManager)
            return try self.renderMonthly(snapshot)
        }
    }

    /// Build the per-member statement for `member` and `month`.
    func generateMemberStatement(member: Member,
                                 month: StatementMonth,
                                 dataManager: DataManager) async throws -> URL {
        try await MainActor.run {
            let snapshot = self.snapshotMember(member: member, month: month)
            return try self.renderMember(snapshot)
        }
    }

    // MARK: Snapshot building (Core Data → plain structs)

    @MainActor
    private func snapshotMonthly(month: StatementMonth,
                                 dataManager: DataManager) -> MonthlyStatementSnapshot {
        let calc = StatementCalculator(asOf: month.endDate)

        let activeMembers = dataManager.members.filter { calc.wasActive($0) }

        // Member rows: keep all active members; ranking is applied at
        // render time so the snapshot stays a pure data capture.
        let memberRows = activeMembers.map { member in
            MonthlyStatementSnapshot.MemberRow(
                name: member.name ?? "Unknown",
                role: member.memberRole.displayName,
                contributions: calc.contributions(for: member),
                joinDate: member.joinDate
            )
        }

        // Active-as-of-end-of-month loans (issued by then, not yet completed).
        // Overdue is computed against the statement's asOf date — not "now"
        // — so a statement issued for March doesn't retroactively flag a
        // loan that only fell behind in April.
        let allLoans = (try? PersistenceController.shared.container.viewContext.fetch(Loan.fetchRequest())) ?? []
        let activeLoans = allLoans
            .filter { loan in
                guard let issued = loan.issueDate, issued <= month.endDate else { return false }
                if let completed = loan.completedDate, completed <= month.endDate { return false }
                return calc.balance(for: loan) > 0.01
            }
            .map { loan in
                let asOfOverdue: Bool = {
                    guard let due = loan.dueDate else { return false }
                    return due < month.endDate
                }()
                return MonthlyStatementSnapshot.LoanRow(
                    memberName: loan.member?.name ?? "Unknown",
                    originalAmount: loan.amount,
                    balance: calc.balance(for: loan),
                    monthlyPayment: loan.monthlyPayment,
                    issueDate: loan.issueDate,
                    dueDate: loan.dueDate,
                    nextPaymentDue: loan.nextPaymentDue,
                    isOverdue: asOfOverdue
                )
            }
            .sorted { $0.memberName < $1.memberName }

        return MonthlyStatementSnapshot(
            month: month,
            fundBalance: calc.fundBalance(),
            totalContributions: calc.totalContributions(),
            totalOutstandingLoans: calc.totalOutstandingLoans(),
            activeMembersCount: activeMembers.count,
            activeLoansCount: activeLoans.count,
            memberRows: memberRows,
            activeLoans: activeLoans
        )
    }

    @MainActor
    private func snapshotMember(member: Member, month: StatementMonth) -> MemberStatementSnapshot {
        let opening = StatementCalculator(asOf: month.priorMonthEndDate)
        let closing = StatementCalculator(asOf: month.endDate)

        var entries: [MemberStatementSnapshot.Entry] = []

        let payments = (member.payments?.allObjects as? [Payment]) ?? []
        for payment in payments {
            guard let date = payment.paymentDate,
                  date >= month.startDate, date <= month.endDate else { continue }
            if payment.contributionAmount > 0 {
                entries.append(.init(
                    date: date,
                    kind: "Contribution",
                    detail: "Monthly contribution",
                    signedAmount: payment.contributionAmount
                ))
            }
            if payment.loanRepaymentAmount > 0 {
                entries.append(.init(
                    date: date,
                    kind: "Loan Repayment",
                    detail: "Loan payment",
                    signedAmount: -payment.loanRepaymentAmount
                ))
            }
        }

        let loans = (member.loans?.allObjects as? [Loan]) ?? []
        for loan in loans {
            guard let issued = loan.issueDate,
                  issued >= month.startDate, issued <= month.endDate else { continue }
            entries.append(.init(
                date: issued,
                kind: "Loan Disbursed",
                detail: "Loan amount: \(CurrencyFormatter.shared.format(loan.amount))",
                signedAmount: -loan.amount
            ))
        }

        let activeLoans = loans
            .filter { loan in
                guard let issued = loan.issueDate, issued <= month.endDate else { return false }
                if let completed = loan.completedDate, completed <= month.endDate { return false }
                return closing.balance(for: loan) > 0.01
            }
            .map { loan in
                MemberStatementSnapshot.ActiveLoan(
                    originalAmount: loan.amount,
                    balance: closing.balance(for: loan),
                    monthlyPayment: loan.monthlyPayment,
                    nextDueDate: loan.nextPaymentDue
                )
            }

        return MemberStatementSnapshot(
            month: month,
            memberName: member.name ?? "Unknown",
            memberRole: member.memberRole.displayName,
            joinDate: member.joinDate,
            openingContributions: opening.contributions(for: member),
            closingContributions: closing.contributions(for: member),
            openingLoanBalance: opening.outstandingLoanBalance(for: member),
            closingLoanBalance: closing.outstandingLoanBalance(for: member),
            entries: entries.sorted { $0.date < $1.date },
            activeLoans: activeLoans
        )
    }

    // MARK: Rendering — Monthly Statement

    private func renderMonthly(_ s: MonthlyStatementSnapshot) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let auxiliary: [String: Any] = [
            kCGPDFContextTitle as String: "Solidarity Fund — Statement for \(s.month.displayName)",
            kCGPDFContextAuthor as String: "Bob Kitchen",
            kCGPDFContextCreator as String: "Parachichi House Solidarity Fund",
            kCGPDFContextSubject as String: "Monthly statement of contributions and loans, \(s.month.displayName)",
            kCGPDFContextKeywords as String: "Solidarity Fund, Parachichi House, Monthly Statement"
        ]

        return try renderPDF(pageRect: pageRect, auxiliary: auxiliary, fileNameStem: "ParachichiHouse_Statement_\(s.month.fileNameLabel)") { rect in
            var y = rect.height - 50
            y = drawHeader(in: rect, at: y, subtitle: "Statement for \(s.month.displayName)")
            y -= 18
            y = drawHeroBand(in: rect, at: y, snapshot: s)
            y -= 24

            y = drawSavingsStandings(in: rect, at: y, snapshot: s)

            if !s.activeLoans.isEmpty {
                y -= 18
                y = drawLoanProgressSection(in: rect, at: y, loans: s.activeLoans)
            }

            drawFooter(in: rect, label: "Statement for \(s.month.displayName)")
        }
    }

    // MARK: Monthly — Hero band

    /// One big Fund Balance number with an inline secondary stat strip
    /// underneath. Replaces the v1 four-card metric row.
    private func drawHeroBand(in pageRect: CGRect, at y: CGFloat, snapshot s: MonthlyStatementSnapshot) -> CGFloat {
        let leftMargin: CGFloat = 40

        // Eyebrow label
        let eyebrowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.darkGray,
            .kern: 1.5
        ]
        "FUND BALANCE".draw(at: CGPoint(x: leftMargin, y: y - 12), withAttributes: eyebrowAttrs)

        // Hero number
        let heroAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 38, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let hero = CurrencyFormatter.shared.format(s.fundBalance)
        hero.draw(at: CGPoint(x: leftMargin, y: y - 52), withAttributes: heroAttrs)

        // Divider rule under the number
        let cg = NSGraphicsContext.current?.cgContext
        cg?.saveGState()
        cg?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.30).cgColor)
        cg?.setLineWidth(0.5)
        cg?.move(to: CGPoint(x: leftMargin, y: y - 60))
        cg?.addLine(to: CGPoint(x: pageRect.width - leftMargin, y: y - 60))
        cg?.strokePath()
        cg?.restoreGState()

        // Secondary stat strip
        let stripAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray
        ]
        let line1 = "\(CurrencyFormatter.shared.format(s.totalContributions)) contributed   ·   \(CurrencyFormatter.shared.format(s.totalOutstandingLoans)) in active loans"
        line1.draw(at: CGPoint(x: leftMargin, y: y - 78), withAttributes: stripAttrs)

        let memberWord = s.activeMembersCount == 1 ? "member" : "members"
        let loanWord = s.activeLoansCount == 1 ? "loan" : "loans"
        let line2 = "\(s.activeMembersCount) active \(memberWord)   ·   \(s.activeLoansCount) \(loanWord) being repaid"
        line2.draw(at: CGPoint(x: leftMargin, y: y - 94), withAttributes: stripAttrs)

        return y - 100
    }

    // MARK: Monthly — Savings Standings (podium + list)

    private func drawSavingsStandings(in pageRect: CGRect, at yIn: CGFloat,
                                      snapshot s: MonthlyStatementSnapshot) -> CGFloat {
        var y = yIn
        let leftMargin: CGFloat = 40

        // Section heading with trophy
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        "🏆  Savings Standings".draw(at: CGPoint(x: leftMargin, y: y - 14), withAttributes: titleAttrs)
        y -= 26

        // Rank: contributions DESC, tiebreak by joinDate ASC (longer-tenured first).
        let ranked = s.memberRows.sorted { lhs, rhs in
            if lhs.contributions != rhs.contributions {
                return lhs.contributions > rhs.contributions
            }
            switch (lhs.joinDate, rhs.joinDate) {
            case (let l?, let r?): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.name < rhs.name
            }
        }

        let topThree = Array(ranked.prefix(3))
        let rest = Array(ranked.dropFirst(3))

        // Podium
        if !topThree.isEmpty {
            let availableWidth = pageRect.width - leftMargin * 2
            let spacing: CGFloat = 12
            let cardCount = max(topThree.count, 1)
            let cardWidth = (availableWidth - spacing * CGFloat(cardCount - 1)) / CGFloat(cardCount)
            let cardHeight: CGFloat = 110

            var x = leftMargin
            for (index, row) in topThree.enumerated() {
                drawPodiumCard(
                    at: CGRect(x: x, y: y - cardHeight, width: cardWidth, height: cardHeight),
                    rank: index,
                    row: row
                )
                x += cardWidth + spacing
            }
            y -= cardHeight + 14
        }

        // Compact list for ranks 4+
        if !rest.isEmpty {
            for row in rest {
                drawSecondaryRankRow(at: y, leftMargin: leftMargin, contentWidth: pageRect.width - leftMargin * 2, row: row)
                y -= 22
            }
        }

        return y
    }

    private func drawPodiumCard(at rect: CGRect, rank: Int, row: MonthlyStatementSnapshot.MemberRow) {
        let cg = NSGraphicsContext.current?.cgContext

        // Background tint based on rank
        let bgColor: NSColor = {
            switch rank {
            case 0: return NSColor.systemYellow.withAlphaComponent(0.12)
            case 1: return NSColor.systemGray.withAlphaComponent(0.10)
            case 2: return NSColor(calibratedRed: 0.80, green: 0.50, blue: 0.20, alpha: 0.10)
            default: return NSColor.systemGray.withAlphaComponent(0.05)
            }
        }()
        cg?.saveGState()
        cg?.setFillColor(bgColor.cgColor)
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        cg?.restoreGState()

        cg?.saveGState()
        cg?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.20).cgColor)
        cg?.setLineWidth(0.5)
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).stroke()
        cg?.restoreGState()

        // Medal row — crown only for #1, otherwise just the medal.
        let medal: String = ["🥇", "🥈", "🥉"][min(rank, 2)]
        let medalLine = rank == 0 ? "👑  🥇" : medal
        let medalAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22)
        ]
        let medalSize = medalLine.size(withAttributes: medalAttrs)
        medalLine.draw(
            at: CGPoint(x: rect.midX - medalSize.width / 2, y: rect.maxY - 36),
            withAttributes: medalAttrs
        )

        // Name (centered)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let nameSize = row.name.size(withAttributes: nameAttrs)
        row.name.draw(
            at: CGPoint(x: rect.midX - nameSize.width / 2, y: rect.minY + 44),
            withAttributes: nameAttrs
        )

        // Role (centered, secondary)
        let roleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.darkGray
        ]
        let roleSize = row.role.size(withAttributes: roleAttrs)
        row.role.draw(
            at: CGPoint(x: rect.midX - roleSize.width / 2, y: rect.minY + 30),
            withAttributes: roleAttrs
        )

        // Amount (centered, larger)
        let amountAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let amountStr = CurrencyFormatter.shared.format(row.contributions)
        let amountSize = amountStr.size(withAttributes: amountAttrs)
        amountStr.draw(
            at: CGPoint(x: rect.midX - amountSize.width / 2, y: rect.minY + 10),
            withAttributes: amountAttrs
        )
    }

    private func drawSecondaryRankRow(at y: CGFloat, leftMargin: CGFloat,
                                      contentWidth: CGFloat,
                                      row: MonthlyStatementSnapshot.MemberRow) {
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        row.name.draw(at: CGPoint(x: leftMargin + 8, y: y - 14), withAttributes: nameAttrs)

        let roleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]
        row.role.draw(at: CGPoint(x: leftMargin + 180, y: y - 14), withAttributes: roleAttrs)

        let amountAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        var attrs = amountAttrs
        attrs[.paragraphStyle] = para
        let amountStr = CurrencyFormatter.shared.format(row.contributions)
        let amountRect = CGRect(x: leftMargin + contentWidth - 130, y: y - 14, width: 130 - 4, height: 14)
        amountStr.draw(in: amountRect, withAttributes: attrs)

        // Faint divider
        let cg = NSGraphicsContext.current?.cgContext
        cg?.saveGState()
        cg?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.18).cgColor)
        cg?.setLineWidth(0.5)
        cg?.move(to: CGPoint(x: leftMargin + 8, y: y - 18))
        cg?.addLine(to: CGPoint(x: leftMargin + contentWidth - 8, y: y - 18))
        cg?.strokePath()
        cg?.restoreGState()
    }

    // MARK: Monthly — Loan Repayment Progress

    private func drawLoanProgressSection(in pageRect: CGRect, at yIn: CGFloat,
                                         loans: [MonthlyStatementSnapshot.LoanRow]) -> CGFloat {
        var y = yIn
        let leftMargin: CGFloat = 40

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        "💪  Loan Repayment Progress".draw(at: CGPoint(x: leftMargin, y: y - 14), withAttributes: titleAttrs)
        y -= 26

        for loan in loans {
            drawLoanProgressCard(in: pageRect, at: y, loan: loan)
            y -= 64
        }
        return y
    }

    private func drawLoanProgressCard(in pageRect: CGRect, at yTop: CGFloat,
                                      loan: MonthlyStatementSnapshot.LoanRow) {
        let leftMargin: CGFloat = 40
        let rightMargin: CGFloat = 40
        let contentWidth = pageRect.width - leftMargin - rightMargin

        // Member name (left)
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        loan.memberName.draw(at: CGPoint(x: leftMargin, y: yTop - 14), withAttributes: nameAttrs)

        // Percent + marker (right)
        let percentLabel = "\(Int((loan.percentRepaid * 100).rounded())) % repaid"
        let markerSpace = loan.marker.emoji.isEmpty ? "" : "  \(loan.marker.emoji)"
        let percentText = "\(percentLabel)\(markerSpace)"
        let percentAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: loan.isOverdue ? NSColor.systemRed : NSColor.darkGray
        ]
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        var pAttrs = percentAttrs
        pAttrs[.paragraphStyle] = para
        let percentRect = CGRect(x: leftMargin, y: yTop - 14, width: contentWidth, height: 14)
        percentText.draw(in: percentRect, withAttributes: pAttrs)

        // Progress bar
        let barY = yTop - 30
        let barHeight: CGFloat = 8
        let barRect = CGRect(x: leftMargin, y: barY, width: contentWidth, height: barHeight)

        let cg = NSGraphicsContext.current?.cgContext
        cg?.saveGState()
        cg?.setFillColor(NSColor.systemGray.withAlphaComponent(0.18).cgColor)
        NSBezierPath(roundedRect: barRect, xRadius: 4, yRadius: 4).fill()
        cg?.restoreGState()

        let fillWidth = contentWidth * CGFloat(loan.percentRepaid)
        if fillWidth > 0.5 {
            let fillRect = CGRect(x: leftMargin, y: barY, width: fillWidth, height: barHeight)
            cg?.saveGState()
            NSBezierPath(roundedRect: fillRect, xRadius: 4, yRadius: 4).addClip()
            let colors: CFArray = [
                NSColor.systemGreen.withAlphaComponent(0.65).cgColor,
                NSColor.systemGreen.cgColor
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                cg?.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: leftMargin, y: barY),
                    end: CGPoint(x: leftMargin + fillWidth, y: barY),
                    options: []
                )
            }
            cg?.restoreGState()
        }

        // Sub-line: remaining + next due
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]
        let remainingPart = "\(CurrencyFormatter.shared.format(loan.balance)) of \(CurrencyFormatter.shared.format(loan.originalAmount)) remaining"
        let nextPart: String = {
            guard let due = loan.nextPaymentDue, loan.balance > 0.01 else { return "" }
            return "Next: \(CurrencyFormatter.shared.format(loan.monthlyPayment)) due \(DateFormatter.fullDate.string(from: due))"
        }()
        let subText = nextPart.isEmpty ? remainingPart : "\(remainingPart)   ·   \(nextPart)"
        subText.draw(at: CGPoint(x: leftMargin, y: yTop - 50), withAttributes: subAttrs)
    }

    // MARK: Rendering — Member Statement

    private func renderMember(_ s: MemberStatementSnapshot) throws -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let auxiliary: [String: Any] = [
            kCGPDFContextTitle as String: "\(s.memberName) — Statement for \(s.month.displayName)",
            kCGPDFContextAuthor as String: "Bob Kitchen",
            kCGPDFContextCreator as String: "Parachichi House Solidarity Fund",
            kCGPDFContextSubject as String: "Member statement, \(s.memberName), \(s.month.displayName)",
            kCGPDFContextKeywords as String: "Solidarity Fund, Parachichi House, Member Statement"
        ]
        let safeName = s.memberName.replacingOccurrences(of: " ", with: "-")

        return try renderPDF(pageRect: pageRect, auxiliary: auxiliary, fileNameStem: "ParachichiHouse_\(safeName)_\(s.month.fileNameLabel)") { rect in
            var y = rect.height - 50
            y = drawHeader(in: rect, at: y, subtitle: "Statement for \(s.month.displayName)")
            y -= 8
            y = drawMemberHeading(in: rect, at: y, snapshot: s)
            y -= 14
            y = drawOpeningClosing(in: rect, at: y, snapshot: s)
            y -= 16

            y = drawSection(title: "Activity in \(s.month.displayName)", in: rect, at: y)
            y = drawMemberEntriesTable(in: rect, at: y, entries: s.entries)

            if !s.activeLoans.isEmpty {
                y -= 16
                y = drawSection(title: "Outstanding Obligations", in: rect, at: y)
                _ = drawActiveLoanFooter(in: rect, at: y, loans: s.activeLoans)
            }

            drawFooter(in: rect, label: "\(s.memberName) — \(s.month.displayName)")
        }
    }

    // MARK: PDF context plumbing

    private func renderPDF(pageRect: CGRect,
                           auxiliary: [String: Any],
                           fileNameStem: String,
                           body: (CGRect) -> Void) throws -> URL {
        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let cg = CGContext(consumer: consumer, mediaBox: &mediaBox, auxiliary as CFDictionary) else {
            throw PDFError.contextCreationFailed
        }

        cg.beginPDFPage([:] as CFDictionary)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)

        body(pageRect)

        NSGraphicsContext.restoreGraphicsState()
        cg.endPDFPage()
        cg.closePDF()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileNameStem).pdf")
        try data.write(to: url)
        return url
    }

    // MARK: Header / footer

    /// Draws the brand block at the top of either report. Returns the
    /// y-coordinate immediately below the block.
    @discardableResult
    private func drawHeader(in pageRect: CGRect, at yPosition: CGFloat, subtitle: String) -> CGFloat {
        var y = yPosition
        let leftMargin: CGFloat = 40
        let blockHeight: CGFloat = 70

        // Background band
        let cg = NSGraphicsContext.current?.cgContext
        cg?.saveGState()
        cg?.setFillColor(NSColor.systemGray.withAlphaComponent(0.10).cgColor)
        cg?.fill(CGRect(x: 0, y: y - blockHeight, width: pageRect.width, height: blockHeight))
        cg?.restoreGState()

        // Logo
        let logoSize: CGFloat = 50
        let logoRect = CGRect(x: leftMargin, y: y - blockHeight + 10, width: logoSize, height: logoSize)
        if let img = NSImage(named: "AvocadoLogo") {
            img.draw(in: logoRect)
        } else {
            drawTextLogoFallback(in: logoRect)
        }

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        "Parachichi House — Solidarity Fund"
            .draw(at: CGPoint(x: leftMargin + logoSize + 15, y: y - 30), withAttributes: titleAttrs)

        // Subtitle
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.darkGray
        ]
        subtitle.draw(at: CGPoint(x: leftMargin + logoSize + 15, y: y - 50), withAttributes: subAttrs)

        // "Issued" date right-aligned
        let issuedAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]
        let issued = "Issued \(DateFormatter.fullDate.string(from: Date()))"
        let issuedSize = issued.size(withAttributes: issuedAttrs)
        issued.draw(
            at: CGPoint(x: pageRect.width - 40 - issuedSize.width, y: y - 50),
            withAttributes: issuedAttrs
        )

        y -= blockHeight
        return y
    }

    private func drawFooter(in pageRect: CGRect, label: String) {
        let cg = NSGraphicsContext.current?.cgContext
        cg?.saveGState()
        cg?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.25).cgColor)
        cg?.setLineWidth(0.5)
        cg?.move(to: CGPoint(x: 40, y: 35))
        cg?.addLine(to: CGPoint(x: pageRect.width - 40, y: 35))
        cg?.strokePath()
        cg?.restoreGState()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.darkGray
        ]
        label.draw(at: CGPoint(x: 40, y: 20), withAttributes: attrs)

        let right = "Parachichi House Solidarity Fund"
        let rightSize = right.size(withAttributes: attrs)
        right.draw(at: CGPoint(x: pageRect.width - 40 - rightSize.width, y: 20), withAttributes: attrs)
    }

    /// Avocado-green disc with monogram — stand-in for the logo asset
    /// when it can't be loaded, so the report still has a brand mark.
    private func drawTextLogoFallback(in rect: CGRect) {
        let cg = NSGraphicsContext.current?.cgContext
        cg?.saveGState()
        let avocado = NSColor(calibratedRed: 0.42, green: 0.55, blue: 0.30, alpha: 1)
        cg?.setFillColor(avocado.cgColor)
        NSBezierPath(ovalIn: rect).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let text = "PHSF"
        let size = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                  withAttributes: attrs)
        cg?.restoreGState()
    }

    // MARK: Section helpers

    @discardableResult
    private func drawSection(title: String, in pageRect: CGRect, at y: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        title.draw(at: CGPoint(x: 40, y: y - 14), withAttributes: attrs)
        return y - 22
    }

    // MARK: Member statement — heading & balances

    private func drawMemberHeading(in pageRect: CGRect, at y: CGFloat, snapshot s: MemberStatementSnapshot) -> CGFloat {
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        s.memberName.draw(at: CGPoint(x: 40, y: y - 22), withAttributes: nameAttrs)

        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray
        ]
        var meta = s.memberRole
        if let join = s.joinDate {
            meta += " • Member since \(DateFormatter.fullDate.string(from: join))"
        }
        meta.draw(at: CGPoint(x: 40, y: y - 40), withAttributes: metaAttrs)

        return y - 50
    }

    private func drawOpeningClosing(in pageRect: CGRect, at y: CGFloat, snapshot s: MemberStatementSnapshot) -> CGFloat {
        let leftMargin: CGFloat = 40
        let availableWidth = pageRect.width - leftMargin * 2
        let cardWidth = (availableWidth - 12) / 2
        let cardHeight: CGFloat = 80

        drawBalancePairCard(
            at: CGRect(x: leftMargin, y: y - cardHeight, width: cardWidth, height: cardHeight),
            title: "Contributions",
            opening: s.openingContributions,
            closing: s.closingContributions,
            tint: .systemBlue
        )
        drawBalancePairCard(
            at: CGRect(x: leftMargin + cardWidth + 12, y: y - cardHeight, width: cardWidth, height: cardHeight),
            title: "Loan Balance",
            opening: s.openingLoanBalance,
            closing: s.closingLoanBalance,
            tint: s.closingLoanBalance > 0 ? .systemOrange : .systemGreen
        )
        return y - cardHeight
    }

    private func drawBalancePairCard(at rect: CGRect, title: String,
                                     opening: Double, closing: Double, tint: NSColor) {
        let cg = NSGraphicsContext.current?.cgContext
        cg?.saveGState()
        cg?.setFillColor(NSColor.white.cgColor)
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        cg?.restoreGState()

        cg?.saveGState()
        cg?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.20).cgColor)
        cg?.setLineWidth(0.5)
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).stroke()
        cg?.restoreGState()

        // Accent stripe
        cg?.saveGState()
        cg?.setFillColor(tint.cgColor)
        cg?.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 3))
        cg?.restoreGState()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.darkGray
        ]
        title.draw(at: CGPoint(x: rect.minX + 10, y: rect.maxY - 22), withAttributes: titleAttrs)

        let smallLabel: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor.gray
        ]
        let openingValueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.darkGray
        ]
        let closingValueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.black
        ]

        // Opening
        "Opening".draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 28), withAttributes: smallLabel)
        CurrencyFormatter.shared.format(opening).draw(
            at: CGPoint(x: rect.minX + 10, y: rect.minY + 12),
            withAttributes: openingValueAttrs
        )

        // Closing (right-aligned)
        let closingValue = CurrencyFormatter.shared.format(closing)
        let closingSize = closingValue.size(withAttributes: closingValueAttrs)
        let closingLabelText = "Closing"
        let closingLabelSize = closingLabelText.size(withAttributes: smallLabel)
        closingLabelText.draw(
            at: CGPoint(x: rect.maxX - 10 - closingLabelSize.width, y: rect.minY + 28),
            withAttributes: smallLabel
        )
        closingValue.draw(
            at: CGPoint(x: rect.maxX - 10 - closingSize.width, y: rect.minY + 10),
            withAttributes: closingValueAttrs
        )

        // Arrow
        let arrowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.systemGray
        ]
        let arrow = "→"
        let arrowSize = arrow.size(withAttributes: arrowAttrs)
        arrow.draw(
            at: CGPoint(x: rect.midX - arrowSize.width / 2, y: rect.minY + 16),
            withAttributes: arrowAttrs
        )
    }

    // MARK: Member statement — entries table

    private func drawMemberEntriesTable(in pageRect: CGRect, at yStart: CGFloat,
                                        entries: [MemberStatementSnapshot.Entry]) -> CGFloat {
        let leftMargin: CGFloat = 40
        let widths: [CGFloat] = [80, 110, 230, 110]  // date, kind, detail, amount
        let headers = ["Date", "Type", "Detail", "Amount"]
        var y = drawTableHeader(headers, widths: widths, at: yStart, leftMargin: leftMargin)

        if entries.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.darkGray
            ]
            "No activity in the period.".draw(at: CGPoint(x: leftMargin, y: y - 14), withAttributes: attrs)
            return y - 22
        }

        for (index, entry) in entries.enumerated() {
            if index % 2 == 1 {
                let cg = NSGraphicsContext.current?.cgContext
                cg?.saveGState()
                cg?.setFillColor(NSColor.systemGray.withAlphaComponent(0.05).cgColor)
                cg?.fill(CGRect(x: leftMargin - 4, y: y - 18, width: widths.reduce(0, +) + 8, height: 18))
                cg?.restoreGState()
            }
            let amount = entry.signedAmount
            let amountStr = (amount >= 0 ? "+" : "-") + CurrencyFormatter.shared.format(abs(amount))
            let values = [
                DateFormatter.shortDate.string(from: entry.date),
                entry.kind,
                entry.detail,
                amountStr
            ]
            drawTableRow(values, widths: widths, at: y, leftMargin: leftMargin, bold: false,
                         coloredColumn: 3, color: amount >= 0 ? NSColor.systemGreen : NSColor.black)
            y -= 18
        }

        return y
    }

    private func drawActiveLoanFooter(in pageRect: CGRect, at y: CGFloat,
                                      loans: [MemberStatementSnapshot.ActiveLoan]) -> CGFloat {
        var currentY = y
        let leftMargin: CGFloat = 40
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]
        for loan in loans {
            let dueText: String = {
                guard let d = loan.nextDueDate else { return "" }
                return " • Next payment due \(DateFormatter.fullDate.string(from: d))"
            }()
            let line = "Active loan: \(CurrencyFormatter.shared.format(loan.balance)) outstanding (originally \(CurrencyFormatter.shared.format(loan.originalAmount))) • Monthly payment \(CurrencyFormatter.shared.format(loan.monthlyPayment))\(dueText)"
            line.draw(at: CGPoint(x: leftMargin, y: currentY - 12), withAttributes: attrs)
            currentY -= 16
        }
        return currentY
    }

    // MARK: Generic table primitives

    @discardableResult
    private func drawTableHeader(_ headers: [String], widths: [CGFloat],
                                 at y: CGFloat, leftMargin: CGFloat) -> CGFloat {
        let cg = NSGraphicsContext.current?.cgContext
        cg?.saveGState()
        cg?.setFillColor(NSColor.systemGray.withAlphaComponent(0.12).cgColor)
        cg?.fill(CGRect(x: leftMargin - 4, y: y - 18, width: widths.reduce(0, +) + 8, height: 18))
        cg?.restoreGState()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.darkGray
        ]

        var x = leftMargin
        for (index, header) in headers.enumerated() {
            let para = NSMutableParagraphStyle()
            para.alignment = (index == 0 || index == 1) ? .left : .right
            var rowAttrs = attrs
            rowAttrs[.paragraphStyle] = para
            let rect = CGRect(x: x, y: y - 14, width: widths[index] - 4, height: 14)
            header.draw(in: rect, withAttributes: rowAttrs)
            x += widths[index]
        }

        cg?.saveGState()
        cg?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.30).cgColor)
        cg?.setLineWidth(0.5)
        cg?.move(to: CGPoint(x: leftMargin, y: y - 18))
        cg?.addLine(to: CGPoint(x: leftMargin + widths.reduce(0, +), y: y - 18))
        cg?.strokePath()
        cg?.restoreGState()

        return y - 20
    }

    private func drawTableRow(_ values: [String], widths: [CGFloat],
                              at y: CGFloat, leftMargin: CGFloat, bold: Bool,
                              coloredColumn: Int? = nil, color: NSColor = .black) {
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: bold ? .semibold : .regular),
            .foregroundColor: NSColor.black
        ]

        var x = leftMargin
        for (index, value) in values.enumerated() {
            let para = NSMutableParagraphStyle()
            para.alignment = (index == 0 || index == 1) ? .left : .right
            para.lineBreakMode = .byTruncatingTail
            var attrs = baseAttrs
            attrs[.paragraphStyle] = para
            if index == coloredColumn { attrs[.foregroundColor] = color }
            let rect = CGRect(x: x, y: y - 14, width: widths[index] - 4, height: 14)
            value.draw(in: rect, withAttributes: attrs)
            x += widths[index]
        }
    }
}

// MARK: - Helpers

extension DateFormatter {
    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM yy"
        return f
    }()
    static let shortMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yy"
        return f
    }()
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}

#endif
