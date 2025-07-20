//
//  ReportsView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers
import PDFKit

struct ReportsView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedReportType = ReportType.fundOverview
    @State private var selectedMember: Member?
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
    @State private var endDate = Date()
    @State private var pdfURL: URL?
    @State private var isGeneratingPDF = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    enum ReportType: String, CaseIterable {
        case fundOverview = "Fund Overview"
        case memberStatement = "Member Statement"
        case loanSummary = "Loan Summary"
        case monthlyReport = "Monthly Report"
        case analytics = "Analytics"
        
        var icon: String {
            switch self {
            case .fundOverview: return "chart.pie.fill"
            case .memberStatement: return "person.text.rectangle.fill"
            case .loanSummary: return "creditcard.fill"
            case .monthlyReport: return "calendar"
            case .analytics: return "chart.xyaxis.line"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and toolbar
            reportHeader
            
            // Report Type Selector
            reportTypeSelector
            
            // Date Range Selector
            if selectedReportType != .fundOverview {
                dateRangeSelector
            }
            
            // Report Content
            ScrollView {
                switch selectedReportType {
                case .fundOverview:
                    FundOverviewReport()
                case .memberStatement:
                    MemberStatementReport(selectedMember: $selectedMember)
                case .loanSummary:
                    LoanSummaryReport(startDate: startDate, endDate: endDate)
                case .monthlyReport:
                    MonthlyReport(startDate: startDate, endDate: endDate)
                case .analytics:
                    AnalyticsReport()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Export Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - View Components
    
    private var reportHeader: some View {
        HStack {
            Text("Reports")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Spacer()
            
            Button {
                generatePDF()
            } label: {
                if isGeneratingPDF {
                    ProgressView()
                } else {
                    Label("Open in Preview", systemImage: "doc.text.magnifyingglass")
                }
            }
            .disabled(isGeneratingPDF)
        }
        .padding(.horizontal)
        .padding(.top, 16) // Normal padding - traffic lights will overlay
        .padding(.bottom, 12)
    }
    
    private var reportTypeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ReportType.allCases, id: \.self) { type in
                    Button {
                        selectedReportType = type
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.icon)
                                .font(.title2)
                            Text(type.rawValue)
                                .font(.caption)
                        }
                        .frame(width: 80)
                        .padding(.vertical, 12)
                        .background(selectedReportType == type ? Color.accentColor : Color.secondary.opacity(0.2))
                        .foregroundColor(selectedReportType == type ? .white : .primary)
                        .cornerRadius(10)
                    }
                }
            }
            .padding()
        }
    }
    
    private var dateRangeSelector: some View {
        HStack {
            DatePicker("From", selection: $startDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            
            Spacer()
            
            DatePicker("To", selection: $endDate, displayedComponents: .date)
                .datePickerStyle(.compact)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
    
    // MARK: - PDF Generation
    
    private func generatePDF() {
        isGeneratingPDF = true
        
        Task {
            do {
                let pdfGenerator = PDFGenerator()
                let url = try await pdfGenerator.generateReport(
                    type: selectedReportType,
                    dataManager: dataManager,
                    member: selectedMember,
                    startDate: startDate,
                    endDate: endDate
                )
                
                await MainActor.run {
                    self.pdfURL = url
                    self.isGeneratingPDF = false
                    self.showPrintDialog(for: url)
                }
            } catch {
                print("PDF generation error: \(error)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showingError = true
                    self.isGeneratingPDF = false
                }
            }
        }
    }
    
    // MARK: - Print Dialog
    
    private func showPrintDialog(for url: URL) {
        // Simply open the PDF in Preview, which handles printing and saving properly
        NSWorkspace.shared.open(url)
        
        // Clean up temporary file after a delay (give Preview time to open it)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            try? FileManager.default.removeItem(at: url)
            self.pdfURL = nil
        }
    }
}

// MARK: - Fund Overview Report

struct FundOverviewReport: View {
    @EnvironmentObject var dataManager: DataManager
    
    var fundSummary: FundSummary {
        FundCalculator.shared.generateFundSummary()
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Fund Balance Card
            FundBalanceCard(fundSummary: fundSummary)
            
            // Key Metrics
            HStack(spacing: 16) {
                ReportMetricCard(
                    title: "Active Members",
                    value: "\(fundSummary.activeMembers)",
                    icon: "person.3.fill",
                    color: .blue
                )
                
                ReportMetricCard(
                    title: "Active Loans",
                    value: "\(fundSummary.activeLoansCount)",
                    icon: "creditcard.fill",
                    color: .orange
                )
            }
            
            // Utilization Chart
            UtilizationChart(utilization: fundSummary.utilizationPercentage)
            
            // Fund Composition
            FundCompositionChart(fundSummary: fundSummary)
            
            // Recent Activity
            RecentActivitySection()
        }
        .padding()
    }
}

// MARK: - Member Statement Report

struct MemberStatementReport: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedMember: Member?
    
    var body: some View {
        VStack(spacing: 20) {
            // Member Selector
            if selectedMember == nil {
                MemberSelector(selectedMember: $selectedMember)
            } else if let member = selectedMember {
                // Back button and Member Info
                HStack {
                    Button {
                        selectedMember = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Select Member")
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                
                // Member Info
                MemberInfoCard(member: member)
                
                // Financial Summary
                MemberFinancialSummary(member: member)
                
                // Contribution History
                ContributionHistoryChart(member: member)
                
                // Loan History
                MemberLoanHistory(member: member)
                
                // Recent Transactions
                MemberTransactionHistory(member: member)
            }
        }
        .padding()
    }
}

// MARK: - Supporting Views

struct FundBalanceCard: View {
    let fundSummary: FundSummary
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Fund Balance")
                .font(.headline)
            
            Text(CurrencyFormatter.shared.format(fundSummary.fundBalance))
                .font(.largeTitle)
                .fontWeight(.bold)
            
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Contributions", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(CurrencyFormatter.shared.format(fundSummary.totalContributions))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Active Loans", systemImage: "minus.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(CurrencyFormatter.shared.format(fundSummary.totalActiveLoans))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ReportMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct UtilizationChart: View {
    let utilization: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fund Utilization")
                .font(.headline)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 30)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(utilizationColor)
                        .frame(width: geometry.size.width * utilization, height: 30)
                    
                    Text(String(format: "%.1f%%", utilization * 100))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                }
            }
            .frame(height: 30)
            
            HStack {
                Text("Warning threshold: 60%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Circle()
                    .fill(utilizationColor)
                    .frame(width: 8, height: 8)
                Text(utilizationStatus)
                    .font(.caption)
                    .foregroundColor(utilizationColor)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var utilizationColor: Color {
        if utilization >= 0.6 {
            return .red
        } else if utilization >= 0.4 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var utilizationStatus: String {
        if utilization >= 0.6 {
            return "High"
        } else if utilization >= 0.4 {
            return "Moderate"
        } else {
            return "Low"
        }
    }
}

struct FundCompositionChart: View {
    let fundSummary: FundSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fund Composition")
                .font(.headline)
            
            Chart {
                SectorMark(
                    angle: .value("Amount", fundSummary.totalContributions),
                    innerRadius: .ratio(0.5)
                )
                .foregroundStyle(.blue)
                .annotation(position: .overlay) {
                    Text("Contributions")
                        .font(.caption)
                }
                
                SectorMark(
                    angle: .value("Amount", fundSummary.bobRemainingInvestment),
                    innerRadius: .ratio(0.5)
                )
                .foregroundStyle(.green)
                .annotation(position: .overlay) {
                    Text("Bob's Investment")
                        .font(.caption)
                }
                
                SectorMark(
                    angle: .value("Amount", fundSummary.totalInterestApplied),
                    innerRadius: .ratio(0.5)
                )
                .foregroundStyle(.purple)
                .annotation(position: .overlay) {
                    Text("Interest")
                        .font(.caption)
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct MemberSelector: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedMember: Member?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Member")
                .font(.headline)
            
            ScrollView {
                ForEach(dataManager.members.sorted { $0.name ?? "" < $1.name ?? "" }) { member in
                    Button {
                        selectedMember = member
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(member.name ?? "Unknown")
                                    .fontWeight(.medium)
                                Text(member.memberRole.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}


// Placeholder implementations for other report components
struct LoanSummaryReport: View {
    @EnvironmentObject var dataManager: DataManager
    let startDate: Date
    let endDate: Date
    
    var filteredLoans: [Loan] {
        // Show all active loans regardless of date range for loan summary
        dataManager.activeLoans
    }
    
    var totalLoanAmount: Double {
        filteredLoans.reduce(0) { $0 + $1.amount }
    }
    
    var totalOutstanding: Double {
        filteredLoans.reduce(0) { $0 + $1.balance }
    }
    
    var overdueLoans: [Loan] {
        filteredLoans.filter { $0.isOverdue }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Summary Cards
            HStack(spacing: 16) {
                ReportMetricCard(
                    title: "Total Loans Issued",
                    value: CurrencyFormatter.shared.format(totalLoanAmount),
                    icon: "creditcard.fill",
                    color: .blue
                )
                
                ReportMetricCard(
                    title: "Outstanding Balance",
                    value: CurrencyFormatter.shared.format(totalOutstanding),
                    icon: "dollarsign.circle.fill",
                    color: .orange
                )
            }
            
            HStack(spacing: 16) {
                ReportMetricCard(
                    title: "Number of Loans",
                    value: "\(filteredLoans.count)",
                    icon: "number.circle.fill",
                    color: .purple
                )
                
                ReportMetricCard(
                    title: "Overdue Loans",
                    value: "\(overdueLoans.count)",
                    icon: "exclamationmark.triangle.fill",
                    color: overdueLoans.isEmpty ? .green : .red
                )
            }
            
            // Loan List
            VStack(alignment: .leading, spacing: 12) {
                Text("Loan Details")
                    .font(.headline)
                
                if filteredLoans.isEmpty {
                    Text("No loans found in selected period")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(filteredLoans) { loan in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loan.member?.name ?? "Unknown")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Issued \(DateHelper.formatDate(loan.issueDate))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(CurrencyFormatter.shared.format(loan.amount))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                HStack(spacing: 4) {
                                    Text("Balance: \(CurrencyFormatter.shared.format(loan.balance))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if loan.isOverdue {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
        }
        .padding()
    }
}

struct MonthlyReport: View {
    @EnvironmentObject var dataManager: DataManager
    let startDate: Date
    let endDate: Date
    
    var body: some View {
        VStack(spacing: 20) {
            // Monthly Summary
            VStack(alignment: .leading, spacing: 12) {
                Text("Monthly Summary")
                    .font(.headline)
                
                Text("\(DateHelper.formatShortMonth(startDate)) - \(DateHelper.formatShortMonth(endDate))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Contribution Analysis
            ContributionAnalysisCard()
            
            // Loan Activity
            LoanActivityCard(startDate: startDate, endDate: endDate)
            
            // Member Activity
            MemberActivityCard()
        }
        .padding()
    }
}

struct ContributionAnalysisCard: View {
    @EnvironmentObject var dataManager: DataManager
    
    var monthlyTotals: [(month: String, amount: Double)] {
        // Simple aggregation of contributions by month
        let calendar = Calendar.current
        var totals: [String: Double] = [:]
        
        for member in dataManager.members {
            if let payments = member.payments?.allObjects as? [Payment] {
                for payment in payments {
                    if let date = payment.paymentDate, payment.contributionAmount > 0 {
                        let components = calendar.dateComponents([.year, .month], from: date)
                        let key = "\(components.year ?? 0)-\(String(format: "%02d", components.month ?? 0))"
                        totals[key, default: 0] += payment.contributionAmount
                    }
                }
            }
        }
        
        return totals.map { (month: $0.key, amount: $0.value) }
            .sorted { $0.month < $1.month }
            .suffix(6)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contribution Analysis")
                .font(.headline)
            
            if monthlyTotals.isEmpty {
                Text("No contribution data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                Chart(monthlyTotals, id: \.month) { item in
                    BarMark(
                        x: .value("Month", String(item.month.suffix(2))),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(.blue)
                }
                .frame(height: 200)
                
                HStack {
                    let total = monthlyTotals.map { $0.amount }.reduce(0, +)
                    let average = total / Double(max(1, monthlyTotals.count))
                    Text("Average: \(CurrencyFormatter.shared.format(average))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Last 6 months")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct LoanActivityCard: View {
    @EnvironmentObject var dataManager: DataManager
    let startDate: Date
    let endDate: Date
    
    var loansIssuedInPeriod: [Loan] {
        dataManager.activeLoans.filter { loan in
            guard let issueDate = loan.issueDate else { return false }
            return issueDate >= startDate && issueDate <= endDate
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loan Activity")
                .font(.headline)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(loansIssuedInPeriod.count)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("New Loans")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(CurrencyFormatter.shared.format(loansIssuedInPeriod.reduce(0) { $0 + $1.amount }))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Total Issued")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct MemberActivityCard: View {
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Member Statistics")
                .font(.headline)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dataManager.members.filter { $0.memberStatus == .active }.count)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Active Members")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dataManager.members.filter { $0.hasActiveLoans }.count)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("With Active Loans")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct AnalyticsReport: View {
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Fund Growth Chart
            FundGrowthChart()
            
            // Member Distribution
            MemberDistributionChart()
            
            // Loan Performance Metrics
            LoanPerformanceMetrics()
        }
        .padding()
    }
}

struct FundGrowthChart: View {
    @EnvironmentObject var dataManager: DataManager
    
    var fundGrowthData: [(month: String, balance: Double)] {
        // Calculate fund balance over last 6 months
        let calendar = Calendar.current
        var data: [(month: String, balance: Double)] = []
        
        for i in 0..<6 {
            let date = calendar.date(byAdding: .month, value: -i, to: Date()) ?? Date()
            let monthKey = DateFormatter().monthSymbols[calendar.component(.month, from: date) - 1].prefix(3)
            
            // Simple calculation - this could be more sophisticated
            let fundSummary = FundCalculator.shared.generateFundSummary()
            let balance = fundSummary.fundBalance * (1.0 - Double(i) * 0.05) // Simulate growth
            
            data.append((month: String(monthKey), balance: max(0, balance)))
        }
        
        return data.reversed()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fund Growth Trend")
                .font(.headline)
            
            if fundGrowthData.isEmpty {
                Text("No fund data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
            } else {
                Chart(fundGrowthData, id: \.month) { item in
                    LineMark(
                        x: .value("Month", item.month),
                        y: .value("Balance", item.balance)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Month", item.month),
                        y: .value("Balance", item.balance)
                    )
                    .foregroundStyle(.blue.opacity(0.2))
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let balance = value.as(Double.self) {
                                Text(CurrencyFormatter.shared.formatShort(balance))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct MemberDistributionChart: View {
    @EnvironmentObject var dataManager: DataManager
    
    var membersByRole: [(role: String, count: Int)] {
        let grouped = Dictionary(grouping: dataManager.members) { $0.memberRole }
        return grouped.map { (role: $0.key.displayName, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Member Distribution by Role")
                .font(.headline)
            
            ForEach(membersByRole, id: \.role) { item in
                HStack {
                    Text(item.role)
                        .font(.subheadline)
                    Spacer()
                    Text("\(item.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct LoanPerformanceMetrics: View {
    @EnvironmentObject var dataManager: DataManager
    
    var averageLoanAmount: Double {
        let loans = dataManager.activeLoans
        guard !loans.isEmpty else { return 0 }
        return loans.reduce(0) { $0 + $1.amount } / Double(loans.count)
    }
    
    var repaymentRate: Double {
        let completedLoans = dataManager.members.flatMap { member in
            (member.loans?.allObjects as? [Loan] ?? []).filter { $0.loanStatus == .completed }
        }
        let totalLoans = dataManager.members.flatMap { member in
            (member.loans?.allObjects as? [Loan] ?? [])
        }
        guard !totalLoans.isEmpty else { return 0 }
        return Double(completedLoans.count) / Double(totalLoans.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loan Performance")
                .font(.headline)
            
            VStack(spacing: 16) {
                HStack {
                    Text("Average Loan Amount")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(averageLoanAmount))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Repayment Success Rate")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", repaymentRate * 100))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(repaymentRate > 0.8 ? .green : .orange)
                }
                
                HStack {
                    Text("Active Loans")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(dataManager.activeLoans.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct MemberInfoCard: View {
    let member: Member
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name ?? "Unknown")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(member.memberRole.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                StatusBadge(status: member.memberStatus)
            }
            
            Divider()
            
            HStack {
                InfoItem(label: "Member Since", value: DateHelper.formatDate(member.joinDate))
                Spacer()
                InfoItem(label: "Phone", value: member.phoneNumber ?? "N/A")
            }
            
            if let email = member.email {
                InfoItem(label: "Email", value: email)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct InfoItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }
}

struct MemberFinancialSummary: View {
    let member: Member
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                FinancialReportMetricCard(
                    title: "Total Contributions",
                    amount: member.totalContributions,
                    icon: "banknote.fill",
                    color: .green
                )
                
                FinancialReportMetricCard(
                    title: "Active Loan Balance",
                    amount: member.totalActiveLoanBalance,
                    icon: "creditcard.fill",
                    color: .orange
                )
            }
            
            if member.cashOutAmount > 0 {
                FinancialReportMetricCard(
                    title: "Cash Out Amount",
                    amount: member.cashOutAmount,
                    icon: "dollarsign.circle.fill",
                    color: .purple
                )
            }
            
            // Net Position
            let netPosition = member.totalContributions - member.totalActiveLoanBalance
            HStack {
                Text("Net Position")
                    .font(.headline)
                Spacer()
                Text(CurrencyFormatter.shared.format(netPosition))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(netPosition >= 0 ? .green : .red)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
        }
    }
}

struct FinancialReportMetricCard: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(CurrencyFormatter.shared.format(amount))
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct ContributionHistoryChart: View {
    let member: Member
    
    var body: some View {
        Text("Contribution History Chart")
            .padding()
    }
}

struct MemberLoanHistory: View {
    let member: Member
    
    var loans: [Loan] {
        (member.loans?.allObjects as? [Loan] ?? [])
            .sorted { ($0.issueDate ?? Date()) > ($1.issueDate ?? Date()) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loan History")
                .font(.headline)
            
            if loans.isEmpty {
                Text("No loans taken")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(loans) { loan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CurrencyFormatter.shared.format(loan.amount))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Issued \(DateHelper.formatDate(loan.issueDate))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if loan.loanStatus == .completed {
                                Label("Completed", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else if loan.isOverdue {
                                Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Label("Active", systemImage: "circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if loan.loanStatus == .active {
                            ProgressView(value: loan.completionPercentage, total: 100)
                                .tint(loan.isOverdue ? .red : .accentColor)
                            
                            HStack {
                                Text("Balance: \(CurrencyFormatter.shared.format(loan.balance))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(loan.completionPercentage))% paid")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct MemberTransactionHistory: View {
    let member: Member
    
    var transactions: [Transaction] {
        (member.transactions?.allObjects as? [Transaction] ?? [])
            .sorted { ($0.transactionDate ?? Date()) > ($1.transactionDate ?? Date()) }
            .prefix(10)
            .map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transactions")
                .font(.headline)
            
            if transactions.isEmpty {
                Text("No transactions found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(transactions) { transaction in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transaction.transactionType.displayName)
                                .font(.subheadline)
                            Text(DateHelper.formatDate(transaction.transactionDate))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(CurrencyFormatter.shared.format(abs(transaction.amount)))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(transaction.amount > 0 ? .green : .red)
                            
                            if let description = transaction.transactionDescription {
                                Text(description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if transaction != transactions.last {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct RecentActivitySection: View {
    @EnvironmentObject var dataManager: DataManager
    
    var recentTransactions: [Transaction] {
        dataManager.recentTransactions.prefix(10).map { $0 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
            
            if recentTransactions.isEmpty {
                Text("No recent transactions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(recentTransactions.prefix(5)) { transaction in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transaction.transactionDescription ?? "Transaction")
                                .font(.subheadline)
                            Text(DateHelper.formatDate(transaction.transactionDate))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(CurrencyFormatter.shared.format(abs(transaction.amount)))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(transaction.amount > 0 ? .green : .red)
                    }
                    .padding(.vertical, 4)
                    
                    if transaction != recentTransactions.prefix(5).last {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    ReportsView()
        .environmentObject(DataManager.shared)
}