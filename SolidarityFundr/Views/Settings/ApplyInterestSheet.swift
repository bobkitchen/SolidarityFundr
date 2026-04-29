//
//  ApplyInterestSheet.swift
//  SolidarityFundr
//
//  Distributes interest to active members proportionally to their
//  contributions. The user picks the source — either converting Bob's
//  remaining capital into members' equity (internal transfer, fund
//  cash unchanged), or adding a fresh deposit that flows directly to
//  members (fund cash grows).
//
//  The sheet shows live previews of:
//    - Per-member share allocation
//    - Effect on Bob's remaining investment
//    - Effect on total staff contributions
//

import SwiftUI

struct ApplyInterestSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var source: DataManager.InterestSource = .fromCapital
    @State private var note: String = ""
    @State private var errorMessage: String?
    @State private var showingConfirmation = false

    /// All active members with positive contributions — the only ones
    /// who can receive interest. Sorted alphabetically for display.
    private var eligibleMembers: [Member] {
        dataManager.members
            .filter { $0.memberStatus == .active && $0.totalContributions > 0 }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var totalContributions: Double {
        eligibleMembers.reduce(0) { $0 + $1.totalContributions }
    }

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    /// Default suggestion: 13% × total active contributions. Honours the
    /// fund's documented commitment without depending on the prior-year
    /// fund balance.
    private var suggestedAmount: Double {
        guard let rate = dataManager.fundSettings?.annualInterestRate else { return 0 }
        return totalContributions * rate
    }

    private var bobAfter: Double {
        let current = dataManager.fundSettings?.bobRemainingInvestment ?? 0
        return source == .fromCapital ? max(0, current - amount) : current
    }

    private var totalContributionsAfter: Double {
        totalContributions + amount
    }

    private var canApply: Bool {
        guard amount > 0, !eligibleMembers.isEmpty, totalContributions > 0 else { return false }
        if source == .fromCapital {
            let bob = dataManager.fundSettings?.bobRemainingInvestment ?? 0
            return amount <= bob
        }
        return true
    }

    var body: some View {
        Form {
            Section("Source") {
                Picker("How is this funded?", selection: $source) {
                    Text("Convert from my capital").tag(DataManager.InterestSource.fromCapital)
                    Text("Fresh deposit").tag(DataManager.InterestSource.freshDeposit)
                }
                .pickerStyle(.segmented)

                Text(sourceExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Amount") {
                HStack {
                    Text("KSH")
                        .foregroundStyle(.secondary)
                    TextField("0", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                if suggestedAmount > 0 {
                    Button {
                        amountText = String(Int(suggestedAmount.rounded()))
                    } label: {
                        Label(
                            "Suggest \(CurrencyFormatter.shared.format(suggestedAmount.rounded())) (annual rate × current contributions)",
                            systemImage: "wand.and.stars"
                        )
                        .font(.callout)
                    }
                }

                TextField("Note (optional, e.g. \"Year 1 anniversary\")", text: $note)
            }

            if !eligibleMembers.isEmpty && amount > 0 {
                Section("Per-member distribution") {
                    ForEach(distributionPreview, id: \.name) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .fontWeight(.medium)
                                Text("\(CurrencyFormatter.shared.format(row.contributions)) of \(CurrencyFormatter.shared.format(totalContributions)) (\(row.percentLabel))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(CurrencyFormatter.shared.format(row.share))
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            if amount > 0 {
                Section("After applying") {
                    LabeledContent("Bob remaining investment") {
                        Text(CurrencyFormatter.shared.format(bobAfter))
                            .monospacedDigit()
                    }
                    LabeledContent("Total staff contributions") {
                        Text(CurrencyFormatter.shared.format(totalContributionsAfter))
                            .monospacedDigit()
                    }
                    LabeledContent("Total interest applied (lifetime)") {
                        let prior = dataManager.fundSettings?.totalInterestApplied ?? 0
                        Text(CurrencyFormatter.shared.format(prior + amount))
                            .monospacedDigit()
                    }
                }
            }

            if let err = errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Apply Interest")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply…") { showingConfirmation = true }
                    .disabled(!canApply)
            }
        }
        .confirmationDialog(
            "Apply KSH \(Int(amount)) interest \(source == .fromCapital ? "from your capital" : "as a fresh deposit")?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply Interest") { performApply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(eligibleMembers.count) member\(eligibleMembers.count == 1 ? "" : "s") will receive a proportional share. This action cannot be undone — but the audit log will record it.")
        }
        .frame(minWidth: 480, minHeight: 540)
    }

    // MARK: - Private

    private var sourceExplanation: String {
        switch source {
        case .fromCapital:
            return "Reclassifies your existing investment as members' interest. Fund cash is unchanged; your stake decreases by the interest amount."
        case .freshDeposit:
            return "You deposit new cash that immediately flows to members. Fund cash grows by the interest amount; your remaining stake is unchanged."
        }
    }

    private struct DistributionRow {
        let name: String
        let contributions: Double
        let share: Double
        let percentLabel: String
    }

    private var distributionPreview: [DistributionRow] {
        guard totalContributions > 0, amount > 0 else { return [] }
        var distributed: Double = 0
        let last = eligibleMembers.count - 1
        return eligibleMembers.enumerated().map { (i, member) in
            let contribs = member.totalContributions
            let pct = (contribs / totalContributions) * 100
            let share: Double
            if i == last {
                share = (amount - distributed).rounded(toPlaces: 2)
            } else {
                share = ((contribs / totalContributions) * amount).rounded(toPlaces: 2)
                distributed += share
            }
            return DistributionRow(
                name: member.name ?? "Unknown",
                contributions: contribs,
                share: share,
                percentLabel: String(format: "%.1f%%", pct)
            )
        }
    }

    private func performApply() {
        do {
            try dataManager.applyInterest(
                amount: amount,
                source: source,
                note: note.isEmpty ? nil : note
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let m = pow(10.0, Double(places))
        return (self * m).rounded() / m
    }
}
