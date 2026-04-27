//
//  LoansListView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//  macOS 26 Tahoe HIG Compliant
//

import SwiftUI

struct LoansListView: View {
    @StateObject private var viewModel = LoanViewModel()
    @State private var showingNewLoan = false

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 0) {
                    fundStatusHeader
                    filterBar

                    if viewModel.filteredLoans.isEmpty {
                        emptyStateView
                    } else {
                        loansList
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Loans list")
            .navigationTitle("Loans")
            .toolbar {
                if !viewModel.eligibleMembers.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingNewLoan = true } label: {
                            Label("New Loan", systemImage: "plus")
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button { viewModel.loadLoans() } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search by member name")
            .sheet(isPresented: $showingNewLoan) {
                NewLoanSheet()
            }
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK") { viewModel.showingError = false }
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .onReceive(NotificationCenter.default.publisher(for: .loanBalanceUpdated)) { _ in
                viewModel.loadLoans()
            }
            .onReceive(NotificationCenter.default.publisher(for: .paymentSaved)) { _ in
                viewModel.loadLoans()
            }
            .onReceive(NotificationCenter.default.publisher(for: .memberDataUpdated)) { _ in
                viewModel.loadLoans()
            }
            .onReceive(NotificationCenter.default.publisher(for: .transactionsUpdated)) { _ in
                viewModel.loadLoans()
            }
        }
    }

    private func openLoanDetail(_ loan: Loan) {
        #if os(macOS)
        if let loanID = loan.loanID {
            openWindow(id: "loan-detail", value: loanID)
        }
        #endif
    }

    // MARK: - View Components

    private var fundStatusHeader: some View {
        // Compact stat strip with fund balance + utilization gauge inline.
        HStack(spacing: 16) {
            MiniMetricCard(
                title: "Fund Balance",
                value: viewModel.formatCurrency(viewModel.fundBalance),
                systemImage: "banknote.fill",
                tint: .green
            )
            MiniMetricCard(
                title: "Active Loans",
                value: "\(viewModel.activeLoans.count)",
                systemImage: "creditcard.fill",
                tint: .blue
            )
            MiniMetricCard(
                title: "Outstanding",
                value: viewModel.formatCurrency(viewModel.totalActiveLoansAmount),
                systemImage: "dollarsign.circle.fill",
                tint: .orange
            )
            MiniMetricCard(
                title: "Overdue",
                value: "\(viewModel.overdueLoans.count)",
                systemImage: "exclamationmark.triangle.fill",
                tint: viewModel.overdueLoans.isEmpty ? .green : .red
            )
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
    
    private var filterBar: some View {
        VStack(spacing: 0) {
            // Native search field is provided by .searchable on the parent view.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    // Status Filter
                Menu {
                    Button("All Status") {
                        viewModel.filterStatus = nil
                    }
                    Divider()
                    ForEach(LoanStatus.allCases, id: \.self) { status in
                        Button(status.displayName) {
                            viewModel.filterStatus = status
                        }
                    }
                } label: {
                    Label(
                        viewModel.filterStatus?.displayName ?? "All Status",
                        systemImage: "circle.fill"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Overdue Filter
                Toggle("Overdue Only", isOn: $viewModel.showOverdueOnly)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(viewModel.showOverdueOnly ? .red : .secondary)
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var loansList: some View {
        List {
            ForEach(viewModel.filteredLoans) { loan in
                LoanRowView(loan: loan) {
                    openLoanDetail(loan)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Loans", systemImage: "creditcard.fill")
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if viewModel.eligibleMembers.isEmpty {
                Button("View Members") {
                    // TODO: Navigate to members
                }
            } else {
                Button("Create New Loan") {
                    showingNewLoan = true
                }
            }
        }
    }
    
    private var emptyStateDescription: String {
        if viewModel.showOverdueOnly {
            return "No overdue loans found"
        } else if viewModel.filterStatus != nil {
            return "No loans match your filter criteria"
        } else if viewModel.eligibleMembers.isEmpty {
            return "No eligible members for loans"
        } else {
            return "No loans have been issued yet"
        }
    }
    
}

// MARK: - Loan Row View

struct LoanRowView: View {
    let loan: Loan
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loan.member?.name ?? "Unknown Member")
                            .font(.headline)
                        HStack {
                            Text(loan.member?.memberRole.displayName ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if loan.isOverdue {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(CurrencyFormatter.shared.format(loan.amount))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Issued \(DateHelper.formatDate(loan.issueDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: loan.completionPercentage, total: 100)
                        .tint(loan.isOverdue ? .red : Color.accentColor)
                    
                    HStack {
                        Text("Balance: \(CurrencyFormatter.shared.format(loan.balance))")
                            .font(.caption)
                        
                        Spacer()
                        
                        Text("\(Int(loan.completionPercentage))% paid")
                            .font(.caption)
                        
                        if let nextPayment = loan.nextPaymentDue {
                            Text("•")
                            Text("Next: \(DateHelper.formatDate(nextPayment))")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New Loan Sheet

struct NewLoanSheet: View {
    @StateObject private var viewModel = LoanViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.eligibleMembers.isEmpty {
                    ContentUnavailableView(
                        "No Eligible Members",
                        systemImage: "person.crop.circle.badge.xmark",
                        description: Text("No members are currently eligible for loans")
                    )
                } else {
                    Form {
                        Section("Loan Details") {
                            // Member Selection
                            Picker("Select Member", selection: $viewModel.selectedMember) {
                                Text("Choose a member").tag(nil as Member?)
                                ForEach(viewModel.eligibleMembers) { member in
                                    HStack {
                                        Text(member.name ?? "")
                                        Spacer()
                                        Text("Max: \(CurrencyFormatter.shared.format(member.maximumLoanAmount))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(member as Member?)
                                }
                            }
                            
                            // Loan Amount
                            if viewModel.selectedMember != nil {
                                HStack {
                                    Text("Amount")
                                    Spacer()
                                    TextField("0", text: $viewModel.loanAmount)
                                        .multilineTextAlignment(.trailing)
                                        .onChange(of: viewModel.loanAmount) {
                                            viewModel.calculateLoanDetails()
                                        }
                                }
                                
                                if let member = viewModel.selectedMember {
                                    HStack {
                                        Text("Maximum Allowed")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(CurrencyFormatter.shared.format(member.maximumLoanAmount))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                // Repayment Period
                                Picker("Repayment Period", selection: $viewModel.repaymentMonths) {
                                    if viewModel.adminOverrideEnabled {
                                        // When override is enabled, show all options
                                        Text("3 Months").tag(3)
                                        Text("4 Months").tag(4)
                                        Text("6 Months").tag(6)
                                    } else if let member = viewModel.selectedMember {
                                        // Show member's allowed repayment months
                                        ForEach(member.allowedRepaymentMonths, id: \.self) { months in
                                            Text("\(months) Months").tag(months)
                                        }
                                    }
                                }
                                .onChange(of: viewModel.repaymentMonths) {
                                    viewModel.calculateLoanDetails()
                                }
                                .onChange(of: viewModel.selectedMember) {
                                    // Reset repayment months when member changes
                                    if let member = viewModel.selectedMember {
                                        // Use the first allowed repayment month for this member
                                        if let firstAllowed = member.allowedRepaymentMonths.first {
                                            viewModel.repaymentMonths = firstAllowed
                                        }
                                        viewModel.calculateLoanDetails()
                                    }
                                }
                                
                                // Issue Date
                                DatePicker("Issue Date", selection: $viewModel.loanIssueDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .onChange(of: viewModel.loanIssueDate) {
                                        viewModel.calculateLoanDetails()
                                    }
                            }
                        }
                        
                        Section("Notes (Optional)") {
                            TextEditor(text: $viewModel.loanNotes)
                                .frame(minHeight: 60)
                        }

                        // Admin Override Section
                        Section {
                            Toggle("Admin Override", isOn: $viewModel.adminOverrideEnabled)

                            if viewModel.adminOverrideEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Override allows bypassing loan limits and repayment period restrictions. A reason is required for audit purposes.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)

                                    TextField("Reason for override (required)", text: $viewModel.overrideReason)
                                        .textFieldStyle(.roundedBorder)

                                    if let member = viewModel.selectedMember {
                                        HStack {
                                            Text("Standard limit:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(CurrencyFormatter.shared.format(member.baseLoanLimit))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if member.hasCustomLoanLimit {
                                            HStack {
                                                Text("Custom limit:")
                                                    .font(.caption)
                                                    .foregroundStyle(.blue)
                                                Text(CurrencyFormatter.shared.format(member.customLoanLimit))
                                                    .font(.caption)
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("Admin Override")
                                Image(systemName: "exclamationmark.shield")
                                    .foregroundStyle(.orange)
                            }
                        }

                        // Payment Schedule
                        if !viewModel.loanSchedule.isEmpty {
                            Section("Payment Schedule") {
                                ForEach(viewModel.loanSchedule, id: \.paymentNumber) { schedule in
                                    HStack {
                                        Text("Payment \(schedule.paymentNumber)")
                                            .font(.subheadline)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(CurrencyFormatter.shared.format(schedule.totalPayment))
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Text(DateHelper.formatDate(schedule.dueDate))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                
                                HStack {
                                    Text("Monthly Loan Payment")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("(Contribution paid separately)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        // Warnings
                        if !viewModel.validationWarnings.isEmpty {
                            Section {
                                ForEach(viewModel.validationWarnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Loan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.createLoan()
                        // Don't dismiss if there's an error OR if warning dialog is showing
                        if !viewModel.showingError && !viewModel.showWarningDialog {
                            dismiss()
                        }
                    }
                    .disabled(viewModel.selectedMember == nil || viewModel.loanAmount.isEmpty)
                }
            }
            .alert("Confirm Loan", isPresented: $viewModel.showWarningDialog) {
                Button("Proceed") {
                    viewModel.proceedWithLoanCreation()
                    // Check if loan was created successfully (warning dialog will be cleared)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !viewModel.showWarningDialog && !viewModel.showingError {
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    // User cancelled loan due to warnings
                }
            } message: {
                Text(viewModel.validationWarnings.joined(separator: "\n\n"))
            }
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK") {
                    viewModel.showingError = false
                }
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred while creating the loan")
            }
        }
    }
}

// MARK: - Supporting Views

struct UtilizationGauge: View {
    let percentage: Double
    let showWarning: Bool
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Utilization")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 4) {
                Text(String(format: "%.0f%%", percentage * 100))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(gaugeColor)
                
                Image(systemName: showWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(gaugeColor)
            }
        }
    }
    
    private var gaugeColor: Color {
        if percentage >= 0.6 {
            return .red
        } else if percentage >= 0.4 {
            return .orange
        } else {
            return .green
        }
    }
}

#Preview {
    LoansListView()
        .environmentObject(DataManager.shared)
}