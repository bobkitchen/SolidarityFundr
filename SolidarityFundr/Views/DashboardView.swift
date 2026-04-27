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

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case overview, members, loans, payments, reports

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .members: "Members"
        case .loans: "Loans"
        case .payments: "Payments"
        case .reports: "Reports"
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

            Section("Fund Status") {
                FundStatusSummary()
            }
        }
        .listStyle(.sidebar)
        // The brand lockup replaces the plain "Solidarity Fund" navigation
        // title — hide the default title to avoid duplication.
        .navigationTitle("")
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
    /// Closure provided by `DashboardView` so the "View All" link in
    /// Recent Transactions can switch the sidebar selection to .payments.
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
                recentTransactions
            }
            .padding()
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

    @ViewBuilder
    private var recentTransactions: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent Transactions")
                        .font(.headline)
                    Spacer()
                    if !dataManager.recentTransactions.isEmpty {
                        Button("View All", action: onViewAllTransactions)
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
                .padding(.bottom, 12)

                if dataManager.recentTransactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "leaf",
                        description: Text("Transactions will appear here once members make payments or take loans.")
                    )
                    .frame(height: 200)
                } else {
                    VStack(spacing: 0) {
                        ForEach(dataManager.recentTransactions.prefix(10)) { transaction in
                            TransactionRowView(transaction: transaction)
                            if transaction != dataManager.recentTransactions.prefix(10).last {
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
