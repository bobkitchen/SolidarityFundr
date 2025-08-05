//
//  PhoneNumberValidator.swift
//  SolidarityFundr
//
//  Created on 7/25/25.
//

import Foundation

struct PhoneNumberValidator {
    /// Validate if a phone number is in a valid format
    static func validate(_ phoneNumber: String) -> Bool {
        let cleanedNumber = phoneNumber.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "+", with: "")
        
        // Check if it's a valid Kenyan number
        if cleanedNumber.hasPrefix("254") {
            return cleanedNumber.count == 12 // 254 + 9 digits
        } else if cleanedNumber.hasPrefix("0") {
            return cleanedNumber.count == 10 // 0 + 9 digits
        }
        
        return false
    }
    
    /// Format phone number to international format
    static func formatToInternational(_ phoneNumber: String) -> String {
        let cleanedNumber = phoneNumber.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "+", with: "")
        
        if cleanedNumber.hasPrefix("254") {
            return "+\(cleanedNumber)"
        } else if cleanedNumber.hasPrefix("0") {
            return "+254" + cleanedNumber.dropFirst()
        }
        
        return "+254" + cleanedNumber
    }
}