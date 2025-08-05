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
import Combine

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
    @State private var refreshID = UUID()
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showingNotificationHistory = false
    @State private var showingBatchStatement = false
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
                case .fundSummary:
                    FundSummaryReport()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Export Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingNotificationHistory) {
            NotificationHistoryView()
        }
        .sheet(isPresented: $showingBatchStatement) {
            BatchStatementView()
                .environmentObject(dataManager)
        }
        .onAppear {
            setupNotificationListeners()
            // Recalculate all member contributions on view load to fix any discrepancies
            if !hasRecalculated {
                dataManager.recalculateAllMemberContributions()
                hasRecalculated = true
            }
        }
        .id(refreshID)
    }
    
    private func setupNotificationListeners() {
        // Listen for payment updates
        NotificationCenter.default.publisher(for: .paymentSaved)
            .sink { _ in
                refreshID = UUID()
            }
            .store(in: &cancellables)
        
        // Listen for loan balance updates
        NotificationCenter.default.publisher(for: .loanBalanceUpdated)
            .sink { _ in
                refreshID = UUID()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - View Components
    
    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analytics & Insights")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Reports")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    showingBatchStatement = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 14))
                        Text("Batch Statements")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    showingNotificationHistory = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 14))
                        Text("Message History")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    generatePDF()
                } label: {
                    HStack(spacing: 6) {
                        if isGeneratingPDF {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 14))
                            Text("Open in Preview")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingPDF)
            }
            
            Text(Date().formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
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
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                
                Text("–")
                    .foregroundColor(.secondary)
                
                DatePicker("To", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            
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
    @State private var isSendingMessage = false
    @State private var showingSendConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var successMessage = ""
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
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                
                // Member Info with SMS Status
                MemberInfoCard(member: member)
                
                // Statement Actions
                MemberStatementActions(
                    member: member,
                    pdfURL: $pdfURL,
                    isGeneratingPDF: $isGeneratingPDF,
                    isSendingMessage: $isSendingMessage,
                    showingSendConfirmation: $showingSendConfirmation,
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
        .alert("Send Statement", isPresented: $showingSendConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Send via WhatsApp") {
                sendStatement(useWhatsApp: true)
            }
        } message: {
            if let member = selectedMember {
                Text("Send monthly statement to \(member.name ?? "member") at \(member.phoneNumber ?? "unknown") via WhatsApp?\n\nThe PDF will be sent directly as an attachment.\n\nPeriod: \(DateHelper.formatDate(statementPeriodStart)) - \(DateHelper.formatDate(statementPeriodEnd))")
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK") {}
        } message: {
            Text(successMessage)
        }
    }
    
    private func sendStatement(useWhatsApp: Bool = false) {
        guard let member = selectedMember,
              let pdfURL = pdfURL,
              let window = NSApp.windows.first else { return }
        
        do {
            let pdfData = try Data(contentsOf: pdfURL)
            
            // Show WhatsApp sharing picker
            if let contentView = window.contentView {
                WhatsAppSharingService.shared.shareStatement(
                    pdfData: pdfData,
                    for: member,
                    in: contentView
                )
                
                // Record the share action
                Task {
                    try await StatementService.shared.recordWhatsAppShare(for: member, pdfData: pdfData)
                    
                    await MainActor.run {
                        successMessage = "Statement prepared for \(member.name ?? "member")"
                        showingSuccess = true
                    }
                }
            }
        } catch {
            errorMessage = "Failed to prepare statement: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Supporting Views

struct MemberStatementActions: View {
    let member: Member
    @Binding var pdfURL: URL?
    @Binding var isGeneratingPDF: Bool
    @Binding var isSendingMessage: Bool
    @Binding var showingSendConfirmation: Bool
    @Binding var statementPeriodStart: Date
    @Binding var statementPeriodEnd: Date
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var dataManager: DataManager
    
    var canSendMessage: Bool {
        // For WhatsApp, we just need a phone number and active status
        member.phoneNumber != nil && member.memberStatus == .active
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack {
                Label("Statement Actions", systemImage: "doc.text.fill")
                    .font(.headline)
                
                Spacer()
                
                // Period Selector
                HStack(spacing: 8) {
                    DatePicker("From", selection: $statementPeriodStart, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    
                    Text("–")
                        .foregroundColor(.secondary)
                    
                    DatePicker("To", selection: $statementPeriodEnd, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
            }
            
            // Action Buttons
            HStack(spacing: 16) {
                // Generate & Preview Button
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
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingPDF || isSendingMessage)
                
                // Send WhatsApp Button
                Button {
                    showingSendConfirmation = true
                } label: {
                    HStack {
                        if isSendingMessage {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "message.fill")
                        }
                        Text("Send via WhatsApp")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(canSendMessage && pdfURL != nil ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage || pdfURL == nil || isSendingMessage)
                .help(getSendButtonHelp())
            }
            
            // Status Messages
            if !canSendMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(getMessageDisabledReason())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // Recent Message History
            if let recentNotifications = getRecentNotifications() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Statements")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(recentNotifications.prefix(3)) { notification in
                        HStack {
                            Circle()
                                .fill(notification.status == "delivered" ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            
                            Text(DateHelper.formatDate(notification.sentDate))
                                .font(.caption)
                            
                            Spacer()
                            
                            Text(notification.status ?? "sent")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
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
                    // Open in Preview
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
    
    private func getSendButtonHelp() -> String {
        if member.phoneNumber == nil {
            return "Member has no phone number on file"
        } else if member.memberStatus != .active {
            return "Member is not active"
        } else if pdfURL == nil {
            return "Generate PDF first before sending"
        } else {
            return "Send statement via WhatsApp with PDF attachment"
        }
    }
    
    private func getMessageDisabledReason() -> String {
        if member.phoneNumber == nil {
            return "No phone number on file"
        } else if member.memberStatus != .active {
            return "Member is not active"
        } else {
            return ""
        }
    }
    
    private func getRecentNotifications() -> [NotificationHistory]? {
        let request: NSFetchRequest<NotificationHistory> = NotificationHistory.fetchRequest()
        request.predicate = NSPredicate(format: "member == %@", member)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \NotificationHistory.sentDate, ascending: false)]
        request.fetchLimit = 3
        
        do {
            let notifications = try viewContext.fetch(request)
            return notifications.isEmpty ? nil : notifications
        } catch {
            print("Error fetching notifications: \(error)")
            return nil
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
    @State private var filterOption: MemberFilterOption = .all
    @State private var sortOption: MemberSortOption = .name
    
    enum MemberFilterOption: String, CaseIterable {
        case all = "All Members"
        case whatsAppEnabled = "WhatsApp Available"
        case neverSent = "Never Sent"
        case overdue = "Overdue"
        
        var icon: String {
            switch self {
            case .all: return "person.3"
            case .whatsAppEnabled: return "message.fill"
            case .neverSent: return "paperplane"
            case .overdue: return "clock.badge.exclamationmark"
            }
        }
    }
    
    enum MemberSortOption: String, CaseIterable {
        case name = "Name"
        case lastStatement = "Last Statement"
        case role = "Role"
    }
    
    var filteredMembers: [Member] {
        let members = dataManager.members.filter { member in
            switch filterOption {
            case .all:
                return true
            case .whatsAppEnabled:
                return member.phoneNumber != nil
            case .neverSent:
                return member.lastStatementSentDate == nil
            case .overdue:
                // Consider overdue if no statement sent in last 30 days
                if let lastSent = member.lastStatementSentDate {
                    return Date().timeIntervalSince(lastSent) > 30 * 24 * 60 * 60
                }
                return true
            }
        }
        
        return members.sorted { m1, m2 in
            switch sortOption {
            case .name:
                return (m1.name ?? "") < (m2.name ?? "")
            case .lastStatement:
                let date1 = m1.lastStatementSentDate ?? Date.distantPast
                let date2 = m2.lastStatementSentDate ?? Date.distantPast
                return date1 > date2
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
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
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
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    // Member count
                    Text("\(filteredMembers.count) members")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Member List
            if filteredMembers.isEmpty {
                VStack {
                    Image(systemName: "person.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No members match filter")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                                    HStack {
                                        Text(member.name ?? "Unknown")
                                            .fontWeight(.medium)
                                        
                                        // WhatsApp Status Icon
                                        if member.phoneNumber != nil {
                                            Image(systemName: "message.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    
                                    HStack {
                                        Text(member.memberRole.displayName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        if let lastSent = member.lastStatementSentDate {
                                            Text("• Last sent: \(DateHelper.formatShortDate(lastSent))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("• Never sent")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
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
                                            .foregroundColor(.red)
                                            .cornerRadius(4)
                                    }
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
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
            
            // WhatsApp Status Row
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: member.phoneNumber != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(member.phoneNumber != nil ? .green : .red)
                        .font(.caption)
                    Text("WhatsApp \(member.phoneNumber != nil ? "Available" : "No Phone")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let lastStatementDate = member.lastStatementSentDate {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Last sent: \(DateHelper.formatDate(lastStatementDate))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("No statements sent")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
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
                                .foregroundColor(transaction.transactionType.isCredit ? .green : .red)
                            
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

// MARK: - Report Type Button

struct ReportTypeButton: View {
    let reportType: ReportsView.ReportType
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: reportType.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                
                Text(reportType.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(textColor)
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
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var iconColor: Color {
        if isSelected {
            return .accentColor
        } else if isHovered {
            return .primary
        } else {
            return .secondary
        }
    }
    
    private var textColor: Color {
        if isSelected {
            return .primary
        } else if isHovered {
            return .primary.opacity(0.9)
        } else {
            return .secondary
        }
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
        } else if isHovered {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.03))
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