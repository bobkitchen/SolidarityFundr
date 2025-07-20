//
//  ValidationHelper.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import SwiftUI

struct ValidationHelper {
    
    // MARK: - Input Validation
    
    static func validateCurrency(_ input: String) -> Bool {
        let cleanedInput = input.replacingOccurrences(of: ",", with: "")
        return Double(cleanedInput) != nil
    }
    
    static func parseCurrency(_ input: String) -> Double? {
        let cleanedInput = input.replacingOccurrences(of: ",", with: "")
        return Double(cleanedInput)
    }
    
    static func formatCurrencyInput(_ input: String) -> String {
        let cleanedInput = input.replacingOccurrences(of: ",", with: "")
        guard let number = Double(cleanedInput) else { return input }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        
        return formatter.string(from: NSNumber(value: number)) ?? input
    }
    
    static func sanitizePhoneNumber(_ phone: String) -> String {
        let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
        return phone.components(separatedBy: allowedCharacters.inverted).joined()
    }
    
    static func validateEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
    
    static func validatePhoneNumber(_ phone: String) -> Bool {
        let phoneRegEx = "^[+]?[0-9]{10,15}$"
        let phonePred = NSPredicate(format:"SELF MATCHES %@", phoneRegEx)
        let cleanPhone = sanitizePhoneNumber(phone)
        return phonePred.evaluate(with: cleanPhone)
    }
    
    // MARK: - Name Validation
    
    static func validateName(_ name: String) -> ValidationResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            return ValidationResult(isValid: false, errors: ["Name is required"], warnings: [])
        }
        
        if trimmedName.count < 2 {
            return ValidationResult(isValid: false, errors: ["Name must be at least 2 characters"], warnings: [])
        }
        
        if trimmedName.count > 50 {
            return ValidationResult(isValid: false, errors: ["Name must be less than 50 characters"], warnings: [])
        }
        
        // Check for invalid characters
        let allowedCharacters = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "'-"))
        if trimmedName.rangeOfCharacter(from: allowedCharacters.inverted) != nil {
            return ValidationResult(isValid: false, errors: ["Name contains invalid characters"], warnings: [])
        }
        
        return ValidationResult(isValid: true, errors: [], warnings: [])
    }
    
    // MARK: - Amount Validation
    
    static func validateLoanAmount(_ amount: Double, minimum: Double = 1000, maximum: Double) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        
        if amount <= 0 {
            errors.append("Amount must be greater than zero")
        } else if amount < minimum {
            errors.append("Minimum loan amount is KSH \(Int(minimum))")
        } else if amount > maximum {
            errors.append("Maximum loan amount is KSH \(Int(maximum))")
        }
        
        // Warning for round numbers
        if amount.truncatingRemainder(dividingBy: 1000) != 0 {
            warnings.append("Consider using round amounts (multiples of 1000)")
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
    
    static func validatePaymentAmount(_ amount: Double, forLoan: Bool) -> ValidationResult {
        var errors: [String] = []
        
        if amount <= 0 {
            errors.append("Amount must be greater than zero")
        } else if forLoan && amount < 2000 {
            errors.append("Loan payments must be at least KSH 2,000")
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors, warnings: [])
    }
    
    // MARK: - Date Validation
    
    static func validateFutureDate(_ date: Date) -> Bool {
        return date > Date()
    }
    
    static func validateDateRange(start: Date, end: Date) -> Bool {
        return start <= end
    }
    
    static func validateJoinDate(_ date: Date) -> ValidationResult {
        if date > Date() {
            return ValidationResult(isValid: false, errors: ["Join date cannot be in the future"], warnings: [])
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: date, to: Date())
        
        if let years = components.year, years > 10 {
            return ValidationResult(isValid: true, errors: [], warnings: ["Join date is more than 10 years ago"])
        }
        
        return ValidationResult(isValid: true, errors: [], warnings: [])
    }
}

// MARK: - View Modifiers

struct ValidationModifier: ViewModifier {
    let isValid: Bool
    let showError: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(showError && !isValid ? Color.red : Color.clear, lineWidth: 1)
            )
    }
}

extension View {
    func validated(_ isValid: Bool, showError: Bool = true) -> some View {
        modifier(ValidationModifier(isValid: isValid, showError: showError))
    }
}

// MARK: - Formatting Extensions

extension String {
    var isValidEmail: Bool {
        ValidationHelper.validateEmail(self)
    }
    
    var isValidPhoneNumber: Bool {
        ValidationHelper.validatePhoneNumber(self)
    }
    
    var sanitizedPhoneNumber: String {
        ValidationHelper.sanitizePhoneNumber(self)
    }
    
    var currencyValue: Double? {
        ValidationHelper.parseCurrency(self)
    }
}

// MARK: - Number Formatting

struct CurrencyFormatter {
    static let shared = CurrencyFormatter()
    
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "KES"
        formatter.maximumFractionDigits = 0
        formatter.currencySymbol = "KSH"
        return formatter
    }()
    
    private let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()
    
    func format(_ amount: Double) -> String {
        return formatter.string(from: NSNumber(value: amount)) ?? "KSH 0"
    }
    
    func formatDecimal(_ amount: Double) -> String {
        return decimalFormatter.string(from: NSNumber(value: amount)) ?? "0"
    }
    
    func formatShort(_ amount: Double) -> String {
        if amount >= 1_000_000 {
            return "KSH \(String(format: "%.1f", amount / 1_000_000))M"
        } else if amount >= 1_000 {
            return "KSH \(String(format: "%.1f", amount / 1_000))K"
        } else {
            return "KSH \(Int(amount))"
        }
    }
}