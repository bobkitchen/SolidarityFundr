//
//  LoanDetailView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI
import Charts

struct LoanDetailView: View {
    @ObservedObject var loan: Loan
    @StateObject private var viewModel = LoanViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openMemberWindow) private var openMemberWindow
    @State private var selectedTab = 0
    @State private var showingPaymentForm = false
    @State private var showingCompleteLoanConfirmation = false
    @State private var showingEditSheet = false
    @State private var loanCompletedTrigger = false
    
    private var loanSummary: LoanSummary? {
        viewModel.getLoanSummary(loan)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Loan Header
                loanHeaderCard
                
                // Quick Actions
                if loan.loanStatus == .active {
                    quickActionsCard
                }
                
                // Tab Selection
                Picker("View", selection: $selectedTab) {
                    Text("Overview").tag(0)
                    Text("Schedule").tag(1)
                    Text("Payments").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Tab Content
                tabContent
            }
            .padding(.vertical)
        }
        .navigationTitle("Loan Details")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Loan", systemImage: "pencil")
                    }
                    
                    if loan.loanStatus == .active {
                        Divider()
                        
                        Button {
                            showingCompleteLoanConfirmation = true
                        } label: {
                            Label("Mark as Complete", systemImage: "checkmark.circle")
                        }
                        .disabled(loan.balance > 0)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingPaymentForm) {
            PaymentFormView(
                viewModel: PaymentViewModel(),
                preselectedMember: loan.member,
                preselectedLoan: loan
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            EditLoanSheet(loan: loan)
        }
        .confirmationDialog(
            "Complete Loan",
            isPresented: $showingCompleteLoanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark as Complete") {
                viewModel.completeLoan(loan)
                loanCompletedTrigger.toggle()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will mark the loan as fully paid. This action cannot be undone.")
        }
        .sensoryFeedback(.success, trigger: loanCompletedTrigger)
        .onAppear {
            viewModel.selectLoan(loan)
        }
    }
    
    // MARK: - View Components
    
    private var loanHeaderCard: some View {
        VStack(spacing: 16) {
            // Member Info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loan.member?.name ?? "Unknown Member")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(loan.member?.memberRole.displayName ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                LoanStatusBadge(loan: loan)
            }
            
            // Loan Amount
            VStack(spacing: 8) {
                Text(CurrencyFormatter.shared.format(loan.amount))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                HStack {
                    Text("Issued on \(DateHelper.formatDate(loan.issueDate))")
                    if let dueDate = loan.dueDate {
                        Text("•")
                        Text("Due \(DateHelper.formatDate(dueDate))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            // Progress
            if loan.loanStatus == .active {
                VStack(spacing: 8) {
                    ProgressView(value: loan.completionPercentage, total: 100)
                        .tint(loan.isOverdue ? .red : Color.accentColor)
                        .scaleEffect(x: 1, y: 2)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paid")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.shared.format(loan.amount - loan.balance))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .center, spacing: 2) {
                            Text("\(Int(loan.completionPercentage))%")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.shared.format(loan.balance))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(loan.balance > 0 ? .orange : .green)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    private var quickActionsCard: some View {
        HStack(spacing: 12) {
            QuickActionButton(
                title: "Make Payment",
                icon: "dollarsign.circle.fill",
                color: .green
            ) {
                showingPaymentForm = true
            }
            
            QuickActionButton(
                title: "View Member",
                icon: "person.fill",
                color: .blue
            ) {
                if let memberID = loan.member?.memberID {
                    openMemberWindow(memberID)
                }
            }
            
            if loan.isOverdue {
                QuickActionButton(
                    title: "Send Reminder",
                    icon: "bell.fill",
                    color: .orange
                ) {
                    // TODO: Implement reminder
                }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            overviewTab
        case 1:
            scheduleTab
        case 2:
            paymentsTab
        default:
            EmptyView()
        }
    }
    
    // MARK: - Tab Views
    
    private var overviewTab: some View {
        VStack(spacing: 16) {
            // Loan Information
            LoanInfoCard(loan: loan)
            
            // Payment Summary
            if let summary = loanSummary {
                PaymentSummaryCard(summary: summary)
            }
            
            // Notes
            if let notes = loan.notes, !notes.isEmpty {
                NotesCard(notes: notes)
            }
        }
        .padding(.horizontal)
    }
    
    private var scheduleTab: some View {
        VStack(spacing: 16) {
            let schedule = FundCalculator.shared.calculateLoanSchedule(
                amount: loan.amount,
                months: Int(loan.repaymentMonths)
            )
            
            Text("Payment Schedule")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(Array(schedule.enumerated()), id: \.offset) { index, payment in
                PaymentScheduleRow(
                    payment: payment,
                    isPaid: payment.remainingBalance >= loan.balance
                )
            }
        }
        .padding(.horizontal)
    }
    
    private var paymentsTab: some View {
        VStack(spacing: 16) {
            let payments = viewModel.getLoanPayments(loan)
            
            if payments.isEmpty {
                ContentUnavailableView(
                    "No Payments",
                    systemImage: "dollarsign.circle",
                    description: Text("No payments have been made on this loan yet")
                )
                .frame(height: 200)
            } else {
                Text("Payment History")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                ForEach(payments) { payment in
                    PaymentHistoryRow(payment: payment)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

struct LoanStatusBadge: View {
    let loan: Loan
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text(statusText)
        }
        .font(.caption)
        .fontWeight(.medium)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private var statusIcon: String {
        if loan.loanStatus == .completed {
            return "checkmark.circle.fill"
        } else if loan.isOverdue {
            return "exclamationmark.triangle.fill"
        } else {
            return "circle.fill"
        }
    }
    
    private var statusText: String {
        if loan.loanStatus == .completed {
            return "Completed"
        } else if loan.isOverdue {
            return "Overdue"
        } else {
            return "Active"
        }
    }
    
    private var backgroundColor: Color {
        if loan.loanStatus == .completed {
            return .green.opacity(0.2)
        } else if loan.isOverdue {
            return .red.opacity(0.2)
        } else {
            return .blue.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        if loan.loanStatus == .completed {
            return .green
        } else if loan.isOverdue {
            return .red
        } else {
            return .blue
        }
    }
}

struct LoanInfoCard: View {
    let loan: Loan

    var body: some View {
        GroupBox("Loan Information") {
            InfoRow(label: "Loan Amount", value: CurrencyFormatter.shared.format(loan.amount))
            InfoRow(label: "Monthly Payment", value: CurrencyFormatter.shared.format(loan.monthlyPayment))
            InfoRow(label: "Repayment Period", value: "\(loan.repaymentMonths) months")
            InfoRow(label: "Issue Date", value: DateHelper.formatDate(loan.issueDate))

            if let dueDate = loan.dueDate {
                InfoRow(label: "Due Date", value: DateHelper.formatDate(dueDate))

                if loan.loanStatus == .active {
                    if loan.isOverdue {
                        InfoRow(
                            label: "Days Overdue",
                            value: "\(DateHelper.daysOverdue(dueDate)) days",
                            valueColor: .red
                        )
                    } else {
                        InfoRow(
                            label: "Days Until Due",
                            value: "\(DateHelper.daysUntilDue(dueDate)) days",
                            valueColor: .green
                        )
                    }
                }
            }
        }
    }
}

struct PaymentSummaryCard: View {
    let summary: LoanSummary

    var body: some View {
        GroupBox("Payment Summary") {
            InfoRow(label: "Total Paid", value: CurrencyFormatter.shared.format(summary.totalPaid))
            InfoRow(label: "Remaining Balance", value: CurrencyFormatter.shared.format(summary.remainingBalance))
            InfoRow(label: "Payments Made", value: "\(summary.paymentHistory.count)")
            InfoRow(label: "Remaining Payments", value: "\(summary.remainingPayments)")

            if let nextDue = summary.nextPaymentDue {
                Divider()
                LabeledContent("Next Payment Due") {
                    HStack(spacing: 8) {
                        DateHelper.paymentStatus(for: nextDue).color
                            .frame(width: 8, height: 8)
                            .clipShape(Circle())
                        Text(DateHelper.formatDate(nextDue))
                    }
                }
            }
        }
    }
}

struct NotesCard: View {
    let notes: String

    var body: some View {
        GroupBox("Notes") {
            Text(notes)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PaymentScheduleRow: View {
    let payment: LoanPaymentSchedule
    let isPaid: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Payment \(payment.paymentNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(DateHelper.formatDate(payment.dueDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.shared.format(payment.totalPayment))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Principal: \(CurrencyFormatter.shared.formatDecimal(payment.principalPayment))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Image(systemName: isPaid ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isPaid ? .green : .secondary)
                .font(.title3)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isPaid ? 0.6 : 1)
    }
}

struct PaymentHistoryRow: View {
    let payment: Payment
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateHelper.formatDate(payment.paymentDate))
                    .font(.subheadline)
                HStack {
                    Text(payment.paymentMethodType.displayName)
                    if payment.loanRepaymentAmount > 0 {
                        Text("•")
                        Text("Loan: \(CurrencyFormatter.shared.formatDecimal(payment.loanRepaymentAmount))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.shared.format(payment.amount))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
                
                if let notes = payment.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        LabeledContent(label) {
            Text(value).foregroundStyle(valueColor)
        }
        .font(.subheadline)
    }
}

// MARK: - Edit Loan Sheet

struct EditLoanSheet: View {
    @ObservedObject var loan: Loan
    @Environment(\.dismiss) private var dismiss
    @State private var loanAmount: String = ""
    @State private var loanBalance: String = ""
    @State private var repaymentMonths: Int = 3
    @State private var issueDate = Date()
    @State private var notes: String = ""
    @State private var loanStatus: LoanStatus = .active
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingRecalculateConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Loan Details") {
                    // Amount
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", text: $loanAmount)
                            .multilineTextAlignment(.trailing)
                        Text("KSH")
                            .foregroundStyle(.secondary)
                    }
                    
                    // Balance
                    HStack {
                        Text("Balance")
                        Spacer()
                        TextField("0", text: $loanBalance)
                            .multilineTextAlignment(.trailing)
                        Text("KSH")
                            .foregroundStyle(.secondary)
                    }
                    
                    // Repayment Period
                    Picker("Repayment Period", selection: $repaymentMonths) {
                        if loan.member?.memberRole == .securityGuard || loan.member?.memberRole == .partTime {
                            Text("6 Months").tag(6)
                        } else {
                            Text("3 Months").tag(3)
                            Text("4 Months").tag(4)
                        }
                    }
                    
                    // Issue Date
                    DatePicker("Issue Date", selection: $issueDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    
                    // Due Date (calculated)
                    HStack {
                        Text("Due Date")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(DateHelper.formatDate(calculateDueDate()))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Loan Status") {
                    Picker("Status", selection: $loanStatus) {
                        Text("Active").tag(LoanStatus.active)
                        Text("Completed").tag(LoanStatus.completed)
                    }

                    if loanStatus != loan.loanStatus {
                        if loanStatus == .active && loan.loanStatus == .completed {
                            Text("Reactivating this loan will allow further payments and tracking")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if loanStatus == .completed && loan.balance > 0 {
                            Text("Warning: This loan still has a balance of \(CurrencyFormatter.shared.format(loan.balance))")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                Section("Balance Management") {
                    Button {
                        showingRecalculateConfirmation = true
                    } label: {
                        Label("Recalculate Balance from Payments", systemImage: "arrow.clockwise")
                    }
                    .foregroundStyle(.blue)
                    
                    Text("This will recalculate the balance based on all loan payments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Current vs New Comparison
                Section("Changes") {
                    ComparisonRow(
                        label: "Amount",
                        current: CurrencyFormatter.shared.format(loan.amount),
                        new: CurrencyFormatter.shared.format(Double(loanAmount) ?? 0)
                    )
                    
                    ComparisonRow(
                        label: "Balance",
                        current: CurrencyFormatter.shared.format(loan.balance),
                        new: CurrencyFormatter.shared.format(Double(loanBalance) ?? 0)
                    )
                    
                    ComparisonRow(
                        label: "Monthly Payment",
                        current: CurrencyFormatter.shared.format(loan.monthlyPayment),
                        new: CurrencyFormatter.shared.format(calculateMonthlyPayment())
                    )
                    
                    ComparisonRow(
                        label: "Issue Date",
                        current: DateHelper.formatDate(loan.issueDate),
                        new: DateHelper.formatDate(issueDate)
                    )
                    
                    ComparisonRow(
                        label: "Due Date",
                        current: DateHelper.formatDate(loan.dueDate),
                        new: DateHelper.formatDate(calculateDueDate())
                    )

                    ComparisonRow(
                        label: "Status",
                        current: loan.loanStatus.displayName,
                        new: loanStatus.displayName
                    )
                }
            }
            .navigationTitle("Edit Loan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveLoanChanges()
                    }
                    .disabled(loanAmount.isEmpty || Double(loanAmount) == nil)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                setupInitialValues()
            }
            .confirmationDialog("Recalculate Balance", isPresented: $showingRecalculateConfirmation) {
                Button("Recalculate") {
                    recalculateBalance()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will update the balance based on all payments made for this loan. Continue?")
            }
        }
    }
    
    private func setupInitialValues() {
        loanAmount = String(Int(loan.amount))
        loanBalance = String(Int(loan.balance))
        repaymentMonths = Int(loan.repaymentMonths)
        issueDate = loan.issueDate ?? Date()
        notes = loan.notes ?? ""
        loanStatus = loan.loanStatus
    }
    
    private func calculateMonthlyPayment() -> Double {
        guard let amount = Double(loanAmount), amount > 0 else { return 0 }
        return amount / Double(repaymentMonths)
    }
    
    private func calculateDueDate() -> Date {
        return Calendar.current.date(byAdding: .month, value: repaymentMonths, to: issueDate) ?? issueDate
    }
    
    private func recalculateBalance() {
        DataManager.shared.recalculateLoanBalance(loan)
        loanBalance = String(Int(loan.balance))
    }
    
    private func saveLoanChanges() {
        guard let newAmount = Double(loanAmount), newAmount > 0 else {
            errorMessage = "Please enter a valid loan amount"
            showingError = true
            return
        }
        
        guard let newBalance = Double(loanBalance), newBalance >= 0 else {
            errorMessage = "Please enter a valid loan balance"
            showingError = true
            return
        }
        
        // Validate that balance is not greater than amount
        if newBalance > newAmount {
            errorMessage = "Loan balance cannot be greater than loan amount"
            showingError = true
            return
        }
        
        // Update loan properties
        loan.amount = newAmount
        loan.balance = newBalance
        loan.repaymentMonths = Int16(repaymentMonths)
        loan.monthlyPayment = calculateMonthlyPayment()
        loan.issueDate = issueDate
        loan.dueDate = calculateDueDate()
        loan.notes = notes.isEmpty ? nil : notes
        loan.updatedAt = Date()

        // Update loan status and completedDate
        if loanStatus != loan.loanStatus {
            loan.status = loanStatus.rawValue
            if loanStatus == .completed {
                loan.completedDate = Date()
            } else {
                // Reactivating the loan - clear completedDate
                loan.completedDate = nil
            }
        }

        // Save changes
        do {
            try loan.managedObjectContext?.save()
            // Notify DataManager to refresh loans
            DataManager.shared.fetchActiveLoans()
            DataManager.shared.fetchAllLoans()
            
            // Post notification that loan was updated
            NotificationCenter.default.post(name: .loanBalanceUpdated, object: loan)
            
            dismiss()
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct ComparisonRow: View {
    let label: String
    let current: String
    let new: String
    
    var hasChanged: Bool {
        current != new
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Text(current)
                    .font(.subheadline)
                
                if hasChanged {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(new)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LoanDetailView(loan: Loan(context: PersistenceController.preview.container.viewContext))
    }
}