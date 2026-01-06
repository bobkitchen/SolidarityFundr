//
//  MemberDetailView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI
import Charts

struct MemberDetailView: View {
    @ObservedObject var member: Member
    @StateObject private var viewModel = MemberViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openLoanWindow) private var openLoanWindow
    @State private var selectedTab = 0
    @State private var showingEditSheet = false
    @State private var showingCashOutConfirmation = false
    @State private var showingNewLoan = false
    @State private var showingNewPayment = false
    @State private var refreshID = UUID()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Card
                memberHeaderCard
                
                // Quick Actions
                quickActionsCard
                
                // Tab Selection
                Picker("View", selection: $selectedTab) {
                    Text("Overview").tag(0)
                    Text("Contributions").tag(1)
                    Text("Loans").tag(2)
                    Text("Transactions").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Tab Content
                tabContent
            }
            .padding(.vertical)
        }
        .navigationTitle("Member Details")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Member", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    if member.memberStatus == .active {
                        Button {
                            viewModel.suspendMember(member)
                        } label: {
                            Label("Suspend Member", systemImage: "pause.circle")
                        }
                    } else if member.memberStatus == .suspended {
                        Button {
                            viewModel.reactivateMember(member)
                        } label: {
                            Label("Reactivate Member", systemImage: "play.circle")
                        }
                    }
                    
                    if member.memberStatus != .active && !member.hasActiveLoans {
                        Button {
                            showingCashOutConfirmation = true
                        } label: {
                            Label("Cash Out", systemImage: "banknote")
                        }
                    }
                    
                    if viewModel.canDeleteMember(member) {
                        Divider()
                        Button(role: .destructive) {
                            viewModel.confirmDelete(for: member)
                        } label: {
                            Label("Delete Member", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditMemberSheet(member: member, viewModel: viewModel)
        }
        .sheet(isPresented: $showingNewLoan) {
            MemberNewLoanSheet(preselectedMember: member)
        }
        .sheet(isPresented: $showingNewPayment) {
            PaymentFormView(
                viewModel: PaymentViewModel(),
                preselectedMember: member
            )
        }
        .confirmationDialog(
            "Cash Out Member",
            isPresented: $showingCashOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Confirm Cash Out") {
                viewModel.cashOutMember(member)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let amount = FundCalculator.shared.calculateMemberCashOut(member: member)
            Text("This will cash out \(CurrencyFormatter.shared.format(amount)) including interest. This action cannot be undone.")
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
        .onReceive(NotificationCenter.default.publisher(for: .memberDataUpdated)) { notification in
            if let updatedMember = notification.object as? Member,
               updatedMember.objectID == member.objectID {
                // Force refresh when this member's data is updated
                refreshID = UUID()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .paymentSaved)) { _ in
            // Force refresh when any payment is saved
            refreshID = UUID()
        }
        .id(refreshID)
    }
    
    // MARK: - View Components
    
    private var memberHeaderCard: some View {
        VStack(spacing: 16) {
            // Member Avatar
            Circle()
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay(
                    Text(member.name?.prefix(2).uppercased() ?? "??")
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                )
            
            // Member Info
            VStack(spacing: 8) {
                Text(member.name ?? "Unknown")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack {
                    Label(member.memberRole.displayName, systemImage: "briefcase.fill")
                    
                    if member.memberStatus != .active {
                        Text("•")
                        StatusBadge(status: member.memberStatus)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                if let joinDate = member.joinDate {
                    Text("Member since \(DateHelper.formatDate(joinDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Key Statistics
            HStack(spacing: 30) {
                StatisticItem(
                    value: CurrencyFormatter.shared.format(member.totalContributions),
                    label: "Total Contributions"
                )
                
                StatisticItem(
                    value: "\(member.monthsAsMember)",
                    label: "Months Active"
                )
                
                StatisticItem(
                    value: CurrencyFormatter.shared.format(member.totalActiveLoanBalance),
                    label: "Active Loans"
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var quickActionsCard: some View {
        HStack(spacing: 12) {
            if member.isEligibleForLoan {
                QuickActionButton(
                    title: "New Loan",
                    icon: "creditcard.fill",
                    color: .blue
                ) {
                    showingNewLoan = true
                }
            }
            
            QuickActionButton(
                title: "Make Payment",
                icon: "dollarsign.circle.fill",
                color: .green
            ) {
                showingNewPayment = true
            }
            
            QuickActionButton(
                title: "Export Report",
                icon: "doc.text.fill",
                color: .purple
            ) {
                // TODO: Implement export
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
            contributionsTab
        case 2:
            loansTab
        case 3:
            transactionsTab
        default:
            EmptyView()
        }
    }
    
    // MARK: - Tab Views
    
    private var overviewTab: some View {
        VStack(spacing: 16) {
            // Contact Information
            if member.email != nil || member.phoneNumber != nil {
                ContactInfoCard(member: member)
            }
            
            // Financial Summary
            FinancialSummaryCard(member: member)
            
            // Loan Eligibility
            LoanEligibilityCard(member: member)
        }
        .padding(.horizontal)
    }
    
    private var contributionsTab: some View {
        VStack(spacing: 16) {
            // Contribution Chart
            if !viewModel.getMemberContributions(for: member).isEmpty {
                ContributionChartCard(
                    contributions: viewModel.getMemberContributions(for: member)
                )
            }
            
            // Contribution History
            ContributionHistoryList(member: member)
        }
        .padding(.horizontal)
    }
    
    private var loansTab: some View {
        VStack(spacing: 16) {
            let loans = viewModel.getMemberLoanHistory(for: member)

            if loans.isEmpty {
                ContentUnavailableView(
                    "No Loans",
                    systemImage: "creditcard.fill",
                    description: Text("This member has not taken any loans yet")
                )
                .frame(height: 200)
            } else {
                ForEach(loans) { loan in
                    Button {
                        if let loanID = loan.loanID {
                            openLoanWindow(loanID)
                        }
                    } label: {
                        LoanCard(loan: loan)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var transactionsTab: some View {
        VStack(spacing: 16) {
            let transactions = member.transactions?.allObjects as? [Transaction] ?? []
            let sortedTransactions = transactions.sorted {
                ($0.transactionDate ?? Date()) > ($1.transactionDate ?? Date())
            }
            
            if sortedTransactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "list.bullet.rectangle",
                    description: Text("No transactions recorded yet")
                )
                .frame(height: 200)
            } else {
                ForEach(sortedTransactions.prefix(50)) { transaction in
                    TransactionRow(transaction: transaction)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views

struct StatisticItem: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(10)
        }
    }
}

struct ContactInfoCard: View {
    let member: Member
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contact Information")
                .font(.headline)
            
            if let email = member.email {
                Label(email, systemImage: "envelope.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let phone = member.phoneNumber {
                HStack {
                    Label(phone, systemImage: "phone.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if PhoneNumberValidator.validate(phone) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Label("SMS Notifications", systemImage: "message.fill")
                    .font(.subheadline)
                
                Spacer()
                
                if member.smsOptIn && member.phoneNumber != nil && PhoneNumberValidator.validate(member.phoneNumber!) {
                    Text("Enabled")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                } else {
                    Text("Disabled")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.gray)
                        .cornerRadius(4)
                }
            }
            
            if let lastSent = member.lastStatementSentDate {
                HStack {
                    Text("Last Statement Sent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(DateHelper.formatDate(lastSent))
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

struct FinancialSummaryCard: View {
    let member: Member
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Financial Summary")
                .font(.headline)
            
            HStack {
                Text("Total Contributions")
                    .foregroundColor(.secondary)
                Spacer()
                Text(CurrencyFormatter.shared.format(member.totalContributions))
                    .fontWeight(.medium)
            }
            
            HStack {
                Text("Active Loans")
                    .foregroundColor(.secondary)
                Spacer()
                Text(CurrencyFormatter.shared.format(member.totalActiveLoanBalance))
                    .fontWeight(.medium)
                    .foregroundColor(member.hasActiveLoans ? .orange : .primary)
            }
            
            HStack {
                Text("Available Balance")
                    .foregroundColor(.secondary)
                Spacer()
                Text(CurrencyFormatter.shared.format(member.availableContributions))
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
            
            if member.cashOutAmount > 0 {
                Divider()
                HStack {
                    Text("Cash Out Amount")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(member.cashOutAmount))
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct LoanEligibilityCard: View {
    let member: Member
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loan Eligibility")
                .font(.headline)
            
            if member.isEligibleForLoan {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Eligible for loans")
                        .foregroundColor(.green)
                    Spacer()
                }
                
                HStack {
                    Text("Maximum Loan Amount")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(CurrencyFormatter.shared.format(member.maximumLoanAmount))
                        .fontWeight(.medium)
                }
            } else {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(eligibilityReason)
                        .foregroundColor(.red)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var eligibilityReason: String {
        if member.memberStatus != .active {
            return "Member is not active"
        } else if member.memberRole == .securityGuard && member.monthsAsMember < 3 {
            return "Guards need 3 months of contributions"
        } else {
            return "Not eligible for loans"
        }
    }
}

struct ContributionChartCard: View {
    let contributions: [MonthlyContribution]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contribution History")
                .font(.headline)
            
            Chart(contributions.suffix(12), id: \.monthKey) { contribution in
                BarMark(
                    x: .value("Month", contribution.displayMonth),
                    y: .value("Amount", contribution.amount)
                )
                .foregroundStyle(Color.accentColor)
            }
            .frame(height: 200)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct ContributionHistoryList: View {
    let member: Member
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Contributions")
                .font(.headline)
            
            let payments = (member.payments?.allObjects as? [Payment] ?? [])
                .filter { $0.contributionAmount > 0 }
                .sorted { ($0.paymentDate ?? Date()) > ($1.paymentDate ?? Date()) }
                .prefix(10)
            
            ForEach(payments) { payment in
                HStack {
                    VStack(alignment: .leading) {
                        Text(DateHelper.formatDate(payment.paymentDate))
                            .font(.subheadline)
                        Text(payment.paymentMethodType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(CurrencyFormatter.shared.format(payment.contributionAmount))
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

struct LoanCard: View {
    let loan: Loan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CurrencyFormatter.shared.format(loan.amount))
                        .font(.headline)
                    Text("Issued \(DateHelper.formatDate(loan.issueDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                StatusBadge(status: loan.loanStatus == .active ? .active : .inactive)
            }
            
            if loan.loanStatus == .active {
                ProgressView(value: loan.completionPercentage, total: 100)
                    .tint(.accentColor)
                
                HStack {
                    Text("Remaining: \(CurrencyFormatter.shared.format(loan.balance))")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(loan.completionPercentage))% paid")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                if loan.isOverdue {
                    Label("Payment overdue", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Completed on \(DateHelper.formatDate(loan.completedDate))")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.transactionType.displayName)
                    .font(.subheadline)
                Text(DateHelper.formatDate(transaction.transactionDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(transaction.displayAmount)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(transaction.transactionType.isCredit ? .green : .red)
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Edit Member Sheet

struct EditMemberSheet: View {
    @ObservedObject var member: Member
    @ObservedObject var viewModel: MemberViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var role: MemberRole = .partTime
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var joinDate = Date()
    @State private var smsOptIn: Bool = false
    @State private var showingPhoneError = false

    // Custom override fields
    @State private var hasCustomLoanLimit: Bool = false
    @State private var customLoanLimitString: String = ""
    @State private var hasCustomRepaymentTerms: Bool = false
    @State private var allowedRepaymentMonths: Set<Int> = []
    @State private var overrideReason: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Member Information") {
                    TextField("Full Name", text: $name)
                        .textContentType(.name)
                    
                    Picker("Role", selection: $role) {
                        ForEach(MemberRole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                }
                
                Section("Contact Information") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        #endif
                    
                    HStack {
                        TextField("Phone Number", text: $phone)
                            .textContentType(.telephoneNumber)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                        
                        if !phone.isEmpty {
                            Image(systemName: PhoneNumberValidator.validate(phone) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(PhoneNumberValidator.validate(phone) ? .green : .red)
                        }
                    }
                    
                    if !phone.isEmpty && !PhoneNumberValidator.validate(phone) {
                        Text("Please enter a valid Kenyan phone number")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Toggle("SMS Notifications", isOn: $smsOptIn)
                        .disabled(phone.isEmpty || !PhoneNumberValidator.validate(phone))
                    
                    if smsOptIn && PhoneNumberValidator.validate(phone) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Member will receive monthly statements via SMS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Employment Details") {
                    DatePicker("Start Date", selection: $joinDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                // Loan Override Settings Section
                Section {
                    Toggle("Custom Loan Limit", isOn: $hasCustomLoanLimit)

                    if hasCustomLoanLimit {
                        HStack {
                            Text("KSH")
                            TextField("Amount", text: $customLoanLimitString)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                        }

                        // Show default limit for reference
                        HStack {
                            Text("Standard limit for \(role.displayName):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(CurrencyFormatter.shared.format(standardLimitForRole(role)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("Custom Repayment Terms", isOn: $hasCustomRepaymentTerms)

                    if hasCustomRepaymentTerms {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Allowed repayment periods:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                ForEach([3, 4, 6], id: \.self) { months in
                                    Toggle("\(months) mo", isOn: Binding(
                                        get: { allowedRepaymentMonths.contains(months) },
                                        set: { isOn in
                                            if isOn {
                                                allowedRepaymentMonths.insert(months)
                                            } else {
                                                allowedRepaymentMonths.remove(months)
                                            }
                                        }
                                    ))
                                    .toggleStyle(.button)
                                    .buttonStyle(.bordered)
                                    .tint(allowedRepaymentMonths.contains(months) ? .blue : .secondary)
                                }
                            }
                        }
                    }

                    if hasCustomLoanLimit || hasCustomRepaymentTerms {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reason for override:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("e.g., Board approved exception", text: $overrideReason)
                                .textFieldStyle(.roundedBorder)
                        }

                        if member.overrideApprovedDate != nil {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.blue)
                                Text("Override approved: \(member.overrideApprovedDate!, style: .date)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Loan Override Settings")
                        Image(systemName: "exclamationmark.shield")
                            .foregroundColor(.orange)
                    }
                } footer: {
                    Text("Override settings allow this member to borrow beyond standard limits or use different repayment periods.")
                        .font(.caption)
                }
            }
            .navigationTitle("Edit Member")
                .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        member.name = name
                        member.memberRole = role
                        member.email = email.isEmpty ? nil : email
                        member.phoneNumber = phone.isEmpty ? nil : phone
                        member.smsOptIn = smsOptIn && PhoneNumberValidator.validate(phone)
                        member.joinDate = joinDate

                        // Save override settings
                        if hasCustomLoanLimit, let limit = Double(customLoanLimitString), limit > 0 {
                            member.customLoanLimit = limit
                        } else {
                            member.customLoanLimit = 0
                        }

                        if hasCustomRepaymentTerms && !allowedRepaymentMonths.isEmpty {
                            member.customRepaymentMonths = allowedRepaymentMonths.sorted().map { String($0) }.joined(separator: ",")
                        } else {
                            member.customRepaymentMonths = nil
                        }

                        if hasCustomLoanLimit || hasCustomRepaymentTerms {
                            member.overrideReason = overrideReason.isEmpty ? nil : overrideReason
                            if member.overrideApprovedDate == nil {
                                member.overrideApprovedDate = Date()
                            }
                        } else {
                            member.overrideReason = nil
                            member.overrideApprovedDate = nil
                        }

                        viewModel.updateMember()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
        .onAppear {
            name = member.name ?? ""
            role = member.memberRole
            email = member.email ?? ""
            phone = member.phoneNumber ?? ""
            smsOptIn = member.smsOptIn
            joinDate = member.joinDate ?? Date()

            // Load override settings
            hasCustomLoanLimit = member.customLoanLimit > 0
            customLoanLimitString = member.customLoanLimit > 0 ? String(Int(member.customLoanLimit)) : ""

            if let customMonths = member.customRepaymentMonths, !customMonths.isEmpty {
                hasCustomRepaymentTerms = true
                allowedRepaymentMonths = Set(customMonths.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
            } else {
                hasCustomRepaymentTerms = false
                allowedRepaymentMonths = []
            }

            overrideReason = member.overrideReason ?? ""
        }
    }

    // Helper function to get standard loan limit for a role
    private func standardLimitForRole(_ role: MemberRole) -> Double {
        switch role {
        case .driver, .assistant:
            return 40000
        case .housekeeper, .groundsKeeper:
            return 19000
        case .securityGuard, .partTime:
            return 10000
        }
    }
}

// MARK: - Placeholder Views

struct MemberNewLoanSheet: View {
    let preselectedMember: Member?
    
    var body: some View {
        NavigationStack {
            Text("New Loan Form - To be implemented")
                .navigationTitle("New Loan")
        }
    }
}

#Preview {
    NavigationStack {
        MemberDetailView(member: Member(context: PersistenceController.preview.container.viewContext))
    }
}