//
//  MemberDetailView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import SwiftUI
import Charts
import PhotosUI
import UniformTypeIdentifiers

struct MemberDetailView: View {
    @ObservedObject var member: Member
    @StateObject private var viewModel = MemberViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openLoanWindow) private var openLoanWindow
    @State private var showingEditSheet = false
    @State private var showingCashOutConfirmation = false
    @State private var showingNewLoan = false
    @State private var showingNewPayment = false

    /// Pre-fill values for the loan-creation sheet, set by the eligibility
    /// card's "Issue Loan with these terms" button.
    @State private var newLoanPrefillAmount: Double?
    @State private var newLoanPrefillMonths: Int?

    /// Photo upload state. Two entry points:
    /// - Photos library via `PhotosPicker` (limited to iCloud Photos).
    /// - Any image file on disk via `.fileImporter` (the general-purpose
    ///   path — JPEGs sent over email, screenshots, scans, etc.).
    /// Both funnel through `MemberPhotoProcessor.process` and end up in
    /// the same `member.photoData` field.
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var showingPhotosPicker = false
    @State private var showingPhotoOptions = false
    @State private var isProcessingPhoto = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                identityHeader
                heroMetrics
                let contributions = viewModel.getMemberContributions(for: member)
                if !contributions.isEmpty {
                    ContributionChartCard(contributions: contributions)
                }
                eligibilityElevated
                loanHistorySection
                paymentHistorySection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(member.name ?? "Member Details")
        .toolbar {
            // Two primary actions in the toolbar (Mac-native pattern) — small,
            // text-only buttons. The previous full-width tile-card buttons in
            // the page body competed visually with the actual content.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewPayment = true
                } label: {
                    Label("Make Payment", systemImage: "plus")
                }
                .help("Record a contribution or loan repayment for \(member.name ?? "this member")")
            }
            if member.isEligibleForLoan {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newLoanPrefillAmount = nil
                        newLoanPrefillMonths = nil
                        showingNewLoan = true
                    } label: {
                        Label("New Loan", systemImage: "creditcard")
                    }
                    .help("Issue a new loan to \(member.name ?? "this member")")
                }
            }
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

                    if member.memberStatus != .cashedOut {
                        Button {
                            showingCashOutConfirmation = true
                        } label: {
                            Label("Cash Out…", systemImage: "banknote")
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
                    Image(systemName: "ellipsis")
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
        .sheet(isPresented: $showingCashOutConfirmation) {
            CashOutMemberSheet(member: member)
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }

    // MARK: - Sections

    /// Compact identity header — single horizontal row. Avatar (real
    /// per-member tint), name + role + status inline, tenure on the right.
    /// Replaces the previous full-width centred panel that left ~150pt
    /// of empty space above and below a tiny avatar.
    private var identityHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            avatarPicker

            VStack(alignment: .leading, spacing: 6) {
                Text(member.name ?? "Unknown")
                    .font(.title.weight(.semibold))

                HStack(spacing: 8) {
                    Text(member.memberRole.displayName)
                    Text("·")
                    StatusBadge(status: member.memberStatus)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let joinDate = member.joinDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Member since")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(joinDate, format: .dateTime.month(.abbreviated).year())
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    Text(tenureString(from: joinDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Tap-to-upload avatar. Click anywhere on the avatar opens a
    /// `.confirmationDialog` that offers two paths:
    /// - "Choose File…" — `.fileImporter` for any image on disk
    /// - "Choose from Photos…" — `PhotosPicker` for iCloud Photos
    /// Plus, when a photo is set, "Remove Photo".
    ///
    /// The previous `Menu` wrapper collapsed the custom 64pt label
    /// into default Menu button chrome, rendering the avatar tiny and
    /// adding a "Change photo" tooltip-as-text artifact.
    /// `Button + .confirmationDialog` keeps the custom label intact.
    private var avatarPicker: some View {
        VStack(spacing: 6) {
            Button {
                showingPhotoOptions = true
            } label: {
                avatarWithCameraOverlay
            }
            .buttonStyle(.plain)
            .help(member.photoData == nil ? "Add a photo" : "Change photo")

            // Always-visible text affordance so the upload action is
            // discoverable without having to hover or guess. Centred
            // under the avatar disc so the column reads as one element.
            Text(member.photoData == nil ? "Add Photo" : "Change Photo")
                .font(.caption)
                .foregroundStyle(BrandColor.avocado)
                .frame(maxWidth: 80)
                .multilineTextAlignment(.center)
        }
        .confirmationDialog("Member Photo",
                            isPresented: $showingPhotoOptions,
                            titleVisibility: .hidden) {
            Button {
                showingFileImporter = true
            } label: {
                Label("Choose File…", systemImage: "folder")
            }
            Button {
                showingPhotosPicker = true
            } label: {
                Label("From Photos Library…", systemImage: "photo.on.rectangle")
            }
            if member.photoData != nil {
                Button("Remove Photo", role: .destructive) {
                    removeCurrentPhoto()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingPhotosPicker,
                      selection: $photoPickerItem,
                      matching: .images,
                      photoLibrary: .shared())
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            applyPickedPhoto(newItem)
        }
        .fileImporter(isPresented: $showingFileImporter,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: false) { result in
            handleFileImporter(result)
        }
    }

    /// Avatar with a prominent avocado camera badge in the bottom-right
    /// when no photo is set, to invite the upload action. When a photo
    /// is set, the badge is more subdued — the photo itself does the
    /// work of being visible.
    private var avatarWithCameraOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            MemberAvatar(member: member, size: 80)
                .overlay(
                    Circle()
                        .strokeBorder(.separator, lineWidth: 0.5)
                )

            // Camera chip — louder when prompting for a first upload.
            ZStack {
                Circle()
                    .fill(BrandColor.avocado)
                    .frame(width: member.photoData == nil ? 28 : 24,
                           height: member.photoData == nil ? 28 : 24)
                    .overlay(Circle().stroke(.background, lineWidth: 2.5))
                Image(systemName: "camera.fill")
                    .font(.system(size: member.photoData == nil ? 13 : 11,
                                  weight: .semibold))
                    .foregroundStyle(.white)
            }
            .opacity(isProcessingPhoto ? 0.4 : 1)
            .offset(x: 2, y: 2)

            if isProcessingPhoto {
                ProgressView()
                    .controlSize(.small)
                    .padding(2)
            }
        }
    }

    private func applyPickedPhoto(_ item: PhotosPickerItem) {
        isProcessingPhoto = true
        Task {
            defer {
                Task { @MainActor in
                    isProcessingPhoto = false
                    photoPickerItem = nil
                }
            }

            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let processed = MemberPhotoProcessor.process(raw) else {
                return
            }

            await persist(processed)
        }
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isProcessingPhoto = true
        Task {
            defer {
                Task { @MainActor in
                    isProcessingPhoto = false
                }
            }

            // Sandbox-scoped resource access: required when the user has
            // picked a file outside the app's container.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            guard let raw = try? Data(contentsOf: url),
                  let processed = MemberPhotoProcessor.process(raw) else {
                return
            }
            await persist(processed)
        }
    }

    @MainActor
    private func persist(_ data: Data) {
        member.photoData = data
        member.updatedAt = Date()
        try? PersistenceController.shared.container.viewContext.save()
    }

    @MainActor
    private func removeCurrentPhoto() {
        member.photoData = nil
        member.updatedAt = Date()
        try? PersistenceController.shared.container.viewContext.save()
    }

    /// Three-up at-a-glance metrics. The page's job in two seconds:
    /// where does this member stand?
    private var heroMetrics: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 0) {
                metricCell(
                    label: "Total Contributions",
                    value: CurrencyFormatter.shared.format(member.totalContributions),
                    tint: .green
                )
                Divider().frame(height: 56)
                metricCell(
                    label: "Active Loan Balance",
                    value: CurrencyFormatter.shared.format(member.totalActiveLoanBalance),
                    tint: member.hasActiveLoans ? .orange : .secondary,
                    muted: !member.hasActiveLoans
                )
                Divider().frame(height: 56)
                metricCell(
                    label: "Available to Borrow",
                    value: CurrencyFormatter.shared.format(member.maximumLoanAmount),
                    tint: member.maximumLoanAmount > 0 ? BrandColor.honey : .secondary,
                    muted: member.maximumLoanAmount == 0
                )
            }
            .padding(.vertical, 6)
        }
    }

    private func metricCell(label: String, value: String, tint: Color, muted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(2, reservesSpace: false)
            Text(value)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(muted ? .secondary : tint)
                .monospacedDigit()
                // On narrow widths (iPhone column), 3-up cells are ~120pt
                // each — too tight for "KSH 33,000" at title2 serif. Shrink
                // to fit instead of truncating with ellipsis.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    /// Eligibility card stays as the most actionable surface but is
    /// visually elevated (its own GroupBox treatment is preserved).
    private var eligibilityElevated: some View {
        LoanEligibilityCard(member: member) { amount, months in
            newLoanPrefillAmount = amount
            newLoanPrefillMonths = months
            showingNewLoan = true
        }
    }

    @ViewBuilder
    private var loanHistorySection: some View {
        let loans = viewModel.getMemberLoanHistory(for: member)
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Loans", count: loans.count)
            if loans.isEmpty {
                Text("No loans on record.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 10) {
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
        }
    }

    @ViewBuilder
    private var paymentHistorySection: some View {
        let transactions = (member.transactions?.allObjects as? [Transaction] ?? [])
            .sorted { ($0.transactionDate ?? Date()) > ($1.transactionDate ?? Date()) }
            .prefix(50)

        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Payments", count: transactions.count)
            if transactions.isEmpty {
                Text("No payments recorded yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transactions)) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func tenureString(from joinDate: Date) -> String {
        let months = Calendar.current.dateComponents([.month], from: joinDate, to: Date()).month ?? 0
        if months < 1 { return "less than a month" }
        if months == 1 { return "1 month" }
        if months < 12 { return "\(months) months" }
        let years = months / 12
        let remainder = months % 12
        if remainder == 0 {
            return years == 1 ? "1 year" : "\(years) years"
        }
        return "\(years)y \(remainder)m"
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

                LoanStatusPill(loan: loan)
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
            } else if loan.loanStatus == .completed {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Completed on \(DateHelper.formatDate(loan.completedDate))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Loan-specific status pill. Replaces the previous `StatusBadge`
/// abuse, which was the member-status primitive and only had Active /
/// Inactive — leaving completed loans labelled "Inactive" in grey.
struct LoanStatusPill: View {
    let loan: Loan

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var label: String {
        if loan.loanStatus == .completed { return "Completed" }
        if loan.isOverdue { return "Overdue" }
        if loan.loanStatus == .active { return "Active" }
        return loan.loanStatus.rawValue.capitalized
    }

    private var tint: Color {
        if loan.loanStatus == .completed { return .green }
        if loan.isOverdue { return .red }
        if loan.loanStatus == .active { return .blue }
        return .gray
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
    @State private var joinDate = Date()

    // Custom override fields
    @State private var hasCustomLoanLimit: Bool = false
    @State private var customLoanLimitString: String = ""
    @State private var hasCustomRepaymentTerms: Bool = false
    @State private var allowedRepaymentMonths: Set<Int> = []
    @State private var overrideReason: String = ""
    
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var isProcessingPhoto = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    HStack(spacing: 16) {
                        MemberAvatar(member: member, size: 64)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Button {
                                    showingFileImporter = true
                                } label: {
                                    Label("Choose File…", systemImage: "folder")
                                }
                                PhotosPicker(selection: $photoPickerItem,
                                             matching: .images,
                                             photoLibrary: .shared()) {
                                    Label("From Photos…", systemImage: "photo.on.rectangle")
                                }
                            }

                            if member.photoData != nil {
                                Button(role: .destructive) {
                                    member.photoData = nil
                                    member.updatedAt = Date()
                                    try? PersistenceController.shared.container.viewContext.save()
                                } label: {
                                    Text("Remove Photo")
                                }
                                .buttonStyle(.borderless)
                            }
                            if isProcessingPhoto {
                                Label("Processing…", systemImage: "hourglass")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .onChange(of: photoPickerItem) { _, newItem in
                        guard let newItem else { return }
                        loadAndApplyPhoto(newItem)
                    }
                    .fileImporter(isPresented: $showingFileImporter,
                                  allowedContentTypes: [.image],
                                  allowsMultipleSelection: false) { result in
                        handleFileImporter(result)
                    }
                }

                Section("Member Information") {
                    TextField("Full Name", text: $name)
                        .textContentType(.name)

                    Picker("Role", selection: $role) {
                        ForEach(MemberRole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
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

    private func loadAndApplyPhoto(_ item: PhotosPickerItem) {
        isProcessingPhoto = true
        Task {
            defer {
                Task { @MainActor in
                    isProcessingPhoto = false
                    photoPickerItem = nil
                }
            }
            guard let raw = try? await item.loadTransferable(type: Data.self),
                  let processed = MemberPhotoProcessor.process(raw) else {
                return
            }
            await MainActor.run {
                member.photoData = processed
                member.updatedAt = Date()
                try? PersistenceController.shared.container.viewContext.save()
            }
        }
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isProcessingPhoto = true
        Task {
            defer {
                Task { @MainActor in
                    isProcessingPhoto = false
                }
            }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            guard let raw = try? Data(contentsOf: url),
                  let processed = MemberPhotoProcessor.process(raw) else {
                return
            }
            await MainActor.run {
                member.photoData = processed
                member.updatedAt = Date()
                try? PersistenceController.shared.container.viewContext.save()
            }
        }
    }
}

#Preview {
    NavigationStack {
        MemberDetailView(member: Member(context: PersistenceController.preview.container.viewContext))
    }
}