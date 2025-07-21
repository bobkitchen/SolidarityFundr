//
//  PaymentFormView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI

struct PaymentFormView: View {
    @ObservedObject var viewModel: PaymentViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    
    let preselectedMember: Member?
    let preselectedLoan: Loan?
    let editingPayment: Payment?
    
    enum Field {
        case amount
    }
    
    init(viewModel: PaymentViewModel, 
         preselectedMember: Member? = nil, 
         preselectedLoan: Loan? = nil,
         editingPayment: Payment? = nil) {
        print("🔧 PaymentFormView: init - editingPayment: \(editingPayment?.member?.name ?? "nil")")
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.preselectedMember = preselectedMember
        self.preselectedLoan = preselectedLoan
        self.editingPayment = editingPayment
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Member Selection
                memberSection
                
                // Payment Type
                if viewModel.selectedMember != nil {
                    paymentTypeSection
                }
                
                // Payment Details
                if viewModel.selectedMember != nil {
                    paymentDetailsSection
                }
                
                // Payment Breakdown
                if !viewModel.paymentAmount.isEmpty && Double(viewModel.paymentAmount) ?? 0 > 0 {
                    paymentBreakdownSection
                }
                
                // Notes
                notesSection
                
                // Warnings
                if !viewModel.validationWarnings.isEmpty {
                    warningsSection
                }
            }
            .navigationTitle(viewModel.isEditMode ? "Edit Payment" : "New Payment")
            .toolbar {
                toolbarContent
            }
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .onAppear {
                setupInitialState()
            }
            .onChange(of: editingPayment) { newPayment in
                if let payment = newPayment {
                    viewModel.loadPaymentForEditing(payment)
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var memberSection: some View {
        Section("Member") {
            if viewModel.isEditMode, let member = viewModel.selectedMember {
                // In edit mode, show the selected member (read-only)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.name ?? "Unknown")
                            .font(.headline)
                        HStack {
                            Text(member.memberRole.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if member.hasActiveLoans {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Label("Has active loan", systemImage: "creditcard.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(CurrencyFormatter.shared.format(member.totalContributions))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.vertical, 4)
            } else if let preselectedMember = preselectedMember {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preselectedMember.name ?? "Unknown")
                            .font(.headline)
                        HStack {
                            Text(preselectedMember.memberRole.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if preselectedMember.hasActiveLoans {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Label("Has active loan", systemImage: "creditcard.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(CurrencyFormatter.shared.format(preselectedMember.totalContributions))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Picker("Select Member", selection: $viewModel.selectedMember) {
                    Text("Choose a member").tag(nil as Member?)
                    ForEach(DataManager.shared.members.sorted { $0.name ?? "" < $1.name ?? "" }) { member in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(member.name ?? "")
                                if member.hasActiveLoans {
                                    Text("Has active loan")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            Spacer()
                            
                            if member.memberStatus != .active {
                                StatusBadge(status: member.memberStatus)
                            }
                        }
                        .tag(member as Member?)
                    }
                }
            }
        }
    }
    
    private var paymentTypeSection: some View {
        Section("Payment Type") {
            if let member = viewModel.selectedMember, member.hasActiveLoans {
                Picker("Payment Type", selection: $viewModel.isLoanPayment) {
                    Text("Monthly Contribution").tag(false)
                    Text("Loan Repayment").tag(true)
                }
                .pickerStyle(.segmented)
                
                if viewModel.isLoanPayment {
                    let activeLoans = member.activeLoans
                    if activeLoans.count == 1 {
                        // Single loan - auto-selected
                        if let loan = activeLoans.first {
                            LoanInfoRow(loan: loan)
                        }
                    } else if activeLoans.count > 1 {
                        // Multiple loans - picker
                        Picker("Select Loan", selection: $viewModel.selectedLoan) {
                            Text("Choose a loan").tag(nil as Loan?)
                            ForEach(activeLoans) { loan in
                                HStack {
                                    Text(CurrencyFormatter.shared.format(loan.amount))
                                    Spacer()
                                    Text("Balance: \(CurrencyFormatter.shared.format(loan.balance))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .tag(loan as Loan?)
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Monthly Contribution")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var paymentDetailsSection: some View {
        Section("Payment Details") {
            // Amount
            HStack {
                Text("Amount")
                Spacer()
                TextField("0", text: $viewModel.paymentAmount)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .amount)
                Text("KSH")
                    .foregroundColor(.secondary)
            }
            
            // Payment Method
            Picker("Payment Method", selection: $viewModel.paymentMethod) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    Text(method.displayName).tag(method)
                }
            }
            
            // Date picker
            DatePicker("Date", selection: $viewModel.paymentDate, displayedComponents: .date)
                .datePickerStyle(.compact)
        }
    }
    
    private var paymentBreakdownSection: some View {
        Section("Payment Breakdown") {
            if viewModel.isLoanPayment {
                HStack {
                    Label("Loan Repayment", systemImage: "creditcard.fill")
                        .foregroundColor(.orange)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(Double(viewModel.paymentAmount) ?? 0))
                        .fontWeight(.medium)
                }
                
                Text("Monthly contributions should be paid separately")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Show remaining balance after payment
                if let loan = viewModel.selectedLoan {
                    let paymentAmount = Double(viewModel.paymentAmount) ?? 0
                    let remainingBalance = max(0, loan.balance - paymentAmount)
                    HStack {
                        Text("Remaining Loan Balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(CurrencyFormatter.shared.format(remainingBalance))
                            .font(.caption)
                            .foregroundColor(remainingBalance > 0 ? .orange : .green)
                    }
                }
            } else {
                HStack {
                    Label("Monthly Contribution", systemImage: "banknote.fill")
                        .foregroundColor(.green)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(viewModel.contributionAmount))
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    private var notesSection: some View {
        Section("Notes (Optional)") {
            TextEditor(text: $viewModel.paymentNotes)
                .frame(minHeight: 60)
        }
    }
    
    private var warningsSection: some View {
        Section {
            ForEach(viewModel.validationWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
    }
    
    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    processPayment()
                }
                .disabled(!canSavePayment)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupInitialState() {
        print("🔧 PaymentFormView: setupInitialState - editingPayment: \(editingPayment != nil)")
        
        // Check if we have an editing payment to load
        if let payment = editingPayment {
            // Load payment for editing
            print("🔧 PaymentFormView: Loading payment for editing - \(payment.member?.name ?? "Unknown")")
            viewModel.loadPaymentForEditing(payment)
        } else if !viewModel.isEditMode {
            // New payment setup only if not already in edit mode
            print("🔧 PaymentFormView: Setting up new payment")
            if let member = preselectedMember {
                viewModel.selectedMember = member
            }
            
            if let loan = preselectedLoan {
                viewModel.selectedLoan = loan
                viewModel.isLoanPayment = true
            }
        }
        
        // Focus on amount field after a slight delay for new payments only
        if editingPayment == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .amount
            }
        }
    }
    
    private func processPayment() {
        if viewModel.isEditMode {
            viewModel.updatePayment()
        } else {
            viewModel.processPayment()
        }
        
        if !viewModel.showingError {
            dismiss()
        }
    }
    
    private var canSavePayment: Bool {
        guard viewModel.selectedMember != nil,
              !viewModel.paymentAmount.isEmpty,
              Double(viewModel.paymentAmount) ?? 0 > 0 else {
            return false
        }
        
        if viewModel.isLoanPayment && viewModel.selectedLoan == nil {
            return false
        }
        
        return true
    }
}

// MARK: - Supporting Views

struct LoanInfoRow: View {
    let loan: Loan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loan Amount: \(CurrencyFormatter.shared.format(loan.amount))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Issued \(DateHelper.formatDate(loan.issueDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if loan.isOverdue {
                    Label("Overdue", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Progress
            VStack(spacing: 4) {
                ProgressView(value: loan.completionPercentage, total: 100)
                    .tint(loan.isOverdue ? .red : .accentColor)
                
                HStack {
                    Text("Balance: \(CurrencyFormatter.shared.format(loan.balance))")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(loan.completionPercentage))% paid")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

#Preview {
    PaymentFormView(viewModel: PaymentViewModel())
        .environmentObject(DataManager.shared)
}