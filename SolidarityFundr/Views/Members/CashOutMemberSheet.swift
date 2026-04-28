//
//  CashOutMemberSheet.swift
//  SolidarityFundr
//
//  Formal departure workflow. Replaces the previous one-tap
//  confirmationDialog with a sheet that previews the settlement
//  breakdown, captures the reason for departure (required for the
//  audit log), the payment method, and the effective date, then posts
//  the cash-out and transitions the member to the terminal
//  `.cashedOut` status.
//
//  Settlement formula (per fund policy, option B):
//    payout = totalContributions × (1 + 0.13)
//
//  Pre-flight: blocks if the member has any active loan with a
//  non-zero balance.
//

import SwiftUI

struct CashOutMemberSheet: View {
    let member: Member
    @StateObject private var viewModel = MemberViewModel()
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String = ""
    @State private var paymentMethod: PaymentMethod = .cash
    @State private var effectiveDate: Date = Date()

    private var hasBlockingLoans: Bool {
        member.hasActiveLoans
    }

    private var contributions: Double { member.totalContributions }
    private var interestRate: Double { dataManager.fundSettings?.annualInterestRate ?? 0.13 }
    private var interestAmount: Double { contributions * interestRate }
    private var payout: Double { contributions + interestAmount }

    private var canSubmit: Bool {
        !hasBlockingLoans
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && payout > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                memberSection
                if hasBlockingLoans {
                    blockingLoansSection
                } else {
                    settlementSection
                    payoutDetailsSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Cash Out")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cash Out") {
                        let didSucceed = viewModel.cashOutMember(
                            member,
                            reason: reason,
                            paymentMethod: paymentMethod,
                            date: effectiveDate
                        )
                        if didSucceed { dismiss() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .alert("Cash-out failed",
                   isPresented: $viewModel.showingError,
                   actions: { Button("OK") {} },
                   message: { Text(viewModel.errorMessage ?? "Unknown error") })
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    // MARK: - Sections

    private var memberSection: some View {
        Section("Member") {
            LabeledContent("Name", value: member.name ?? "Unknown")
            LabeledContent("Role", value: member.memberRole.displayName)
            if let joinDate = member.joinDate {
                LabeledContent("Joined", value: DateHelper.formatDate(joinDate))
            }
        }
    }

    private var blockingLoansSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active loans must be settled first.")
                        .font(.callout.weight(.medium))
                    Text("This member has an outstanding loan balance. Record a final loan payment that brings the balance to zero, then return here to complete the cash-out.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var settlementSection: some View {
        Section {
            LabeledContent("Total Contributions") {
                Text(CurrencyFormatter.shared.format(contributions))
                    .monospacedDigit()
            }
            LabeledContent("Interest at \(Int((interestRate * 100).rounded()))%") {
                Text(CurrencyFormatter.shared.format(interestAmount))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }
            Divider()
            LabeledContent("Payout") {
                Text(CurrencyFormatter.shared.format(payout))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        } header: {
            Text("Settlement")
        } footer: {
            Text("Per fund policy: contributions plus a flat \(Int((interestRate * 100).rounded()))% on contributions.")
        }
    }

    private var payoutDetailsSection: some View {
        Section {
            Picker("Payment method", selection: $paymentMethod) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    Text(method.displayName).tag(method)
                }
            }

            DatePicker("Effective date",
                       selection: $effectiveDate,
                       displayedComponents: .date)

            VStack(alignment: .leading, spacing: 6) {
                Text("Reason for departure")
                    .font(.callout)
                TextField("Required — captured in audit log",
                          text: $reason,
                          axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("A reason is required for the audit log.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Payout details")
        } footer: {
            Text("Cash-out is permanent: the member transitions to the Cashed Out state, their records are preserved for historical reports, and they no longer appear in active rollups.")
        }
    }
}
