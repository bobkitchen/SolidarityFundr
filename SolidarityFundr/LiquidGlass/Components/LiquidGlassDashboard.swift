//
//  LiquidGlassDashboard.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Liquid Glass Dashboard Implementation
//

import SwiftUI
import Charts

// MARK: - Liquid Glass Dashboard
struct LiquidGlassDashboard: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedMetric: MetricType? = nil
    @State private var animateCards = false
    
    enum MetricType: String, CaseIterable {
        case balance = "Fund Balance"
        case members = "Active Members"
        case loans = "Active Loans"
        case utilization = "Utilization"
        
        var icon: String {
            switch self {
            case .balance: return "banknote.fill"
            case .members: return "person.3.fill"
            case .loans: return "creditcard.fill"
            case .utilization: return "percent"
            }
        }
        
        var color: Color {
            switch self {
            case .balance: return .green
            case .members: return .blue
            case .loans: return .orange
            case .utilization: return .purple
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.spacingXLarge) {
                // Header
                DashboardHeader()
                    .padding(.horizontal, DesignSystem.marginStandard)
                
                // Metrics Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: DesignSystem.spacingMedium) {
                    ForEach(MetricType.allCases, id: \.self) { metric in
                        LiquidGlassMetricCard(
                            type: metric,
                            value: metricValue(for: metric),
                            trend: metricTrend(for: metric),
                            isSelected: selectedMetric == metric
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedMetric = selectedMetric == metric ? nil : metric
                            }
                        }
                        .scaleEffect(animateCards ? 1 : 0.9)
                        .opacity(animateCards ? 1 : 0)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7)
                            .delay(Double(metric.hashValue % 4) * 0.1),
                            value: animateCards
                        )
                    }
                }
                .padding(.horizontal, DesignSystem.marginStandard)
                
                // Activity Chart
                ActivityChartCard()
                    .padding(.horizontal, DesignSystem.marginStandard)
                
                // Recent Transactions
                RecentTransactionsCard()
                    .padding(.horizontal, DesignSystem.marginStandard)
                
                // Quick Actions
                QuickActionsCard()
                    .padding(.horizontal, DesignSystem.marginStandard)
                    .padding(.bottom, DesignSystem.marginStandard)
            }
            .padding(.top, DesignSystem.marginStandard) // Normal top padding - traffic lights will overlay
        }
        .background(Color.primaryBackground)
        .onAppear {
            animateCards = true
        }
    }
    
    private func metricValue(for type: MetricType) -> String {
        switch type {
        case .balance:
            return CurrencyFormatter.shared.format(dataManager.fundSettings?.calculateFundBalance() ?? 0)
        case .members:
            return "\(dataManager.members.filter { $0.memberStatus == .active }.count)"
        case .loans:
            return "\(dataManager.activeLoans.count)"
        case .utilization:
            return String(format: "%.1f%%", (dataManager.fundSettings?.calculateUtilizationPercentage() ?? 0) * 100)
        }
    }
    
    private func metricTrend(for type: MetricType) -> Double {
        // Simulate trend data
        switch type {
        case .balance: return 5.2
        case .members: return 0.0
        case .loans: return -2.3
        case .utilization: return 3.1
        }
    }
}

// MARK: - Dashboard Header
struct DashboardHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingXSmall) {
            Text("Welcome back")
                .font(DesignSystem.Typography.subtitle)
                .foregroundColor(.secondaryText)
            
            Text("Solidarity Fund Overview")
                .font(DesignSystem.Typography.pageTitle)
                .foregroundColor(.primaryText)
            
            Text(Date().formatted(date: .complete, time: .omitted))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Metric Card
struct LiquidGlassMetricCard: View {
    let type: LiquidGlassDashboard.MetricType
    let value: String
    let trend: Double
    let isSelected: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            HStack {
                Image(systemName: type.icon)
                    .foregroundColor(type.color)
                    .font(.system(size: 20, weight: .medium))
                Text(type.rawValue)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(.secondaryText)
                Spacer()
            }
            
            Text(value)
                .font(DesignSystem.Typography.pageTitle)
                .foregroundColor(.primaryText)
                .multilineTextAlignment(.leading)
        }
        .padding(DesignSystem.spacingMedium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .performantGlass(
            material: .regularMaterial,
            cornerRadius: DesignSystem.cornerRadiusLarge,
            strokeOpacity: 0.1
        )
        .adaptiveShadow(
            isHovered: isHovered,
            isSelected: isSelected,
            baseRadius: 8,
            baseOpacity: 0.1
        )
        .hoverOverlay(
            isHovered: isHovered,
            cornerRadius: DesignSystem.cornerRadiusLarge,
            intensity: 0.05
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(DesignSystem.gentleSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Trend Indicator
struct TrendIndicator: View {
    let value: Double
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: value > 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
            
            Text(String(format: "%.1f%%", abs(value)))
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(value > 0 ? .green : .red)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((value > 0 ? Color.green : Color.red).opacity(0.1))
        )
    }
}

// MARK: - Mini Chart
struct MiniChart: View {
    let color: Color
    
    var body: some View {
        Canvas { context, size in
            let path = Path { path in
                let points = generateRandomPoints(in: size)
                path.move(to: points[0])
                
                for i in 1..<points.count {
                    path.addLine(to: points[i])
                }
            }
            
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.6), color]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                lineWidth: 2
            )
        }
    }
    
    private func generateRandomPoints(in size: CGSize) -> [CGPoint] {
        let count = 10
        return (0..<count).map { i in
            let x = size.width * CGFloat(i) / CGFloat(count - 1)
            let y = size.height * (0.2 + CGFloat.random(in: 0...0.6))
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Activity Chart Card
struct ActivityChartCard: View {
    @State private var selectedPeriod = "Week"
    let periods = ["Day", "Week", "Month", "Year"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Fund Activity")
                    .font(.system(size: 20, weight: .semibold))
                
                Spacer()
                
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(periods, id: \.self) { period in
                        Text(period).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            // Chart placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(height: 200)
                .overlay(
                    Text("Activity Chart")
                        .foregroundColor(.secondary)
                )
        }
        .padding(DesignSystem.marginStandard)
        .performantGlass(
            material: .regularMaterial,
            cornerRadius: DesignSystem.cornerRadiusLarge,
            strokeOpacity: 0.1
        )
    }
}

// MARK: - Recent Transactions Card
struct RecentTransactionsCard: View {
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Transactions")
                    .font(.system(size: 20, weight: .semibold))
                
                Spacer()
                
                Button("View All") {
                    // Action
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            
            if dataManager.recentTransactions.isEmpty {
                EmptyTransactionsView()
            } else {
                VStack(spacing: 12) {
                    ForEach(dataManager.recentTransactions.prefix(5)) { transaction in
                        LiquidGlassTransactionRow(transaction: transaction)
                    }
                }
            }
        }
        .padding(DesignSystem.marginStandard)
        .performantGlass(
            material: .regularMaterial,
            cornerRadius: DesignSystem.cornerRadiusLarge,
            strokeOpacity: 0.1
        )
    }
}

// MARK: - Empty Transactions View
struct EmptyTransactionsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No transactions yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Transactions will appear here once members make payments or take loans")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Transaction Row
struct LiquidGlassTransactionRow: View {
    let transaction: Transaction
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            // Icon
            Circle()
                .fill(transaction.transactionType.isCredit ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: transaction.transactionType.isCredit ? "arrow.down" : "arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(transaction.transactionType.isCredit ? .green : .red)
                )
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.member?.name ?? "Fund Transaction")
                    .font(.system(size: 14, weight: .medium))
                
                Text(transaction.transactionType.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Amount and Date
            VStack(alignment: .trailing, spacing: 4) {
                Text(transaction.displayAmount)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(transaction.transactionType.isCredit ? .green : .red)
                
                Text(transaction.transactionDate ?? Date(), style: .date)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Quick Actions Card
struct QuickActionsCard: View {
    let actions = [
        QuickAction(title: "Add Member", icon: "person.badge.plus", color: .blue),
        QuickAction(title: "New Loan", icon: "plus.circle.fill", color: .orange),
        QuickAction(title: "Record Payment", icon: "checkmark.circle.fill", color: .green),
        QuickAction(title: "Generate Report", icon: "doc.text.fill", color: .purple)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.system(size: 20, weight: .semibold))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(actions) { action in
                    LiquidGlassQuickActionButton(action: action)
                }
            }
        }
        .padding(DesignSystem.marginStandard)
        .performantGlass(
            material: .regularMaterial,
            cornerRadius: DesignSystem.cornerRadiusLarge,
            strokeOpacity: 0.1
        )
    }
}

// MARK: - Quick Action Model
struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
}

// MARK: - Quick Action Button
struct LiquidGlassQuickActionButton: View {
    let action: QuickAction
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {}) {
            HStack(spacing: DesignSystem.spacingXSmall) {
                Image(systemName: action.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Text(action.title)
                    .font(DesignSystem.Typography.buttonText)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, DesignSystem.spacingMedium)
            .padding(.vertical, DesignSystem.spacingSmall)
            .background(action.color)
            .cornerRadius(DesignSystem.cornerRadiusSmall)
        }
        .buttonStyle(LiquidGlassButtonStyle(cornerRadius: DesignSystem.cornerRadiusSmall))
        .adaptiveShadow(
            isHovered: isHovered,
            baseRadius: 4,
            baseOpacity: 0.08
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview
#Preview {
    LiquidGlassDashboard()
        .environmentObject(DataManager.shared)
        .frame(width: 1200, height: 800)
}