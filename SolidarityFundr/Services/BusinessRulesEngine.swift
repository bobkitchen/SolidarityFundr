//
//  BusinessRulesEngine.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation

class BusinessRulesEngine {
    static let shared = BusinessRulesEngine()
    
    private init() {}
    
    // MARK: - Member Validation
    
    func validateNewMember(name: String, role: MemberRole, email: String?, phoneNumber: String?) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Name validation
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Member name is required")
        } else if name.count < 2 {
            errors.append("Member name must be at least 2 characters")
        }
        
        // Email validation (optional but must be valid if provided)
        if let email = email, !email.isEmpty {
            if !isValidEmail(email) {
                errors.append("Invalid email format")
            }
        }
        
        // Phone validation (optional but must be valid if provided)
        if let phone = phoneNumber, !phone.isEmpty {
            if !isValidPhoneNumber(phone) {
                warnings.append("Phone number format may be invalid")
            }
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Loan Validation
    
    func validateLoanRequest(member: Member, amount: Double, repaymentMonths: Int, fundSettings: FundSettings?) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Member eligibility
        if !member.isEligibleForLoan {
            if member.memberStatus != .active {
                errors.append("Member must be active to receive a loan")
            } else if member.memberRole == .securityGuard && member.monthsAsMember < 3 {
                errors.append("Guards must have 3 months of contributions before taking a loan")
            }
        }
        
        // Amount validation
        if amount <= 0 {
            errors.append("Loan amount must be greater than zero")
        } else {
            let maxAmount = member.maximumLoanAmount
            if amount > maxAmount {
                errors.append("Loan amount exceeds maximum allowed: KSH \(Int(maxAmount))")
            }
        }
        
        // Repayment period validation
        if member.memberRole == .securityGuard || member.memberRole == .partTime {
            // Guards and part-time staff must use 6-month repayment period
            if repaymentMonths != 6 {
                errors.append("Guards and part-time staff must use 6-month repayment period")
            }
        } else {
            // Other staff use 3 or 4 month repayment periods
            if repaymentMonths != 3 && repaymentMonths != 4 {
                errors.append("Repayment period must be 3 or 4 months")
            }
        }
        
        // Fund utilization warning
        if let settings = fundSettings {
            let currentUtilization = settings.calculateUtilizationPercentage()
            let fundBalance = settings.calculateFundBalance()
            let newUtilization = (currentUtilization * fundBalance + amount) / fundBalance
            
            if newUtilization >= settings.utilizationWarningThreshold {
                warnings.append("This loan will push fund utilization above \(Int(settings.utilizationWarningThreshold * 100))%")
            }
            
            if fundBalance - amount < settings.minimumFundBalance {
                warnings.append("This loan will reduce fund balance below minimum threshold of KSH \(Int(settings.minimumFundBalance))")
            }
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Payment Validation
    
    func validatePayment(member: Member, amount: Double, loan: Loan?, paymentType: PaymentType) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        // Amount validation
        if amount <= 0 {
            errors.append("Payment amount must be greater than zero")
        }
        
        // Loan payment validation
        if let loan = loan {
            if loan.loanStatus != .active {
                errors.append("Cannot make payment on inactive loan")
            }
            
            // Remove minimum amount check since contributions are separate
            
            if amount > loan.balance {
                warnings.append("Payment exceeds remaining loan balance")
            }
        } else if paymentType == .loanRepayment {
            errors.append("No active loan selected for repayment")
        }
        
        // Member status check
        if member.memberStatus == .suspended {
            warnings.append("Member is suspended - payment will be accepted but status should be reviewed")
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Cash Out Validation
    
    func validateCashOut(member: Member) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        if member.memberStatus == .active {
            errors.append("Active members cannot cash out. Member must be suspended or inactive first.")
        }
        
        if member.hasActiveLoans {
            errors.append("Member has active loans that must be settled before cashing out")
        }
        
        if member.totalContributions <= 0 {
            errors.append("Member has no contributions to cash out")
        }
        
        if member.cashOutAmount > 0 {
            warnings.append("Member has already cashed out KSH \(Int(member.cashOutAmount))")
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Fund Operations Validation
    
    func validateInterestApplication(fundSettings: FundSettings) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        if let lastApplied = fundSettings.lastInterestAppliedDate {
            let daysSinceLastApplication = Calendar.current.dateComponents([.day], from: lastApplied, to: Date()).day ?? 0
            
            if daysSinceLastApplication < 365 {
                warnings.append("Interest was last applied \(daysSinceLastApplication) days ago. Annual interest is typically applied after 365 days.")
            }
        }
        
        let fundBalance = fundSettings.calculateFundBalance()
        if fundBalance <= 0 {
            errors.append("Cannot apply interest to negative or zero fund balance")
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    // MARK: - Helper Methods
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
    
    private func isValidPhoneNumber(_ phone: String) -> Bool {
        let phoneRegEx = "^[+]?[0-9]{10,15}$"
        let phonePred = NSPredicate(format:"SELF MATCHES %@", phoneRegEx)
        let cleanPhone = phone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        return phonePred.evaluate(with: cleanPhone)
    }
    
    // MARK: - Business Rules Checks
    
    func shouldWarnFundUtilization(_ fundSettings: FundSettings) -> Bool {
        return fundSettings.calculateUtilizationPercentage() >= fundSettings.utilizationWarningThreshold
    }
    
    func shouldWarnMinimumBalance(_ fundSettings: FundSettings) -> Bool {
        return fundSettings.calculateFundBalance() < fundSettings.minimumFundBalance
    }
    
    func canDeleteMember(_ member: Member) -> Bool {
        return !member.hasActiveLoans
    }
    
    func calculateMaxLoanAmount(for member: Member) -> Double {
        return member.maximumLoanAmount
    }
    
    func calculateMonthlyPayment(loanAmount: Double, months: Int) -> Double {
        return loanAmount / Double(months)
    }
}

// MARK: - Validation Result

struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    
    var hasWarnings: Bool {
        return !warnings.isEmpty
    }
    
    var allMessages: [String] {
        return errors + warnings
    }
    
    var errorMessage: String? {
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }
    
    var warningMessage: String? {
        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }
}