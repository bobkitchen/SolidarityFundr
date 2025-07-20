//
//  PaymentsView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI

struct PaymentsView: View {
    @StateObject private var viewModel = PaymentViewModel()
    @State private var showingNewPayment = false
    @State private var selectedPayment: Payment?
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary Header
            paymentSummaryHeader
            
            // Date Range Filter
            dateRangeFilter
            
            // Filter Options
            filterBar
            
            // Payments List
            if viewModel.filteredPayments.isEmpty {
                emptyStateView
            } else {
                paymentsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $viewModel.searchText, prompt: "Search by member name...")
        .sheet(isPresented: $showingNewPayment) {
            PaymentFormView()
        }
        .onAppear {
            viewModel.loadPayments()
        }
    }
    
    // MARK: - View Components
    
    private var paymentSummaryHeader: some View {
        VStack(spacing: 12) {
            // Title and toolbar
            HStack {
                Text("Payments")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Toolbar actions
                Button {
                    showingNewPayment = true
                } label: {
                    Label("New Payment", systemImage: "plus")
                }
                
                Menu {
                    Button {
                        viewModel.loadPayments()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    
                    Divider()
                    
                    Button {
                        exportPayments()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
            .padding(.horizontal)
            .padding(.top, 16) // Normal padding - traffic lights will overlay
            .padding(.bottom, 12)
            
            HStack(spacing: 20) {
                SummaryCard(
                    title: "Total Payments",
                    value: viewModel.formatCurrency(viewModel.paymentSummary.totalAmount),
                    icon: "dollarsign.circle.fill",
                    color: .green
                )
                
                SummaryCard(
                    title: "Contributions",
                    value: viewModel.formatCurrency(viewModel.paymentSummary.totalContributions),
                    icon: "banknote.fill",
                    color: .blue
                )
                
                SummaryCard(
                    title: "Loan Repayments",
                    value: viewModel.formatCurrency(viewModel.paymentSummary.totalLoanRepayments),
                    icon: "creditcard.fill",
                    color: .orange
                )
            }
            .padding(.horizontal)
            
            HStack {
                Label("\(viewModel.paymentSummary.paymentCount) payments", systemImage: "number.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if viewModel.paymentSummary.paymentCount > 0 {
                    Label("Avg: \(viewModel.formatCurrency(viewModel.paymentSummary.averagePayment))", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color.secondary.opacity(0.1))
    }
    
    private var dateRangeFilter: some View {
        HStack {
            DatePicker("From", selection: $viewModel.startDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            
            Spacer()
            
            DatePicker("To", selection: $viewModel.endDate, displayedComponents: .date)
                .datePickerStyle(.compact)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onChange(of: viewModel.startDate) { _ in
            viewModel.loadPayments()
        }
        .onChange(of: viewModel.endDate) { _ in
            viewModel.loadPayments()
        }
    }
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                // Payment Type Filter
                Menu {
                    Button("All Types") {
                        viewModel.filterType = nil
                    }
                    Divider()
                    ForEach(PaymentType.allCases, id: \.self) { type in
                        Button(type.displayName) {
                            viewModel.filterType = type
                        }
                    }
                } label: {
                    Label(
                        viewModel.filterType?.displayName ?? "All Types",
                        systemImage: "square.grid.2x2"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Payment Method Filter
                Menu {
                    Button("All Methods") {
                        viewModel.filterMethod = nil
                    }
                    Divider()
                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                        Button(method.displayName) {
                            viewModel.filterMethod = method
                        }
                    }
                } label: {
                    Label(
                        viewModel.filterMethod?.displayName ?? "All Methods",
                        systemImage: "creditcard"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
    
    private var paymentsList: some View {
        List {
            ForEach(viewModel.filteredPayments) { payment in
                PaymentRowView(payment: payment) {
                    selectedPayment = payment
                }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Payments", systemImage: "dollarsign.circle")
        } description: {
            Text(emptyStateDescription)
        } actions: {
            Button("Make Payment") {
                showingNewPayment = true
            }
        }
    }
    
    private var emptyStateDescription: String {
        if !viewModel.searchText.isEmpty {
            return "No payments match your search"
        } else if viewModel.filterType != nil || viewModel.filterMethod != nil {
            return "No payments match your filters"
        } else {
            return "No payments recorded in this date range"
        }
    }
    
    
    private func exportPayments() {
        let csv = viewModel.exportPayments()
        // TODO: Implement file export
        print("Export CSV: \(csv)")
    }
}

// MARK: - Payment Row View

struct PaymentRowView: View {
    let payment: Payment
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HStack {
                    // Member Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(payment.member?.name ?? "Unknown")
                            .font(.headline)
                        HStack {
                            Image(systemName: iconForPaymentType(payment.paymentType))
                                .font(.caption)
                            Text(payment.paymentType.displayName)
                                .font(.caption)
                            
                            Text("•")
                            
                            Text(payment.paymentMethodType.displayName)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Amount and Date
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(CurrencyFormatter.shared.format(payment.amount))
                            .font(.headline)
                            .foregroundColor(.green)
                        Text(DateHelper.formatDate(payment.paymentDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Breakdown for loan payments
                if payment.paymentType == .loanRepayment || payment.paymentType == .mixed {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "creditcard.fill")
                                .font(.caption2)
                            Text("Loan: \(CurrencyFormatter.shared.format(payment.loanRepaymentAmount))")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "banknote.fill")
                                .font(.caption2)
                            Text("Contribution: \(CurrencyFormatter.shared.format(payment.contributionAmount))")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                        
                        Spacer()
                    }
                }
                
                // Notes if available
                if let notes = payment.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func iconForPaymentType(_ type: PaymentType) -> String {
        switch type {
        case .contribution:
            return "banknote.fill"
        case .loanRepayment:
            return "creditcard.fill"
        case .mixed:
            return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Supporting Views

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            
            Text(value)
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

#Preview {
    PaymentsView()
        .environmentObject(DataManager.shared)
}