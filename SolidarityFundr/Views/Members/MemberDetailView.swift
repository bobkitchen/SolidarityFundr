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
    @State private var selectedTab: DetailTab = .overview
    @State private var showingEditSheet = false
    @State private var showingCashOutConfirmation = false
    @State private var showingNewLoan = false
    @State private var showingNewPayment = false

    /// Pre-fill values for the loan-creation sheet, set by the eligibility
    /// card's "Issue Loan with these terms" button.
    @State private var newLoanPrefillAmount: Double?
    @State private var newLoanPrefillMonths: Int?

    enum DetailTab: String, CaseIterable, Hashable {
        case overview = "Overview"
        case contributions = "Contributions"
        case loans = "Loans"
        case transactions = "Transactions"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                memberHeaderCard
                quickActionsCard

                Picker("View", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                tabContent
            }
            .padding(.vertical)
        }
        .navigationTitle(member.name ?? "Member Details")
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
        .sheet(isPresented: $showingNewLoan, onDismiss: {
            newLoanPrefillAmount = nil
            newLoanPrefillMonths = nil
        }) {
            NewLoanSheet(
                preselectedMember: member,
                preselectedAmount: newLoanPrefillAmount,
                preselectedMonths: newLoanPrefillMonths
            )
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
        // No refreshID hack: @ObservedObject member already publishes
        // changes for KVO-backed Core Data properties, and the eligibility
        // card observes DataManager directly, so adding a payment elsewhere
        // updates this view without manual invalidation.
    }

    // MARK: - View Components

    /// Identity-only header. Financial summary and contribution counts
    /// live in the Overview tab so they're not duplicated.
    private var memberHeaderCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 64, height: 64)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BrandColor.avatarTint(for: member.name))
                .accessibilityHidden(true)

            Text(member.name ?? "Unknown")
                .font(.title2.weight(.semibold))

            HStack(spacing: 8) {
                Label(member.memberRole.displayName, systemImage: "briefcase.fill")
                    .labelStyle(.titleAndIcon)
                if member.memberStatus != .active {
                    Text("•")
                    StatusBadge(status: member.memberStatus)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let joinDate = member.joinDate {
                Text("Member since \(DateHelper.formatDate(joinDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
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
                    newLoanPrefillAmount = nil
                    newLoanPrefillMonths = nil
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
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:      overviewTab
        case .contributions: contributionsTab
        case .loans:         loansTab
        case .transactions:  transactionsTab
        }
    }
    
    // MARK: - Tab Views
    
    private var overviewTab: some View {
        VStack(spacing: 16) {
            if member.email != nil || member.phoneNumber != nil {
                ContactInfoCard(member: member)
            }

            FinancialSummaryCard(member: member)

            LoanEligibilityCard(member: member) { amount, months in
                newLoanPrefillAmount = amount
                newLoanPrefillMonths = months
                showingNewLoan = true
            }
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
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct ContactInfoCard: View {
    let member: Member

    var body: some View {
        GroupBox("Contact Information") {
            if let email = member.email {
                LabeledContent("Email") {
                    Text(email).foregroundStyle(.secondary)
                }
            }
            if let phone = member.phoneNumber {
                LabeledContent("Phone") {
                    HStack(spacing: 8) {
                        Text(phone).foregroundStyle(.secondary)
                        if PhoneNumberValidator.validate(phone) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
            }

            Divider()

            LabeledContent("SMS Notifications") {
                let enabled = member.smsOptIn && member.phoneNumber != nil
                    && PhoneNumberValidator.validate(member.phoneNumber!)
                Text(enabled ? "Enabled" : "Disabled")
                    .foregroundStyle(enabled ? .green : .secondary)
            }

            if let lastSent = member.lastStatementSentDate {
                LabeledContent("Last Statement Sent") {
                    Text(DateHelper.formatDate(lastSent))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct FinancialSummaryCard: View {
    let member: Member

    var body: some View {
        GroupBox("Financial Summary") {
            LabeledContent("Total Contributions") {
                Text(CurrencyFormatter.shared.format(member.totalContributions))
            }
            LabeledContent("Active Loans") {
                Text(CurrencyFormatter.shared.format(member.totalActiveLoanBalance))
                    .foregroundStyle(member.hasActiveLoans ? .orange : .primary)
            }
            LabeledContent("Available Balance") {
                Text(CurrencyFormatter.shared.format(member.availableContributions))
                    .foregroundStyle(.green)
            }
            if member.cashOutAmount > 0 {
                Divider()
                LabeledContent("Cash Out Amount") {
                    Text(CurrencyFormatter.shared.format(member.cashOutAmount))
                }
            }
        }
    }
}

/// Live loan calculator. Shows the maximum amount this member could
/// borrow right now (against role limit, fund headroom, and utilization
/// threshold) and lets the admin try a specific amount + repayment-month
/// combination to see the resulting monthly payment and fund-utilization
/// impact. Recomputes on every dataManager publish, so adding a payment
/// elsewhere updates the numbers next time you land on this page.
struct LoanEligibilityCard: View {
    let member: Member
    /// Called when the admin taps "Issue Loan with these terms" — the
    /// parent view (MemberDetailView) opens the loan-creation sheet
    /// pre-filled with `(amount, months)`. Optional so the card can also
    /// be used as a read-only summary elsewhere.
    var onIssueLoan: ((Double, Int) -> Void)? = nil
    @EnvironmentObject private var dataManager: DataManager

    @State private var proposedAmount: Double = 0
    @State private var proposedMonths: Int = 3
    @State private var didInitialise = false

    private var settings: FundSettings? { dataManager.fundSettings }

    private var eligibility: LoanEligibility? {
        guard let settings else { return nil }
        return LoanEligibility.compute(
            member: member,
            settings: settings,
            proposedAmount: proposedAmount > 0 ? proposedAmount : nil,
            proposedMonths: proposedMonths
        )
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if let eligibility {
                    if eligibility.isEligible {
                        eligibleBody(eligibility)
                    } else {
                        blockedBody(eligibility)
                    }
                } else {
                    Text("Fund settings unavailable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack {
                Text("Loan Eligibility")
                Spacer()
                eligibilityBadge
            }
        }
        .onAppear { initialiseIfNeeded() }
        .onChange(of: member.objectID) { _, _ in
            didInitialise = false
            initialiseIfNeeded()
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var eligibilityBadge: some View {
        if let e = eligibility {
            if !e.isEligible {
                Label("Blocked", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !e.warnings.isEmpty || (e.preview?.exceedsWarningThreshold == true) {
                Label("Caution", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label("Eligible", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private func eligibleBody(_ e: LoanEligibility) -> some View {
        // Max available — the headline number.
        HStack(alignment: .firstTextBaseline) {
            Text("Available now")
                .foregroundStyle(.secondary)
            Spacer()
            Text(CurrencyFormatter.shared.format(e.effectiveMax))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }

        // Show which constraint is binding, so the admin understands *why*
        // the available number is what it is.
        if e.effectiveMax > 0 {
            Text(bindingConstraintExplanation(e))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        // Calculator: amount + months → monthly payment + utilization impact.
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Try amount")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("Amount", value: $proposedAmount, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                Text("KSH").foregroundStyle(.secondary)
            }

            if e.allowedRepaymentMonths.count > 1 {
                Picker("Repay over", selection: $proposedMonths) {
                    ForEach(e.allowedRepaymentMonths, id: \.self) { months in
                        Text("\(months) months").tag(months)
                    }
                }
                .pickerStyle(.segmented)
            } else if let only = e.allowedRepaymentMonths.first {
                LabeledContent("Repay over") {
                    Text("\(only) months").foregroundStyle(.secondary)
                }
            }

            if let preview = e.preview, preview.amount > 0 {
                LabeledContent("Monthly payment") {
                    Text(CurrencyFormatter.shared.format(preview.monthlyPayment))
                        .monospacedDigit()
                        .fontWeight(.medium)
                }

                LabeledContent("Fund utilization") {
                    HStack(spacing: 4) {
                        Text(percentString(preview.utilizationBefore))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(percentString(preview.utilizationAfter))
                            .monospacedDigit()
                            .foregroundStyle(preview.exceedsWarningThreshold ? .red : .primary)
                    }
                }
            }
        }

        // Warnings, if any.
        if !e.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(e.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }

        // Issue Loan with these terms — only present if the parent gave
        // us a callback. Pre-fills the loan-creation sheet so the admin
        // doesn't re-enter what they just dialled in.
        if let onIssueLoan, let preview = e.preview, preview.amount > 0 {
            Button {
                onIssueLoan(preview.amount, preview.months)
            } label: {
                Label("Issue Loan with these terms", systemImage: "creditcard.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func blockedBody(_ e: LoanEligibility) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(e.blockingReasons, id: \.self) { reason in
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    // MARK: - Helpers

    private func initialiseIfNeeded() {
        guard !didInitialise, let e = eligibility else { return }
        proposedAmount = e.effectiveMax
        if let first = e.allowedRepaymentMonths.first(where: { $0 == proposedMonths })
            ?? e.allowedRepaymentMonths.first {
            proposedMonths = first
        }
        didInitialise = true
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func bindingConstraintExplanation(_ e: LoanEligibility) -> String {
        // Tell the admin which limit is currently the binding one.
        let m = e.memberMaxAmount
        let f = e.fundHeadroom
        let u = e.utilizationCeiling
        let effective = e.effectiveMax
        if effective == m {
            return "Bound by member's role limit and existing balance."
        } else if effective == f {
            return "Bound by fund minimum-balance buffer."
        } else if effective == u {
            return "Bound by utilization warning threshold."
        }
        return ""
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
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(CurrencyFormatter.shared.format(payment.contributionAmount))
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
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                
                if loan.isOverdue {
                    Label("Payment overdue", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Completed on \(DateHelper.formatDate(loan.completedDate))")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(transaction.displayAmount)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(transaction.transactionType.isCredit ? .green : .red)
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                            .foregroundStyle(.red)
                    }
                    
                    Toggle("SMS Notifications", isOn: $smsOptIn)
                        .disabled(phone.isEmpty || !PhoneNumberValidator.validate(phone))
                    
                    if smsOptIn && PhoneNumberValidator.validate(phone) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            Text("Member will receive monthly statements via SMS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(CurrencyFormatter.shared.format(standardLimitForRole(role)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Custom Repayment Terms", isOn: $hasCustomRepaymentTerms)

                    if hasCustomRepaymentTerms {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Allowed repayment periods:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

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
                                .foregroundStyle(.secondary)
                            TextField("e.g., Board approved exception", text: $overrideReason)
                                .textFieldStyle(.roundedBorder)
                        }

                        if member.overrideApprovedDate != nil {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.blue)
                                Text("Override approved: \(member.overrideApprovedDate!, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Loan Override Settings")
                        Image(systemName: "exclamationmark.shield")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Override settings allow this member to borrow beyond standard limits or use different repayment periods.")
                        .font(.caption)
                }
            }
            .navigationTitle("Edit Member")
            .interactiveDismissDisabled(hasUnsavedChanges)
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

    private var hasUnsavedChanges: Bool {
        name != (member.name ?? "") ||
        role != member.memberRole ||
        email != (member.email ?? "") ||
        phone != (member.phoneNumber ?? "") ||
        smsOptIn != member.smsOptIn ||
        joinDate != (member.joinDate ?? Date()) ||
        hasCustomLoanLimit != (member.customLoanLimit > 0) ||
        hasCustomRepaymentTerms != (member.customRepaymentMonths != nil && !(member.customRepaymentMonths ?? "").isEmpty) ||
        overrideReason != (member.overrideReason ?? "")
    }

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

#Preview {
    NavigationStack {
        MemberDetailView(member: Member(context: PersistenceController.preview.container.viewContext))
    }
}