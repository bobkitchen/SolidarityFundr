//
//  DashboardView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedTab = 0
    @AppStorage("useLiquidGlass") private var useLiquidGlass: Bool = true
    
    var body: some View {
        #if os(macOS)
        if useLiquidGlass {
            // Liquid Glass Design - Proper floating sidebar implementation
            HStack(spacing: 0) {
                // Sidebar - fixed width with padding for floating effect
                FloatingSidebar(selectedSection: $selectedTab)
                    .frame(width: DesignSystem.sidebarExpandedWidth)
                    .padding(.leading, DesignSystem.sidebarPadding)
                    .padding(.trailing, DesignSystem.sidebarPadding / 2) // Half padding on right
                    .padding(.vertical, DesignSystem.sidebarPadding)
                
                // Main content fills remaining space
                DetailView(selectedTab: selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 800, minHeight: 640)
            .liquidGlassWindowBackground()
        } else {
            // Original Design
            NavigationSplitView {
                SidebarView(selectedTab: $selectedTab)
            } detail: {
                DetailView(selectedTab: selectedTab)
            }
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
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
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
            
            NavigationLink(value: 1) {
                Label("Members", systemImage: "person.3.fill")
            }
            
            NavigationLink(value: 2) {
                Label("Loans", systemImage: "creditcard.fill")
            }
            
            NavigationLink(value: 3) {
                Label("Payments", systemImage: "dollarsign.circle.fill")
            }
            
            NavigationLink(value: 4) {
                Label("Reports", systemImage: "doc.text.fill")
            }
            
            NavigationLink(value: 5) {
                Label("Settings", systemImage: "gear")
            }
        }
        .navigationTitle("Solidarity Fund")
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
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
        case 5:
            let _ = print("🔧 DashboardView: Loading SettingsView for case 5")
            SettingsView()
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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Solidarity Fund Overview")
                    .font(.largeTitle)
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
        .navigationTitle("Overview")
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(color)
                    .font(.title2)
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
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
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
    }
}

// Placeholder views removed - implementations in separate files

#Preview {
    DashboardView()
        .environmentObject(DataManager.shared)
}