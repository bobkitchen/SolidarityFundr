//
//  DashboardView.swift
//  SolidarityFundr
//
//  Stock SwiftUI dashboard. Uses NavigationSplitView so the system applies
//  Liquid Glass to the sidebar automatically on macOS 26 — no hand-rolled
//  glass simulators.
//

import SwiftUI
import Charts
import CoreData

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case overview, members, loans, payments, reports, history

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .members: "Members"
        case .loans: "Loans"
        case .payments: "Payments"
        case .reports: "Reports"
        case .history: "History"
        }
    }

    var systemImage: String {
        // Apple's sidebar convention (Mail / Notes / Reminders / Finder) uses
        // unfilled / hierarchical icons. Filled icons read louder than they
        // should next to thin sidebar text.
        switch self {
        case .overview: "chart.line.uptrend.xyaxis"
        case .members:  "person.2"
        case .loans:    "creditcard"
        case .payments: "dollarsign.circle"
        case .reports:  "doc.text"
        case .history:  "clock.arrow.circlepath"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selection: DashboardSection? = .overview

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 640)
        #else
        TabView(selection: $selection) {
            ForEach(DashboardSection.allCases) { section in
                detailContent(for: section)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
                    .tag(Optional(section))
            }
        }
        #endif
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {
            // Brand lockup at the top of the sidebar. The Avocado mark + a
            // serif wordmark gives the app an identity beyond "Solidarity
            // Fund" plain-text title.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image("AvocadoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Solidarity Fund")
                            .font(.system(.headline, design: .serif))
                            .foregroundStyle(.primary)
                        Text("Parachichi House")
                            .font(.caption2)
                            .textCase(.uppercase)
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            ForEach(Array(DashboardSection.allCases.enumerated()), id: \.element) { index, section in
                // Default sidebar styling — system handles selection contrast
                // automatically. Per-section character lives in the detail
                // pages (page tints, brand colors), not the sidebar chrome.
                Label(section.title, systemImage: section.systemImage)
                    .tag(Optional(section))
                    // ⌘1–5 to switch tabs.
                    .keyboardShortcutForSidebarIndex(index, action: { selection = section })
            }
        }
        .listStyle(.sidebar)
        // The brand lockup replaces the plain "Solidarity Fund" navigation
        // title — hide the default title to avoid duplication.
        .navigationTitle("")
        // Pin Fund Status to the bottom of the sidebar column. `safeAreaInset`
        // is the canonical SwiftUI hook for "footer that sits below scrolling
        // content but above safe-area chrome."
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sidebarFundStatusFooter
        }
    }

    @ViewBuilder
    private var sidebarFundStatusFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Fund Status")
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            FundStatusSummary()
                .labeledContentStyle(.automatic)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        detailContent(for: selection ?? .overview, jumpTo: { selection = $0 })
    }

    @ViewBuilder
    private func detailContent(for section: DashboardSection,
                               jumpTo: @escaping (DashboardSection) -> Void = { _ in }) -> some View {
        // Per-section tinting: each page inherits its section's brand color
        // so selection highlights, links, ProgressViews, and prominent buttons
        // pick it up automatically. Members reads olive, Loans honey, etc.
        Group {
            switch section {
            case .overview: OverviewView(onViewAllTransactions: { jumpTo(.payments) })
            case .members: MembersListView()
            case .loans: LoansListView()
            case .payments: PaymentsView()
            case .reports: ReportsView()
            case .history: HistoryView()
            }
        }
        .tint(section.tint)
    }
}

// MARK: - Sidebar keyboard shortcut helper

private extension View {
    /// Attach a ⌘<n+1> keyboard shortcut to the sidebar nav item at `index`.
    /// SwiftUI gives `tag(_:)`-based selection nothing for free here, so we
    /// overlay a hidden Button that owns the shortcut.
    @ViewBuilder
    func keyboardShortcutForSidebarIndex(_ index: Int, action: @escaping () -> Void) -> some View {
        if let key = ["1", "2", "3", "4", "5"][safe: index] {
            self.background(
                Button(action: action) { EmptyView() }
                    .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
            )
        } else {
            self
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Fund Status Summary (sidebar footer)

private struct FundStatusSummary: View {
    @EnvironmentObject var dataManager: DataManager

    private var fundBalance: Double {
        dataManager.fundSettings?.calculateFundBalance() ?? 0
    }
    private var utilization: Double {
        dataManager.fundSettings?.calculateUtilizationPercentage() ?? 0
    }

    var body: some View {
        Group {
            row(
                "Balance",
                value: CurrencyFormatter.shared.format(fundBalance),
                color: BrandColor.avocado
            )
            row(
                "Utilization",
                value: String(format: "%.1f%%", utilization * 100),
                color: utilizationColor(utilization)
            )
            row(
                "Active Loans",
                value: "\(dataManager.activeLoans.count)",
                color: BrandColor.honey
            )
        }
    }

    private func row(_ label: String, value: String, color: Color) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(color)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    private func utilizationColor(_ utilization: Double) -> Color {
        if utilization >= 0.6 { return .red }
        if utilization >= 0.4 { return .orange }
        return .green
    }
}

// MARK: - Overview (default page)
//
// Stock SwiftUI: a Form-style ScrollView of GroupBox cards. GroupBox on
// macOS 26 renders as the appropriate Liquid Glass surface for grouped
// content automatically.

struct OverviewView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var isRecalculating = false
    /// Member that the user wants to record a payment for, when triggered
    /// from a "Record Payment" button on a Due/Overdue row. Drives a
    /// sheet via `.sheet(item:)` so the right member is pre-filled.
    @State private var paymentMember: PaymentTarget?

    /// Closure provided by `DashboardView` so the "View All" link in
    /// Recent Activity can switch the sidebar selection to .payments.
    var onViewAllTransactions: () -> Void = {}

    private var fundBalance: Double { dataManager.fundSettings?.calculateFundBalance() ?? 0 }
    private var utilization: Double { dataManager.fundSettings?.calculateUtilizationPercentage() ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                welcomeHeader
                heroFundBalance
                fundBalanceSparkline
                secondaryMetrics
                whatsDueSection
            }
            .padding()
        }
        .sheet(item: $paymentMember) { target in
            PaymentFormView(
                viewModel: PaymentViewModel(),
                preselectedMember: target.member
            )
        }
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isRecalculating = true
                    dataManager.recalculateAllMemberContributions()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        isRecalculating = false
                    }
                } label: {
                    if isRecalculating {
                        Label("Recalculating", systemImage: "arrow.clockwise")
                            .symbolEffect(.pulse, options: .repeating)
                    } else {
                        Label("Recalculate", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRecalculating)
            }
        }
    }

    // Editorial welcome — Swahili greeting in serif, today's date in muted
    // small caps. Personal touch that says "this is YOUR fund," not "this is
    // a SaaS dashboard."
    @ViewBuilder
    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Habari")
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(.primary)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                .font(.caption2)
                .tracking(1.4)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Hero card: fund balance set in NY system serif at 48pt — magazine
    // numerics. The KSH pill pairs with rounded numerics by default so it
    // gets an explicit serif design override here.
    @ViewBuilder
    private var heroFundBalance: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Fund Balance", systemImage: "banknote")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                CurrencyPill(
                    amount: fundBalance,
                    tint: BrandColor.avocado,
                    size: 48,
                    design: .serif,
                    weight: .semibold
                )
                .accessibilityLabel("Fund balance, \(CurrencyFormatter.shared.format(fundBalance))")

                Divider()

                HStack(spacing: 28) {
                    inlineStat(
                        label: "Utilization",
                        value: String(format: "%.1f%%", utilization * 100),
                        systemImage: "chart.pie",
                        color: utilizationColor(utilization)
                    )
                    inlineStat(
                        label: "Active Loans",
                        value: "\(dataManager.activeLoans.count)",
                        systemImage: "creditcard",
                        color: BrandColor.honey
                    )
                    inlineStat(
                        label: "Active Members",
                        value: "\(dataManager.members.filter { $0.memberStatus == .active }.count)",
                        systemImage: "person.2",
                        color: BrandColor.olive
                    )
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }

    private func inlineStat(label: String, value: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // 30-day fund-balance sparkline. Plots the running `balance` field from
    // each transaction. Pure shape — no axes, no grid — so it reads as a
    // visual cue rather than a chart.
    @ViewBuilder
    private var fundBalanceSparkline: some View {
        let trend = sparklineData
        if trend.count >= 2 {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Trend")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(1.0)
                        Spacer()
                        Text("Last \(trend.count) transactions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Chart(Array(trend.enumerated()), id: \.offset) { index, point in
                        AreaMark(
                            x: .value("Step", index),
                            y: .value("Balance", point)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [BrandColor.avocado.opacity(0.45), BrandColor.avocado.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Step", index),
                            y: .value("Balance", point)
                        )
                        .foregroundStyle(BrandColor.avocado)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 56)
                }
            }
        }
    }

    private var sparklineData: [Double] {
        let recent = dataManager.recentTransactions
            .prefix(30)
            .reversed()
        return recent.map { $0.balance }
    }

    @ViewBuilder
    private var secondaryMetrics: some View {
        let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]
        LazyVGrid(columns: columns, spacing: 16) {
            MiniMetricCard(
                title: "Total Contributions",
                value: CurrencyFormatter.shared.format(dataManager.members.reduce(0) { $0 + $1.totalContributions }),
                systemImage: "tray.and.arrow.down.fill",
                tint: .blue
            )
            MiniMetricCard(
                title: "Outstanding Loans",
                value: CurrencyFormatter.shared.format(dataManager.activeLoans.reduce(0) { $0 + $1.balance }),
                systemImage: "creditcard.fill",
                tint: .orange
            )
            MiniMetricCard(
                title: "Members",
                value: "\(dataManager.members.count)",
                systemImage: "person.3.fill",
                tint: .green
            )
        }
    }

    // MARK: - What's Due
    //
    // Replaces the old "Recent Transactions" panel. Surfaces what needs
    // attention today (overdue loans, payments due this week) with
    // one-tap "Record Payment" actions, plus a slim 3-row recent-activity
    // tail. Browsing the full transaction history lives in the Payments
    // tab; the dashboard's job is to show what to *do* next.

    private var overdueLoans: [Loan] {
        dataManager.activeLoans.filter { $0.isOverdue }
    }

    private var dueThisWeekLoans: [Loan] {
        let now = Date()
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return dataManager.activeLoans.filter { loan in
            guard !loan.isOverdue,
                  let nextDue = loan.nextPaymentDue else { return false }
            return nextDue >= now && nextDue <= weekFromNow
        }
    }

    @ViewBuilder
    private var whatsDueSection: some View {
        VStack(spacing: 16) {
            if !overdueLoans.isEmpty {
                dueGroup(
                    title: "Overdue",
                    systemImage: "exclamationmark.triangle.fill",
                    accent: .red,
                    loans: overdueLoans
                )
            }

            if !dueThisWeekLoans.isEmpty {
                dueGroup(
                    title: "Due This Week",
                    systemImage: "calendar.badge.clock",
                    accent: .orange,
                    loans: dueThisWeekLoans
                )
            }

            if overdueLoans.isEmpty && dueThisWeekLoans.isEmpty {
                allCaughtUpCard
            }

            recentActivityTail
        }
    }

    private func dueGroup(title: String, systemImage: String, accent: Color, loans: [Loan]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(loans) { loan in
                    DueLoanRow(loan: loan, accent: accent) {
                        if let m = loan.member {
                            paymentMember = PaymentTarget(member: m)
                        }
                    }
                    if loan != loans.last {
                        Divider()
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(accent)
                Text(title)
                Spacer()
                Text("\(loans.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var allCaughtUpCard: some View {
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All caught up.")
                        .font(.callout.weight(.semibold))
                    Text("No overdue or upcoming loan payments this week.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var recentActivityTail: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent Activity")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !dataManager.recentTransactions.isEmpty {
                        Button("View All", action: onViewAllTransactions)
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                .padding(.bottom, 8)

                if dataManager.recentTransactions.isEmpty {
                    Text("No activity yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    let recent = Array(dataManager.recentTransactions.prefix(3))
                    VStack(spacing: 0) {
                        ForEach(recent) { transaction in
                            TransactionRowView(transaction: transaction)
                            if transaction != recent.last {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    func utilizationColor(_ utilization: Double) -> Color {
        if utilization >= 0.6 { return .red }
        if utilization >= 0.4 { return .orange }
        return .green
    }
}

// MARK: - DueLoanRow
//
// One row in an Overdue / Due-This-Week group. Shows the member, a
// human-readable timing (e.g. "5 days overdue", "Due in 3 days"), the
// outstanding balance, and a primary "Record Payment" button that opens
// the payment sheet pre-filled for that member.

struct DueLoanRow: View {
    let loan: Loan
    let accent: Color
    let onRecordPayment: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(loan.member?.name ?? "Unknown")
                    .font(.callout.weight(.medium))
                Text(timingLabel)
                    .font(.caption)
                    .foregroundStyle(accent)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.shared.format(loan.balance))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Text("Balance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button(action: onRecordPayment) {
                Label("Record Payment", systemImage: "plus.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .help("Record a payment for \(loan.member?.name ?? "this member")")
        }
        .padding(.vertical, 8)
    }

    private var timingLabel: String {
        if loan.isOverdue, let due = loan.dueDate {
            let days = Calendar.current.dateComponents([.day], from: due, to: Date()).day ?? 0
            if days <= 1 { return "Overdue by 1 day" }
            return "Overdue by \(days) days"
        }
        if let next = loan.nextPaymentDue {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: next).day ?? 0
            if days <= 0 { return "Due today" }
            if days == 1 { return "Due tomorrow" }
            return "Due in \(days) days"
        }
        return ""
    }
}

/// Identifiable wrapper so the dashboard can drive a member-pre-filled
/// PaymentFormView via `.sheet(item:)`.
struct PaymentTarget: Identifiable {
    let member: Member
    var id: NSManagedObjectID { member.objectID }
}

// MARK: - MetricCard
//
// Single canonical small-card metric component used across Overview, Members,
// Loans, Payments. Replaces the previous StatCard / StatisticCard / SummaryCard
// duplicates.

struct MiniMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                        .font(.title3)
                        .accessibilityHidden(true)
                    Spacer()
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

// MARK: - Transaction Row

struct TransactionRowView: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            // Per-member avatar dot — same hash as MembersList avatars, so a
            // glance recognises which member made which transaction.
            avatarDot

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.member?.name ?? "Fund Transaction")
                    .font(.subheadline.weight(.medium))
                Text(transaction.transactionType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.displayAmount)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(transaction.transactionType.isCredit ? .green : .red)
                    .monospacedDigit()
                Text(transaction.transactionDate ?? Date(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transaction.member?.name ?? "Fund Transaction"), \(transaction.transactionType.displayName), \(transaction.displayAmount)")
    }

    @ViewBuilder
    private var avatarDot: some View {
        if let name = transaction.member?.name {
            Circle()
                .fill(BrandColor.avatarTint(for: name).opacity(0.85))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        } else {
            // Fund-level transactions (interest, Bob's investment) get the
            // brand avocado dot.
            Circle()
                .fill(BrandColor.avocado.opacity(0.85))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(DataManager.shared)
}
