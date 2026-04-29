//
//  WithdrawFundsSheet.swift
//  SolidarityFundr
//
//  Records Bob withdrawing cash from the fund. Decrements
//  `bobRemainingInvestment` and the fund cash balance by the same
//  amount. Member balances are unaffected.
//
//  The sheet shows live previews of:
//    - Bob's investment after the withdrawal
//    - Fund cash balance after the withdrawal
//    - Whether the fund would drop below the minimum-balance threshold
//

import SwiftUI

struct WithdrawFundsSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var errorMessage: String?
    @State private var showingConfirmation = false

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var bobCurrent: Double {
        dataManager.fundSettings?.bobRemainingInvestment ?? 0
    }

    private var fundCashCurrent: Double {
        FundCalculator.shared.calculateFundBalance(settings: dataManager.fundSettings)
    }

    private var minimumBalance: Double {
        dataManager.fundSettings?.minimumFundBalance ?? 0
    }

    private var bobAfter: Double { max(0, bobCurrent - amount) }
    private var fundCashAfter: Double { fundCashCurrent - amount }

    private var willBreachMinimum: Bool {
        fundCashAfter < minimumBalance
    }

    private var willExceedStake: Bool {
        amount > bobCurrent
    }

    private var canWithdraw: Bool {
        amount > 0 && !willExceedStake
    }

    var body: some View {
        Form {
            Section("Current state") {
                LabeledContent("Your remaining investment") {
                    Text(CurrencyFormatter.shared.format(bobCurrent))
                        .monospacedDigit()
                }
                LabeledContent("Fund cash balance") {
                    Text(CurrencyFormatter.shared.format(fundCashCurrent))
                        .monospacedDigit()
                }
            }

            Section("Withdrawal amount") {
                HStack {
                    Text("KSH")
                        .foregroundStyle(.secondary)
                    TextField("0", text: $amountText)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                TextField("Note (optional, e.g. \"Year 1 milestone withdrawal\")", text: $note)
            }

            if amount > 0 {
                Section("After withdrawing") {
                    LabeledContent("Your remaining investment") {
                        Text(CurrencyFormatter.shared.format(bobAfter))
                            .monospacedDigit()
                            .foregroundStyle(willExceedStake ? .red : .primary)
                    }
                    LabeledContent("Fund cash balance") {
                        Text(CurrencyFormatter.shared.format(fundCashAfter))
                            .monospacedDigit()
                            .foregroundStyle(willBreachMinimum ? .orange : .primary)
                    }
                }

                if willExceedStake {
                    Section {
                        Label(
                            "Withdrawal exceeds your remaining investment by \(CurrencyFormatter.shared.format(amount - bobCurrent)).",
                            systemImage: "xmark.octagon.fill"
                        )
                        .foregroundStyle(.red)
                        .font(.callout)
                    }
                } else if willBreachMinimum {
                    Section {
                        Label(
                            "Fund balance would drop below the configured minimum of \(CurrencyFormatter.shared.format(minimumBalance)). You can still proceed if you accept the risk.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                        .font(.callout)
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
        .navigationTitle("Withdraw Funds")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Withdraw…") { showingConfirmation = true }
                    .disabled(!canWithdraw)
            }
        }
        .confirmationDialog(
            "Withdraw KSH \(Int(amount)) from the fund?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Withdraw", role: .destructive) { performWithdraw() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your remaining investment will drop to \(CurrencyFormatter.shared.format(bobAfter)). The withdrawal will be recorded in the ledger and audit log.")
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private func performWithdraw() {
        do {
            try dataManager.recordWithdrawal(
                amount: amount,
                note: note.isEmpty ? nil : note
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
