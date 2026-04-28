//
//  ReportsView.swift
//  SolidarityFundr
//
//  Two reports, one screen:
//    1. Monthly Statement — fund-wide compiled statement for a chosen
//       month (the document Bob shares with the household each month).
//    2. Member Statement — the same scope, narrowed to a single member.
//
//  Both are period-bounded by a single Month picker. PDFs render via
//  PDFGenerator and open in Preview for the user to print or share.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

#if !os(macOS)
// Reports rely on the AppKit-only PDF drawing pipeline. iPhone shows
// a clean placeholder rather than carrying a parallel UIKit stack.
struct ReportsView: View {
    var body: some View {
        ContentUnavailableView(
            "Reports are available on Mac",
            systemImage: "doc.text",
            description: Text("Open the fund on your Mac to generate and share PDF statements.")
        )
    }
}
#else

struct ReportsView: View {
    @EnvironmentObject var dataManager: DataManager

    @State private var selectedReportType: ReportType = .monthlyStatement
    @State private var selectedMonth: StatementMonth = .current
    @State private var selectedMember: Member?
    @State private var isGeneratingPDF = false
    @State private var errorMessage: String?

    enum ReportType: String, CaseIterable, Identifiable {
        case monthlyStatement = "Monthly Statement"
        case memberStatement = "Member Statement"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .monthlyStatement: return "doc.text.image.fill"
            case .memberStatement: return "person.text.rectangle.fill"
            }
        }

        var subtitle: String {
            switch self {
            case .monthlyStatement: return "Fund-wide statement for the month"
            case .memberStatement: return "Statement for a single member"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            reportTypePicker
            Divider()
            monthRow
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    switch selectedReportType {
                    case .monthlyStatement:
                        MonthlyStatementPreview(
                            month: selectedMonth,
                            isGenerating: $isGeneratingPDF,
                            onGenerate: generateMonthlyPDF
                        )
                    case .memberStatement:
                        if let member = selectedMember {
                            MemberStatementPreview(
                                member: member,
                                month: selectedMonth,
                                isGenerating: $isGeneratingPDF,
                                onBack: { selectedMember = nil },
                                onGenerate: { generateMemberPDF(for: member) }
                            )
                        } else {
                            MemberPicker(selectedMember: $selectedMember)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Reports")
        .alert(
            "Could not generate PDF",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Report-type picker

    private var reportTypePicker: some View {
        HStack(spacing: 12) {
            ForEach(ReportType.allCases) { type in
                ReportTypeChip(
                    reportType: type,
                    isSelected: selectedReportType == type
                ) {
                    selectedReportType = type
                    if type == .monthlyStatement {
                        selectedMember = nil
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Month picker row

    private var monthRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)

            MonthPicker(selection: $selectedMonth)

            Spacer()

            // Quick previous/next buttons make month-stepping feel right
            // for a workflow that is mostly "this month minus one".
            HStack(spacing: 6) {
                Button { stepMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                Button { stepMonth(1) } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedMonth == .current && false) // future months allowed; keep both arrows live
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func stepMonth(_ delta: Int) {
        let cal = Calendar.current
        let date = selectedMonth.startDate
        guard let stepped = cal.date(byAdding: .month, value: delta, to: date) else { return }
        let comps = cal.dateComponents([.year, .month], from: stepped)
        selectedMonth = StatementMonth(year: comps.year!, month: comps.month!)
    }

    // MARK: PDF generation

    private func generateMonthlyPDF() {
        runPDFGeneration { generator in
            try await generator.generateMonthlyStatement(
                month: selectedMonth,
                dataManager: dataManager
            )
        }
    }

    private func generateMemberPDF(for member: Member) {
        runPDFGeneration { generator in
            try await generator.generateMemberStatement(
                member: member,
                month: selectedMonth,
                dataManager: dataManager
            )
        }
    }

    private func runPDFGeneration(_ work: @escaping (PDFGenerator) async throws -> URL) {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        Task {
            do {
                let url = try await work(PDFGenerator())
                await MainActor.run {
                    isGeneratingPDF = false
                    NSWorkspace.shared.open(url)
                    // Let Preview pick it up before we delete the temp file.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            } catch {
                await MainActor.run {
                    isGeneratingPDF = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Report-type chip

private struct ReportTypeChip: View {
    let reportType: ReportsView.ReportType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: reportType.icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(reportType.rawValue)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(reportType.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.35) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Monthly statement preview

private struct MonthlyStatementPreview: View {
    @EnvironmentObject var dataManager: DataManager
    let month: StatementMonth
    @Binding var isGenerating: Bool
    let onGenerate: () -> Void

    private var calculator: StatementCalculator {
        StatementCalculator(asOf: month.endDate)
    }

    /// Active members ranked by contributions DESC, tiebreak join date ASC.
    /// Mirrors `PDFGenerator.drawSavingsStandings` so the preview shows
    /// what the printout will show.
    private var rankedMembers: [MemberRow] {
        dataManager.members
            .filter { calculator.wasActive($0) }
            .map { member in
                MemberRow(
                    name: member.name ?? "Unknown",
                    role: member.memberRole.displayName,
                    contributions: calculator.contributions(for: member),
                    joinDate: member.joinDate
                )
            }
            .sorted { lhs, rhs in
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
    }

    private var activeLoanRows: [LoanProgressViewModel] {
        let allLoans = (try? PersistenceController.shared.container.viewContext.fetch(Loan.fetchRequest())) ?? []
        return allLoans
            .filter { loan in
                guard let issued = loan.issueDate, issued <= month.endDate else { return false }
                if let completed = loan.completedDate, completed <= month.endDate { return false }
                return calculator.balance(for: loan) > 0.01
            }
            .map { loan in
                let asOfOverdue: Bool = {
                    guard let due = loan.dueDate else { return false }
                    return due < month.endDate
                }()
                let balance = calculator.balance(for: loan)
                let percent = loan.amount > 0 ? min(1.0, (loan.amount - balance) / loan.amount) : 0
                return LoanProgressViewModel(
                    memberName: loan.member?.name ?? "Unknown",
                    originalAmount: loan.amount,
                    balance: balance,
                    monthlyPayment: loan.monthlyPayment,
                    nextDue: loan.nextPaymentDue,
                    percentRepaid: percent,
                    marker: LoanProgressMarker.evaluate(percentRepaid: percent, isOverdue: asOfOverdue),
                    isOverdue: asOfOverdue
                )
            }
            .sorted { $0.memberName < $1.memberName }
    }

    private var fundBalance: Double { calculator.fundBalance() }
    private var totalContributions: Double { calculator.totalContributions() }
    private var totalOutstanding: Double { calculator.totalOutstandingLoans() }
    private var activeCount: Int { calculator.activeMembersCount() }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Statement for \(month.displayName)")
                .font(.title2.weight(.semibold))

            heroBand

            savingsStandings

            if !activeLoanRows.isEmpty {
                loanProgress
            }

            generateButton
        }
    }

    // MARK: Hero band

    private var heroBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FUND BALANCE")
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.shared.format(fundBalance))
                .font(.system(size: 44, weight: .semibold))
                .monospacedDigit()
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("\(CurrencyFormatter.shared.format(totalContributions)) contributed   ·   \(CurrencyFormatter.shared.format(totalOutstanding)) in active loans")
                Text("\(activeCount) active \(activeCount == 1 ? "member" : "members")   ·   \(activeLoanRows.count) \(activeLoanRows.count == 1 ? "loan" : "loans") being repaid")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Savings standings

    private var savingsStandings: some View {
        let topThree = Array(rankedMembers.prefix(3))
        let rest = Array(rankedMembers.dropFirst(3))

        return VStack(alignment: .leading, spacing: 14) {
            Text("🏆  Savings Standings")
                .font(.headline)

            if !topThree.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(topThree.enumerated()), id: \.offset) { idx, row in
                        PodiumCard(rank: idx, row: row)
                    }
                }
            }

            if !rest.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rest.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.name)
                                .fontWeight(.medium)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(row.role)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(CurrencyFormatter.shared.format(row.contributions))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .font(.callout)
                        .overlay(Divider(), alignment: .bottom)
                    }
                }
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Loan progress

    private var loanProgress: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("💪  Loan Repayment Progress")
                .font(.headline)

            VStack(spacing: 14) {
                ForEach(Array(activeLoanRows.enumerated()), id: \.offset) { _, row in
                    LoanProgressCard(row: row)
                }
            }
        }
    }

    private var generateButton: some View {
        Button(action: onGenerate) {
            HStack {
                if isGenerating {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                Text("Generate & Open in Preview")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    // MARK: View models (preview-local)

    fileprivate struct MemberRow {
        let name: String
        let role: String
        let contributions: Double
        let joinDate: Date?
    }

    fileprivate struct LoanProgressViewModel {
        let memberName: String
        let originalAmount: Double
        let balance: Double
        let monthlyPayment: Double
        let nextDue: Date?
        let percentRepaid: Double
        let marker: LoanProgressMarker
        let isOverdue: Bool
    }
}

// MARK: - Podium card

private struct PodiumCard: View {
    let rank: Int  // 0, 1, 2
    let row: MonthlyStatementPreview.MemberRow

    private var medal: String { ["🥇", "🥈", "🥉"][min(rank, 2)] }

    private var bgTint: Color {
        switch rank {
        case 0: return Color.yellow.opacity(0.18)
        case 1: return Color.gray.opacity(0.15)
        case 2: return Color.orange.opacity(0.18)
        default: return Color.gray.opacity(0.08)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(rank == 0 ? "👑  🥇" : medal)
                .font(.system(size: 24))
            Text(row.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .multilineTextAlignment(.center)
            Text(row.role)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.shared.format(row.contributions))
                .font(.headline)
                .monospacedDigit()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(bgTint)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
    }
}

// MARK: - Loan progress card

private struct LoanProgressCard: View {
    let row: MonthlyStatementPreview.LoanProgressViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.memberName)
                    .font(.callout.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    Text("\(Int((row.percentRepaid * 100).rounded())) % repaid")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(row.isOverdue ? Color.red : .secondary)
                    if !row.marker.emoji.isEmpty {
                        Text(row.marker.emoji)
                    }
                }
            }
            ProgressView(value: row.percentRepaid)
                .progressViewStyle(.linear)
                .tint(row.isOverdue ? .red : .green)
            HStack {
                Text("\(CurrencyFormatter.shared.format(row.balance)) of \(CurrencyFormatter.shared.format(row.originalAmount)) remaining")
                Spacer()
                if let due = row.nextDue, row.balance > 0.01 {
                    Text("Next: \(CurrencyFormatter.shared.format(row.monthlyPayment)) due \(due.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Member statement preview

private struct MemberStatementPreview: View {
    @EnvironmentObject var dataManager: DataManager
    let member: Member
    let month: StatementMonth
    @Binding var isGenerating: Bool
    let onBack: () -> Void
    let onGenerate: () -> Void

    private var openingCalc: StatementCalculator { StatementCalculator(asOf: month.priorMonthEndDate) }
    private var closingCalc: StatementCalculator { StatementCalculator(asOf: month.endDate) }

    private var openingContrib: Double { openingCalc.contributions(for: member) }
    private var closingContrib: Double { closingCalc.contributions(for: member) }
    private var openingLoan: Double { openingCalc.outstandingLoanBalance(for: member) }
    private var closingLoan: Double { closingCalc.outstandingLoanBalance(for: member) }

    private var entries: [PeriodEntry] {
        let payments = (member.payments?.allObjects as? [Payment]) ?? []
        var rows: [PeriodEntry] = []

        for payment in payments {
            guard let date = payment.paymentDate,
                  date >= month.startDate, date <= month.endDate else { continue }

            if payment.contributionAmount > 0 {
                rows.append(PeriodEntry(
                    date: date,
                    kind: "Contribution",
                    detail: "Monthly contribution",
                    signedAmount: payment.contributionAmount
                ))
            }
            if payment.loanRepaymentAmount > 0 {
                rows.append(PeriodEntry(
                    date: date,
                    kind: "Loan Repayment",
                    detail: payment.loan?.member?.name.map { "Toward loan: \($0)" } ?? "Loan payment",
                    signedAmount: -payment.loanRepaymentAmount
                ))
            }
        }

        // Loans disbursed to this member during the period
        let loans = (member.loans?.allObjects as? [Loan]) ?? []
        for loan in loans {
            guard let issued = loan.issueDate,
                  issued >= month.startDate, issued <= month.endDate else { continue }
            rows.append(PeriodEntry(
                date: issued,
                kind: "Loan Disbursed",
                detail: "Loan amount: \(CurrencyFormatter.shared.format(loan.amount))",
                signedAmount: -loan.amount
            ))
        }

        return rows.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button(action: onBack) {
                    Label("Members", systemImage: "chevron.left")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(member.name ?? "Unknown")
                    .font(.title2.weight(.semibold))
                Text("\(member.memberRole.displayName) • Statement for \(month.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Opening / Closing
            HStack(spacing: 12) {
                balanceCard(
                    title: "Contributions",
                    opening: openingContrib,
                    closing: closingContrib,
                    tint: .blue
                )
                balanceCard(
                    title: "Loan Balance",
                    opening: openingLoan,
                    closing: closingLoan,
                    tint: closingLoan > 0 ? .orange : .green
                )
            }

            // Period entries
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Date").frame(width: 90, alignment: .leading)
                    Text("Type").frame(width: 130, alignment: .leading)
                    Text("Detail").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Amount").frame(width: 120, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.10))

                if entries.isEmpty {
                    Text("No activity in \(month.displayName).")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(entries) { entry in
                        HStack(spacing: 0) {
                            Text(DateFormatter.shortDate.string(from: entry.date))
                                .frame(width: 90, alignment: .leading)
                            Text(entry.kind)
                                .foregroundStyle(.secondary)
                                .frame(width: 130, alignment: .leading)
                            Text(entry.detail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                            Text(formatSigned(entry.signedAmount))
                                .foregroundStyle(entry.signedAmount > 0 ? .green : .primary)
                                .frame(width: 120, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.secondary.opacity(0.04))
                        .overlay(Divider(), alignment: .bottom)
                    }
                }
            }
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            generateButton
        }
    }

    private func balanceCard(title: String, opening: Double, closing: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Opening")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.shared.format(opening))
                        .font(.subheadline)
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Closing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.shared.format(closing))
                        .font(.headline)
                        .monospacedDigit()
                }
            }
            Capsule().fill(tint).frame(height: 3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatSigned(_ amount: Double) -> String {
        let formatted = CurrencyFormatter.shared.format(abs(amount))
        return amount >= 0 ? "+\(formatted)" : "-\(formatted)"
    }

    private var generateButton: some View {
        Button(action: onGenerate) {
            HStack {
                if isGenerating {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                Text("Generate & Open in Preview")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    private struct PeriodEntry: Identifiable {
        let id = UUID()
        let date: Date
        let kind: String
        let detail: String
        let signedAmount: Double
    }
}

// MARK: - Member picker (for member-statement flow)

private struct MemberPicker: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedMember: Member?

    private var sortedMembers: [Member] {
        dataManager.members.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select a member")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(sortedMembers) { member in
                    Button {
                        selectedMember = member
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.name ?? "Unknown")
                                    .fontWeight(.medium)
                                Text(member.memberRole.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if member.memberStatus != .active {
                                Text(member.memberStatus.rawValue.capitalized)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.red.opacity(0.18))
                                    .foregroundStyle(.red)
                                    .clipShape(Capsule())
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                    .background(Color.secondary.opacity(0.04))
                    .overlay(Divider(), alignment: .bottom)
                }
            }
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// `DateFormatter.shortDate` is declared in PDFGenerator.swift (also
// macOS-only). Reused here so the in-app preview and the printed PDF
// show identical date strings.

#Preview {
    ReportsView()
        .environmentObject(DataManager.shared)
}

#endif
