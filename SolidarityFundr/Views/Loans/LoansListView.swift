//
//  LoansListView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI
import Combine

struct LoansListView: View {
    @StateObject private var viewModel = LoanViewModel()
    @State private var selectedLoan: Loan?
    @State private var showingNewLoan = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        VStack(spacing: 0) {
            // Fund Status Header
            fundStatusHeader
            
            // Filter Bar
            filterBar
            
            // Loans List
            if viewModel.filteredLoans.isEmpty {
                emptyStateView
            } else {
                loansList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingNewLoan) {
            NewLoanSheet()
        }
        .sheet(item: $selectedLoan) { loan in
            NavigationStack {
                LoanDetailView(loan: loan)
            }
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {
                viewModel.showingError = false
            }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
        .onAppear {
            // Set up listener for loan balance updates
            NotificationCenter.default.publisher(for: .loanBalanceUpdated)
                .sink { _ in
                    print("🔧 LoansListView: Loan balance updated, refreshing loans...")
                    viewModel.loadLoans()
                }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - View Components
    
    private var fundStatusHeader: some View {
        VStack(spacing: 12) {
            // Clean header matching Overview style
            VStack(alignment: .leading, spacing: 8) {
                Text("Loan Management")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Loans")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    // Toolbar actions
                    if !viewModel.eligibleMembers.isEmpty {
                        Button {
                            showingNewLoan = true
                        } label: {
                            Label("New Loan", systemImage: "plus")
                        }
                    }
                    
                    Menu {
                        Button {
                            viewModel.loadLoans()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
                
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Fund Balance
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fund Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(viewModel.formatCurrency(viewModel.fundBalance))
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                // Utilization Gauge
                UtilizationGauge(
                    percentage: viewModel.utilizationPercentage,
                    showWarning: viewModel.utilizationWarning
                )
            }
            .padding(.horizontal)
            
            // Loan Statistics
            HStack(spacing: 20) {
                StatisticCard(
                    title: "Active Loans",
                    value: "\(viewModel.activeLoans.count)",
                    icon: "creditcard.fill",
                    color: .blue
                )
                
                StatisticCard(
                    title: "Total Outstanding",
                    value: viewModel.formatCurrency(viewModel.totalActiveLoansAmount),
                    icon: "dollarsign.circle.fill",
                    color: .orange
                )
                
                StatisticCard(
                    title: "Overdue",
                    value: "\(viewModel.overdueLoans.count)",
                    icon: "exclamationmark.triangle.fill",
                    color: viewModel.overdueLoans.isEmpty ? .green : .red
                )
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
    }
    
    private var filterBar: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search by member name...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
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
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
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
                    selectedLoan = loan
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
                                .foregroundColor(.secondary)
                            
                            if loan.isOverdue {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
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
                            .foregroundColor(.secondary)
                    }
                }
                
                // Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: loan.completionPercentage, total: 100)
                        .tint(loan.isOverdue ? .red : .accentColor)
                    
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
                    .foregroundColor(.secondary)
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
                                            .foregroundColor(.secondary)
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
                                        .onChange(of: viewModel.loanAmount) { _ in
                                            viewModel.calculateLoanDetails()
                                        }
                                }
                                
                                if let member = viewModel.selectedMember {
                                    HStack {
                                        Text("Maximum Allowed")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(CurrencyFormatter.shared.format(member.maximumLoanAmount))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                // Repayment Period
                                Picker("Repayment Period", selection: $viewModel.repaymentMonths) {
                                    Text("3 Months").tag(3)
                                    Text("4 Months").tag(4)
                                }
                                .onChange(of: viewModel.repaymentMonths) { _ in
                                    viewModel.calculateLoanDetails()
                                }
                                
                                // Issue Date
                                DatePicker("Issue Date", selection: $viewModel.loanIssueDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .onChange(of: viewModel.loanIssueDate) { _ in
                                        viewModel.calculateLoanDetails()
                                    }
                            }
                        }
                        
                        Section("Notes (Optional)") {
                            TextEditor(text: $viewModel.loanNotes)
                                .frame(minHeight: 60)
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
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                HStack {
                                    Text("Monthly Loan Payment")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("(Contribution paid separately)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // Warnings
                        if !viewModel.validationWarnings.isEmpty {
                            Section {
                                ForEach(viewModel.validationWarnings, id: \.self) { warning in
                                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
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
                        if !viewModel.showingError {
                            dismiss()
                        }
                    }
                    .disabled(viewModel.selectedMember == nil || viewModel.loanAmount.isEmpty)
                }
            }
            .alert("Confirm Loan", isPresented: $viewModel.showWarningDialog) {
                Button("Proceed") {
                    viewModel.proceedWithLoanCreation()
                    if !viewModel.showingError {
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(viewModel.validationWarnings.joined(separator: "\n\n"))
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
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Text(String(format: "%.0f%%", percentage * 100))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(gaugeColor)
                
                Image(systemName: showWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(gaugeColor)
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