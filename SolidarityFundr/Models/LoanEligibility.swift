//
//  LoanEligibility.swift
//  SolidarityFundr
//
//  Pure value type that combines the member-side and fund-side rules
//  into a single "what could this member borrow right now" answer.
//
//  Used by the LoanEligibilityCard on MemberDetailView so the admin can
//  see, at a glance, what's possible for a given member without leaving
//  their page. Also drives the pre-fill on the issuance flow.
//

import Foundation
import CoreData

struct LoanEligibility {

    // MARK: - Ceilings

    /// Role + existing-balance ceiling, e.g. "Driver limit 40k − 30k active = 10k headroom".
    let memberMaxAmount: Double

    /// Fund-balance headroom: how much could be lent without dropping the
    /// fund below the configured minimum balance.
    let fundHeadroom: Double

    /// Largest single loan amount that would *not* push utilization over
    /// the configured warning threshold.
    let utilizationCeiling: Double

    /// The minimum of the three above, clamped at zero. This is the
    /// number to show as "you can lend up to KSH X right now."
    var effectiveMax: Double {
        max(0, min(memberMaxAmount, fundHeadroom, utilizationCeiling))
    }

    // MARK: - Rule outcomes

    /// Hard blocks — non-zero means no loan should be issued.
    /// Examples: member status not active; guard with <3 months of contributions.
    let blockingReasons: [String]

    /// Soft warnings — caller may proceed but should display them.
    /// Examples: fund would dip near minimum balance; utilization would
    /// cross the warning threshold (when not overridden).
    let warnings: [String]

    /// Allowed repayment terms for this member (3/4 for most roles, 6 for guards/part-time).
    let allowedRepaymentMonths: [Int]

    var isEligible: Bool { blockingReasons.isEmpty && effectiveMax > 0 }

    // MARK: - Per-amount preview

    /// Populated when `compute` is called with a proposedAmount. Lets the
    /// UI show "if you lend KSH 25,000 over 4 months, monthly payment is
    /// KSH 6,250 and utilization goes from 10% → 22%."
    let preview: Preview?

    struct Preview {
        let amount: Double
        let months: Int
        let monthlyPayment: Double
        let utilizationBefore: Double  // 0…1
        let utilizationAfter: Double   // 0…1
        let exceedsWarningThreshold: Bool
    }

    // MARK: - Compute

    static func compute(
        member: Member,
        settings: FundSettings,
        proposedAmount: Double? = nil,
        proposedMonths: Int? = nil,
        fundCalculator: FundCalculator = .shared
    ) -> LoanEligibility {

        // 1. Member ceiling — uses existing role+balance logic on Member.
        let memberMax = member.maximumLoanAmount

        // 2. Fund balance headroom.
        let fundBalance = fundCalculator.calculateFundBalance(settings: settings)
        let minBalance = settings.minimumFundBalance
        let fundHeadroom = max(0, fundBalance - minBalance)

        // 3. Utilization ceiling. Solve: (currentLoans + L) / totalCapital == threshold
        //    → L = threshold * totalCapital − currentLoans
        let totalActive = fundCalculator.calculateTotalActiveLoans()
        let totalCapital = fundCalculator.calculateTotalCapital(settings: settings)
        let threshold = settings.utilizationWarningThreshold
        let utilizationCeiling: Double
        if totalCapital > 0 {
            utilizationCeiling = max(0, threshold * totalCapital - totalActive)
        } else {
            utilizationCeiling = 0
        }

        // 4. Blocks (hard).
        var blocks: [String] = []
        if member.memberStatus != .active {
            blocks.append("Member is \(member.memberStatus.rawValue.capitalized).")
        }
        if member.memberRole == .securityGuard || member.memberRole == .partTime {
            if member.contributionMonthsCount < 3 {
                let made = member.contributionMonthsCount
                blocks.append("Guards/part-time need 3 months of contributions (\(made)/3).")
            }
        }

        // 5. Soft warnings.
        var warns: [String] = []
        if fundBalance - (proposedAmount ?? 0) < minBalance {
            warns.append("Issuing this loan would drop the fund below its KSH \(Int(minBalance)) minimum.")
        }

        // 6. Per-amount preview, if requested.
        let preview: Preview? = {
            guard let amount = proposedAmount, amount > 0 else { return nil }
            let months = proposedMonths ?? member.allowedRepaymentMonths.first ?? 3
            let monthly = months > 0
                ? (amount / Double(months)).rounded(.toNearestOrAwayFromZero)
                : 0
            let utilBefore = totalCapital > 0 ? totalActive / totalCapital : 0
            let utilAfter = totalCapital > 0 ? (totalActive + amount) / totalCapital : 0
            let exceeds = utilAfter > settings.utilizationWarningThreshold
            if exceeds {
                warns.append(
                    String(format: "This would push utilization to %.1f%% (warning at %.0f%%).",
                           utilAfter * 100,
                           settings.utilizationWarningThreshold * 100)
                )
            }
            return Preview(
                amount: amount,
                months: months,
                monthlyPayment: monthly,
                utilizationBefore: utilBefore,
                utilizationAfter: utilAfter,
                exceedsWarningThreshold: exceeds
            )
        }()

        return LoanEligibility(
            memberMaxAmount: memberMax,
            fundHeadroom: fundHeadroom,
            utilizationCeiling: utilizationCeiling,
            blockingReasons: blocks,
            warnings: warns,
            allowedRepaymentMonths: member.allowedRepaymentMonths,
            preview: preview
        )
    }
}
