//
//  PaymentsView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//  macOS 26 Tahoe HIG Compliant
//

import SwiftUI

struct PaymentsView: View {
    @StateObject private var viewModel = PaymentViewModel()
    @State private var showingNewPayment = false
    @State private var selectedPayment: Payment?
    // Removed sheet-based edit state variables as we're using windows now
    @State private var showingDeleteConfirmation = false
    @State private var paymentToDelete: Payment?

    @State private var paymentSavedTrigger = false

    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 0) {
                    paymentSummaryHeader
                    dateRangeFilter
                    filterBar

                    if viewModel.filteredPayments.isEmpty {
                        emptyStateView
                    } else {
                        paymentsList
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primaryBackground)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Payments list")
            .navigationTitle("Payments")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewPayment = true } label: {
                        Label("New Payment", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button { viewModel.loadPayments() } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Divider()
                        Button { exportPayments() } label: {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search by member name")
            .sheet(isPresented: $showingNewPayment) {
                PaymentFormView(viewModel: viewModel)
            }
            .sensoryFeedback(.success, trigger: paymentSavedTrigger)
            .onAppear { viewModel.loadPayments() }
            .onReceive(NotificationCenter.default.publisher(for: .paymentSaved)) { _ in
                viewModel.loadPayments()
                paymentSavedTrigger.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .transactionsUpdated)) { _ in
                viewModel.loadPayments()
            }
            .onReceive(NotificationCenter.default.publisher(for: .memberDataUpdated)) { _ in
                viewModel.loadPayments()
            }
            .confirmationDialog(
                "Delete Payment",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let payment = paymentToDelete {
                        viewModel.deletePayment(payment)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this payment? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - View Components
    
    private var paymentSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(paymentsHeadline)
                .font(.system(.title, design: .serif))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                MiniMetricCard(
                    title: "Total",
                    value: viewModel.formatCurrency(viewModel.paymentSummary.totalAmount),
                    systemImage: "dollarsign.circle",
                    tint: BrandColor.terracotta
                )
                MiniMetricCard(
                    title: "Contributions",
                    value: viewModel.formatCurrency(viewModel.paymentSummary.totalContributions),
                    systemImage: "banknote",
                    tint: BrandColor.avocado
                )
                MiniMetricCard(
                    title: "Loan Repayments",
                    value: viewModel.formatCurrency(viewModel.paymentSummary.totalLoanRepayments),
                    systemImage: "creditcard",
                    tint: BrandColor.honey
                )
            }

            HStack(spacing: 16) {
                Label("\(viewModel.paymentSummary.paymentCount) payments", systemImage: "number.circle")
                if viewModel.paymentSummary.paymentCount > 0 {
                    Label("Avg \(viewModel.formatCurrency(viewModel.paymentSummary.averagePayment))",
                          systemImage: "chart.line.uptrend.xyaxis")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var paymentsHeadline: String {
        let count = viewModel.paymentSummary.paymentCount
        if count == 0 { return "No Payments Yet" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        let spelled = (formatter.string(from: NSNumber(value: count)) ?? "\(count)").capitalized
        return "\(spelled) \(count == 1 ? "Payment" : "Payments")"
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
        .onChange(of: viewModel.startDate) {
            viewModel.loadPayments()
        }
        .onChange(of: viewModel.endDate) {
            viewModel.loadPayments()
        }
    }
    
    private var filterBar: some View {
        VStack(spacing: 0) {
            // Native search field is provided by .searchable on the parent view.
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
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var paymentsList: some View {
        List {
            ForEach(viewModel.filteredPayments) { payment in
                PaymentRowView(payment: payment) {
                    selectedPayment = payment
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        paymentToDelete = payment
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    // Edit-payment opens a separate macOS window via the
                    // PaymentEditWindowController (AppKit-backed). iOS
                    // gets an inline edit sheet in a follow-up Sprint 6
                    // commit; for now, the edit affordance is mac-only.
                    #if os(macOS)
                    Button {
                        PaymentEditWindowController.openEditWindow(for: payment) {
                            viewModel.loadPayments()
                        }
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                    #endif
                }
                .contextMenu {
                    #if os(macOS)
                    Button {
                        PaymentEditWindowController.openEditWindow(for: payment) {
                            viewModel.loadPayments()
                        }
                    } label: {
                        Label("Edit Payment", systemImage: "pencil")
                    }
                    #endif
                    
                    Button {
                        selectedPayment = payment
                    } label: {
                        Label("View Details", systemImage: "info.circle")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        paymentToDelete = payment
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Payment", systemImage: "trash")
                    }
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
        // Export CSV generated
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
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Amount and Date
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(CurrencyFormatter.shared.format(payment.amount))
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text(DateHelper.formatDate(payment.paymentDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        .foregroundStyle(.orange)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "banknote.fill")
                                .font(.caption2)
                            Text("Contribution: \(CurrencyFormatter.shared.format(payment.contributionAmount))")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                        
                        Spacer()
                    }
                }
                
                // Notes if available
                if let notes = payment.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    .foregroundStyle(color)
                    .font(.title3)
                Spacer()
            }
            
            Text(value)
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

#Preview {
    PaymentsView()
        .environmentObject(DataManager.shared)
}