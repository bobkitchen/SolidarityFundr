//
//  DateHelper.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation

struct DateHelper {
    
    // MARK: - Date Calculations
    
    static func monthsBetween(start: Date, end: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: start, to: end)
        return components.month ?? 0
    }
    
    static func daysBetween(start: Date, end: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: start, to: end)
        return components.day ?? 0
    }
    
    static func yearsBetween(start: Date, end: Date) -> Double {
        let months = Double(monthsBetween(start: start, end: end))
        return months / 12.0
    }
    
    static func addMonths(_ months: Int, to date: Date) -> Date {
        return Calendar.current.date(byAdding: .month, value: months, to: date) ?? date
    }
    
    static func addDays(_ days: Int, to date: Date) -> Date {
        return Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
    
    static func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
    
    static func endOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        let startOfMonth = self.startOfMonth(for: date)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? startOfMonth
        return calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? date
    }
    
    static func isLastDayOfMonth(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.component(.month, from: date) != calendar.component(.month, from: tomorrow)
    }
    
    // MARK: - Date Comparisons
    
    static func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        Calendar.current.isDate(date1, inSameDayAs: date2)
    }
    
    static func isSameMonth(_ date1: Date, _ date2: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.month, from: date1) == calendar.component(.month, from: date2) &&
               calendar.component(.year, from: date1) == calendar.component(.year, from: date2)
    }
    
    static func isInPast(_ date: Date) -> Bool {
        return date < Date()
    }
    
    static func isInFuture(_ date: Date) -> Bool {
        return date > Date()
    }
    
    static func isToday(_ date: Date) -> Bool {
        return Calendar.current.isDateInToday(date)
    }
    
    static func isWithinDays(_ days: Int, from date: Date) -> Bool {
        let futureDate = addDays(days, to: Date())
        return date <= futureDate
    }
    
    // MARK: - Business Date Calculations
    
    static func nextPaymentDate(from startDate: Date, monthsElapsed: Int) -> Date {
        return addMonths(monthsElapsed + 1, to: startDate)
    }
    
    static func loanDueDate(issueDate: Date, repaymentMonths: Int) -> Date {
        return addMonths(repaymentMonths, to: issueDate)
    }
    
    static func monthsSinceJoining(_ joinDate: Date) -> Int {
        return monthsBetween(start: joinDate, end: Date())
    }
    
    static func daysUntilDue(_ dueDate: Date) -> Int {
        let days = daysBetween(start: Date(), end: dueDate)
        return max(0, days)
    }
    
    static func daysOverdue(_ dueDate: Date) -> Int {
        let days = daysBetween(start: dueDate, end: Date())
        return max(0, days)
    }
    
    // MARK: - Date Formatting
    
    static func formatDate(_ date: Date?, style: DateFormatter.Style = .medium) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    static func formatDateTime(_ date: Date?, dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .short) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }
    
    static func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    static func formatShortMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
    
    static func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Date Ranges
    
    static func currentMonthRange() -> (start: Date, end: Date) {
        let now = Date()
        let start = startOfMonth(for: now)
        let end = endOfMonth(for: now)
        return (start, end)
    }
    
    static func previousMonthRange() -> (start: Date, end: Date) {
        let now = Date()
        let previousMonth = addMonths(-1, to: now)
        let start = startOfMonth(for: previousMonth)
        let end = endOfMonth(for: previousMonth)
        return (start, end)
    }
    
    static func yearToDateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let startComponents = DateComponents(year: year, month: 1, day: 1)
        let start = calendar.date(from: startComponents) ?? now
        return (start, now)
    }
    
    static func lastNMonthsRange(_ months: Int) -> (start: Date, end: Date) {
        let end = Date()
        let start = addMonths(-months, to: end)
        return (start, end)
    }
    
    // MARK: - Payment Schedule Helpers
    
    static func generatePaymentScheduleDates(startDate: Date, numberOfPayments: Int) -> [Date] {
        var dates: [Date] = []
        for i in 1...numberOfPayments {
            let paymentDate = addMonths(i, to: startDate)
            dates.append(paymentDate)
        }
        return dates
    }
    
    static func isPaymentDue(_ paymentDate: Date, gracePeriodDays: Int = 7) -> Bool {
        let daysUntil = daysBetween(start: Date(), end: paymentDate)
        return daysUntil <= gracePeriodDays && daysUntil >= 0
    }
    
    static func paymentStatus(for date: Date) -> PaymentDateStatus {
        if isInPast(date) {
            return .overdue
        } else if isPaymentDue(date) {
            return .due
        } else {
            return .upcoming
        }
    }
}

// MARK: - Date Extensions

extension Date {
    var startOfMonth: Date {
        DateHelper.startOfMonth(for: self)
    }
    
    var endOfMonth: Date {
        DateHelper.endOfMonth(for: self)
    }
    
    var isToday: Bool {
        DateHelper.isToday(self)
    }
    
    var isInPast: Bool {
        DateHelper.isInPast(self)
    }
    
    var isInFuture: Bool {
        DateHelper.isInFuture(self)
    }
    
    func monthsSince(_ date: Date) -> Int {
        DateHelper.monthsBetween(start: date, end: self)
    }
    
    func daysSince(_ date: Date) -> Int {
        DateHelper.daysBetween(start: date, end: self)
    }
    
    func addingMonths(_ months: Int) -> Date {
        DateHelper.addMonths(months, to: self)
    }
    
    func addingDays(_ days: Int) -> Date {
        DateHelper.addDays(days, to: self)
    }
}

// MARK: - Payment Date Status

enum PaymentDateStatus {
    case overdue
    case due
    case upcoming
    
    var color: Color {
        switch self {
        case .overdue:
            return .red
        case .due:
            return .orange
        case .upcoming:
            return .green
        }
    }
    
    var description: String {
        switch self {
        case .overdue:
            return "Overdue"
        case .due:
            return "Due Soon"
        case .upcoming:
            return "Upcoming"
        }
    }
}

// SwiftUI Color import for PaymentDateStatus
import SwiftUI