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
        switch self {
        case .overview: "chart.line.uptrend.xyaxis"
        case .members: "person.3.fill"
        case .loans: "creditcard.fill"
        case .payments: "dollarsign.circle.fill"
        case .reports: "doc.text.fill"
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
            Section {
                ForEach(DashboardSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(Optional(section))
                }
            }

            Section {
                FundStatusSummary()
            } header: {
                Text("Fund Status")
            }
        }
        .navigationTitle("Solidarity Fund")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        detailContent(for: selection ?? .overview)
    }

    @ViewBuilder
    private func detailContent(for section: DashboardSection) -> some View {
        switch section {
        case .overview: OverviewView()
        case .members: MembersListView()
        case .loans: LoansListView()
        case .payments: PaymentsView()
        case .reports: ReportsView()
        }
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
        VStack(alignment: .leading, spacing: 6) {
            row("Balance", value: CurrencyFormatter.shared.format(fundBalance), color: .green)
            row("Utilization", value: String(format: "%.1f%%", utilization * 100),
                color: utilizationColor(utilization))
            row("Active Loans", value: "\(dataManager.activeLoans.count)", color: .orange)
        }
        .font(.caption)
        .padding(.vertical, 4)
    }

    private func row(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(color).fontWeight(.medium)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metricsGrid
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

    @ViewBuilder
    private var metricsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]
        LazyVGrid(columns: columns, spacing: 16) {
            StatCard(
                title: "Fund Balance",
                value: formatCurrency(dataManager.fundSettings?.calculateFundBalance() ?? 0),
                systemImage: "banknote.fill",
                color: .green
            )
            StatCard(
                title: "Active Members",
                value: "\(dataManager.members.filter { $0.memberStatus == .active }.count)",
                systemImage: "person.3.fill",
                color: .blue
            )
            StatCard(
                title: "Active Loans",
                value: "\(dataManager.activeLoans.count)",
                systemImage: "creditcard.fill",
                color: .orange
            )
            StatCard(
                title: "Utilization",
                value: String(format: "%.1f%%", (dataManager.fundSettings?.calculateUtilizationPercentage() ?? 0) * 100),
                systemImage: "percent",
                color: utilizationColor(dataManager.fundSettings?.calculateUtilizationPercentage() ?? 0)
            )
        }
    }

    @ViewBuilder
    private var recentTransactions: some View {
        GroupBox("Recent Transactions") {
            if dataManager.recentTransactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "doc.text",
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

    func formatCurrency(_ amount: Double) -> String {
        CurrencyFormatter.shared.format(amount)
    }

    func utilizationColor(_ utilization: Double) -> Color {
        if utilization >= 0.6 { return .red }
        if utilization >= 0.4 { return .orange }
        return .green
    }
}

// MARK: - Stat Card
//
// A simple GroupBox-style card. No hand-rolled glass.

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .foregroundStyle(color)
                        .font(.title2)
                        .accessibilityHidden(true)
                    Spacer()
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
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
        HStack {
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
                Text(transaction.transactionDate ?? Date(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transaction.member?.name ?? "Fund Transaction"), \(transaction.transactionType.displayName), \(transaction.displayAmount)")
    }
}

#Preview {
    DashboardView()
        .environmentObject(DataManager.shared)
}
