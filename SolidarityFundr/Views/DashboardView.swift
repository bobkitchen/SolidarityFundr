//
//  DashboardView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//  macOS 26 Tahoe HIG Compliant
//

import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab = 0
    @AppStorage("useLiquidGlass") private var useLiquidGlass: Bool = true
    @AppStorage("isSidebarCollapsed") private var isSidebarCollapsed: Bool = false

    private var sidebarWidth: CGFloat {
        isSidebarCollapsed ? 68 : DesignSystem.sidebarExpandedWidth
    }

    var body: some View {
        #if os(macOS)
        if useLiquidGlass {
            HStack(spacing: 0) {
                // Sidebar with macOS 26 glass effects
                FloatingSidebar(
                    selectedSection: $selectedTab,
                    isCollapsed: $isSidebarCollapsed
                )
                .frame(width: sidebarWidth)
                .sidebarGlassBackground() // macOS 26 backgroundExtensionEffect

                // Main content
                DetailView(selectedTab: selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
            }
            .frame(minWidth: isSidebarCollapsed ? 600 : 800, minHeight: 640)
            .background(Color(NSColor.windowBackgroundColor))
            .accessibilityElement(children: .contain)
        } else {
            // Original Design with macOS 26 NavigationSplitView updates
            NavigationSplitView {
                SidebarView(selectedTab: $selectedTab)
                    .sidebarGlassBackground() // macOS 26 backgroundExtensionEffect
            } detail: {
                DetailView(selectedTab: selectedTab)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        #else
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem {
                    Label("Overview", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(0)

            MembersListView()
                .tabItem {
                    Label("Members", systemImage: "person.3.fill")
                }
                .tag(1)

            LoansListView()
                .tabItem {
                    Label("Loans", systemImage: "creditcard.fill")
                }
                .tag(2)

            PaymentsView()
                .tabItem {
                    Label("Payments", systemImage: "dollarsign.circle.fill")
                }
                .tag(3)

            ReportsView()
                .tabItem {
                    Label("Reports", systemImage: "doc.text.fill")
                }
                .tag(4)
        }
        #endif
    }
}

#if os(macOS)
struct SidebarView: View {
    @Binding var selectedTab: Int

    var body: some View {
        List(selection: $selectedTab) {
            NavigationLink(value: 0) {
                Label("Overview", systemImage: "chart.line.uptrend.xyaxis")
            }
            .accessibilityLabel("Overview")

            NavigationLink(value: 1) {
                Label("Members", systemImage: "person.3.fill")
            }
            .accessibilityLabel("Members")

            NavigationLink(value: 2) {
                Label("Loans", systemImage: "creditcard.fill")
            }
            .accessibilityLabel("Loans")

            NavigationLink(value: 3) {
                Label("Payments", systemImage: "dollarsign.circle.fill")
            }
            .accessibilityLabel("Payments")

            NavigationLink(value: 4) {
                Label("Reports", systemImage: "doc.text.fill")
            }
            .accessibilityLabel("Reports")
        }
        .navigationTitle("Solidarity Fund")
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation sidebar")
    }
}

struct DetailView: View {
    let selectedTab: Int
    @AppStorage("useLiquidGlass") private var useLiquidGlass: Bool = true

    var body: some View {
        switch selectedTab {
        case 0:
            if useLiquidGlass {
                LiquidGlassDashboard()
            } else {
                OverviewView()
            }
        case 1:
            MembersListView()
        case 2:
            LoansListView()
        case 3:
            PaymentsView()
        case 4:
            ReportsView()
        default:
            if useLiquidGlass {
                LiquidGlassDashboard()
            } else {
                OverviewView()
            }
        }
    }
}
#endif

struct OverviewView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var refreshID = UUID()
    @State private var isRecalculating = false

    var body: some View {
        ScrollView {
            GlassContainerCompat {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Solidarity Fund Overview")
                            .font(.largeTitle)
                        Spacer()
                        Button {
                            isRecalculating = true
                            dataManager.recalculateAllMemberContributions()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                isRecalculating = false
                                refreshID = UUID()
                            }
                        } label: {
                            if isRecalculating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Recalculate", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(TahoeGlassButtonStyle())
                        .disabled(isRecalculating)
                        .accessibleControl(label: "Recalculate fund balances")
                    }
                    .padding(.bottom)

                    HStack(spacing: 20) {
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

                    Text("Recent Transactions")
                        .font(.headline)
                        .padding(.top)

                    if dataManager.recentTransactions.isEmpty {
                        ContentUnavailableView(
                            "No Transactions",
                            systemImage: "doc.text",
                            description: Text("Transactions will appear here once members make payments or take loans.")
                        )
                        .frame(height: 200)
                    } else {
                        ForEach(dataManager.recentTransactions.prefix(10)) { transaction in
                            TransactionRowView(transaction: transaction)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Overview")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fund overview")
        .onReceive(NotificationCenter.default.publisher(for: .transactionsUpdated)) { _ in
            refreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .paymentSaved)) { _ in
            refreshID = UUID()
        }
        .id(refreshID)
    }

    func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "KES"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "KSH 0"
    }

    func utilizationColor(_ utilization: Double) -> Color {
        if utilization >= 0.6 {
            return .red
        } else if utilization >= 0.4 {
            return .orange
        } else {
            return .green
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(color)
                    .font(.title2)
                    .accessibilityHidden(true)
                Spacer()
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(minHeight: 100)
        .tertiaryGlass(cornerRadius: DesignSystem.cornerRadiusMedium)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(DesignSystem.gentleSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibleCard(label: title, value: value)
    }
}

struct TransactionRowView: View {
    let transaction: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(transaction.member?.name ?? "Fund Transaction")
                    .font(.headline)
                Text(transaction.transactionType.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(transaction.displayAmount)
                    .font(.headline)
                    .foregroundColor(transaction.transactionType.isCredit ? .green : .red)
                Text(transaction.transactionDate ?? Date(), style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
