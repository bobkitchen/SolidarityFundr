//
//  ReportsView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//  macOS 26 Tahoe HIG Compliant
//

import SwiftUI
import Charts
import UniformTypeIdentifiers
import PDFKit

#if !os(macOS)
// Reports rely on the AppKit-only PDF drawing pipeline. iPhone shows
// a clean placeholder rather than carrying a parallel UIKit stack.
struct ReportsView: View {
    var body: some View {
        ContentUnavailableView(
            "Reports are available on Mac",
            systemImage: "doc.text",
            description: Text("Open the fund on your Mac to generate and share PDF reports.")
        )
    }
}
#else

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
    @State private var hasRecalculated = false
    
    enum ReportType: String, CaseIterable {
        case fundOverview = "Fund Overview"
        case memberStatement = "Member Statement"
        case loanSummary = "Loan Summary"
        case monthlyReport = "Monthly Report"
        case analytics = "Analytics"
        case fundSummary = "Fund Summary Report"
        
        var icon: String {
            switch self {
            case .fundOverview: return "chart.pie.fill"
            case .memberStatement: return "person.text.rectangle.fill"
            case .loanSummary: return "creditcard.fill"
            case .monthlyReport: return "calendar"
            case .analytics: return "chart.xyaxis.line"
            case .fundSummary: return "doc.text.image.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 0) {
                    reportHeader
                    reportTypeSelector

                    if selectedReportType != .fundOverview {
                        dateRangeSelector
                    }

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
                        case .fundSummary:
                            FundSummaryReport()
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Reports view")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        generatePDF()
                    } label: {
                        if isGeneratingPDF {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Open in Preview", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    .disabled(isGeneratingPDF)
                }
            }
            .alert("Export Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                if !hasRecalculated {
                    dataManager.recalculateAllMemberContributions()
                    hasRecalculated = true
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var reportHeader: some View {
        EmptyView()
    }

    private var reportTypeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReportType.allCases, id: \.self) { type in
                    ReportTypeButton(
                        reportType: type,
                        isSelected: selectedReportType == type,
                        action: { selectedReportType = type }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
    
    private var dateRangeSelector: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.body)
                    .foregroundStyle(.secondary)
                
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                
                Text("–")
                    .foregroundStyle(.secondary)
                
                DatePicker("To", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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
    
    @State private var pdfURL: URL?
    @State private var isGeneratingPDF = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var statementPeriodStart = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var statementPeriodEnd = Date()
    
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
                        pdfURL = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Select Member")
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                
                // Member Info
                MemberInfoCard(member: member)

                // Statement Actions
                MemberStatementActions(
                    member: member,
                    pdfURL: $pdfURL,
                    isGeneratingPDF: $isGeneratingPDF,
                    statementPeriodStart: $statementPeriodStart,
                    statementPeriodEnd: $statementPeriodEnd
                )
                
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
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Supporting Views

struct MemberStatementActions: View {
    let member: Member
    @Binding var pdfURL: URL?
    @Binding var isGeneratingPDF: Bool
    @Binding var statementPeriodStart: Date
    @Binding var statementPeriodEnd: Date
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Statement Actions", systemImage: "doc.text.fill")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    DatePicker("From", selection: $statementPeriodStart, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()

                    Text("–")
                        .foregroundStyle(.secondary)

                    DatePicker("To", selection: $statementPeriodEnd, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button {
                generateAndPreviewPDF()
            } label: {
                HStack {
                    if isGeneratingPDF {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    Text("Generate & Preview")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPDF)
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func generateAndPreviewPDF() {
        isGeneratingPDF = true

        Task {
            do {
                let pdfGenerator = PDFGenerator()
                let url = try await pdfGenerator.generateReport(
                    type: .memberStatement,
                    dataManager: dataManager,
                    member: member,
                    startDate: statementPeriodStart,
                    endDate: statementPeriodEnd
                )

                await MainActor.run {
                    self.pdfURL = url
                    self.isGeneratingPDF = false
                    NSWorkspace.shared.open(url)
                }
            } catch {
                print("PDF generation error: \(error)")
                await MainActor.run {
                    self.isGeneratingPDF = false
                }
            }
        }
    }
}

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
                        .foregroundStyle(.green)
                    Text(CurrencyFormatter.shared.format(fundSummary.totalContributions))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Active Loans", systemImage: "minus.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(CurrencyFormatter.shared.format(fundSummary.totalActiveLoans))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 30)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(utilizationColor)
                        .frame(width: geometry.size.width * utilization, height: 30)
                    
                    Text(String(format: "%.1f%%", utilization * 100))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                }
            }
            .frame(height: 30)
            
            HStack {
                Text("Warning threshold: 60%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(utilizationColor)
                    .frame(width: 8, height: 8)
                Text(utilizationStatus)
                    .font(.caption)
                    .foregroundStyle(utilizationColor)
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MemberSelector: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedMember: Member?
    @State private var filterOption: MemberFilterOption = .all
    @State private var sortOption: MemberSortOption = .name
    
    enum MemberFilterOption: String, CaseIterable {
        case all = "All Members"
        case withActiveLoan = "With Active Loan"
        case withoutActiveLoan = "Without Active Loan"

        var icon: String {
            switch self {
            case .all: return "person.3"
            case .withActiveLoan: return "creditcard.fill"
            case .withoutActiveLoan: return "creditcard"
            }
        }
    }

    enum MemberSortOption: String, CaseIterable {
        case name = "Name"
        case role = "Role"
    }

    var filteredMembers: [Member] {
        let members = dataManager.members.filter { member in
            switch filterOption {
            case .all:
                return true
            case .withActiveLoan:
                return member.hasActiveLoans
            case .withoutActiveLoan:
                return !member.hasActiveLoans
            }
        }

        return members.sorted { m1, m2 in
            switch sortOption {
            case .name:
                return (m1.name ?? "") < (m2.name ?? "")
            case .role:
                return m1.memberRole.rawValue < m2.memberRole.rawValue
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with filters
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Member")
                    .font(.headline)
                
                // Filter and Sort Controls
                HStack {
                    // Filter Menu
                    Menu {
                        ForEach(MemberFilterOption.allCases, id: \.self) { option in
                            Button {
                                filterOption = option
                            } label: {
                                Label(option.rawValue, systemImage: option.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filterOption.icon)
                            Text(filterOption.rawValue)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    
                    // Sort Menu
                    Menu {
                        ForEach(MemberSortOption.allCases, id: \.self) { option in
                            Button {
                                sortOption = option
                            } label: {
                                Text("Sort by \(option.rawValue)")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortOption.rawValue)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    
                    Spacer()
                    
                    // Member count
                    Text("\(filteredMembers.count) members")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Member List
            if filteredMembers.isEmpty {
                VStack {
                    Image(systemName: "person.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No members match filter")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
                    ForEach(filteredMembers) { member in
                        Button {
                            selectedMember = member
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(member.name ?? "Unknown")
                                        .fontWeight(.medium)

                                    Text(member.memberRole.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                // Status Indicators
                                VStack(alignment: .trailing, spacing: 4) {
                                    if member.memberStatus != .active {
                                        Text(member.memberStatus.rawValue.capitalized)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.red.opacity(0.2))
                                            .foregroundStyle(.red)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}


struct LoanSummaryReport: View {
    @EnvironmentObject var dataManager: DataManager
    let startDate: Date
    let endDate: Date
    
    /// Loans whose issueDate falls within the selected period.
    /// Includes completed loans, since the user is asking "what was issued
    /// in this window" — the report's "Total Loans Issued" metric only
    /// makes sense with that interpretation.
    var filteredLoans: [Loan] {
        dataManager.allLoans.filter { loan in
            guard let issued = loan.issueDate else { return false }
            return issued >= startDate && issued <= endDate
        }
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
                        .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(CurrencyFormatter.shared.format(loan.amount))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                HStack(spacing: 4) {
                                    Text("Balance: \(CurrencyFormatter.shared.format(loan.balance))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    if loan.isOverdue {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding()
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(.secondary)
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
        return ChartDataGenerator.shared.generateMonthlyContributionData(
            months: 6,
            context: PersistenceController.shared.container.viewContext
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contribution Analysis")
                .font(.headline)
            
            if monthlyTotals.isEmpty {
                Text("No contribution data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("Last 6 months")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(CurrencyFormatter.shared.format(loansIssuedInPeriod.reduce(0) { $0 + $1.amount }))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Total Issued")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dataManager.members.filter { $0.hasActiveLoans }.count)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("With Active Loans")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        return ChartDataGenerator.shared.generateFundGrowthData(
            months: 6,
            context: PersistenceController.shared.container.viewContext
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fund Growth Trend")
                .font(.headline)
            
            if fundGrowthData.isEmpty {
                Text("No fund data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(averageLoanAmount))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Repayment Success Rate")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", repaymentRate * 100))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(repaymentRate > 0.8 ? .green : .orange)
                }
                
                HStack {
                    Text("Active Loans")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(dataManager.activeLoans.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                StatusBadge(status: member.memberStatus)
            }
            
            Divider()

            HStack {
                InfoItem(label: "Member Since", value: DateHelper.formatDate(member.joinDate))
                Spacer()
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct InfoItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(netPosition >= 0 ? .green : .red)
            }
            .padding()
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(CurrencyFormatter.shared.format(amount))
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if loan.loanStatus == .completed {
                                Label("Completed", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if loan.isOverdue {
                                Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Label("Active", systemImage: "circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        
                        if loan.loanStatus == .active {
                            ProgressView(value: loan.completionPercentage, total: 100)
                                .tint(loan.isOverdue ? .red : Color.accentColor)
                            
                            HStack {
                                Text("Balance: \(CurrencyFormatter.shared.format(loan.balance))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(loan.completionPercentage))% paid")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MemberTransactionHistory: View {
    let member: Member
    
    var transactions: [Transaction] {
        (member.transactions?.allObjects as? [Transaction] ?? [])
            .sorted { ($0.createdAt ?? Date()) > ($1.createdAt ?? Date()) }
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
                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(CurrencyFormatter.shared.format(abs(transaction.amount)))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(transaction.transactionType.isCredit ? .green : .red)
                            
                            if let description = transaction.transactionDescription {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(CurrencyFormatter.shared.format(abs(transaction.amount)))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(transaction.amount > 0 ? .green : .red)
                    }
                    .padding(.vertical, 4)
                    
                    if transaction != recentTransactions.prefix(5).last {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Report Type Button

struct ReportTypeButton: View {
    let reportType: ReportsView.ReportType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: reportType.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)

                Text(reportType.rawValue)
                    .font(.caption2)
                    .foregroundStyle(textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 88, height: 66)
            .background(backgroundView)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.3) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        if isSelected {
            return .accentColor
        } else {
            return .secondary
        }
    }

    private var textColor: Color {
        isSelected ? .primary : .secondary
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.08))
                )
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .opacity(0.5)
        }
    }
}

#Preview {
    ReportsView()
        .environmentObject(DataManager.shared)
}
#endif
