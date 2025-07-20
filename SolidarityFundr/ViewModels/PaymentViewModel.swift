//
//  PaymentViewModel.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class PaymentViewModel: ObservableObject {
    @Published var payments: [Payment] = []
    @Published var selectedPayment: Payment?
    @Published var searchText = ""
    @Published var filterType: PaymentType?
    @Published var filterMethod: PaymentMethod?
    @Published var startDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @Published var endDate = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingError = false
    @Published var showingNewPayment = false
    @Published var showingPaymentDetails = false
    @Published var validationWarnings: [String] = []
    
    // New payment form fields
    @Published var selectedMember: Member?
    @Published var paymentAmount: String = ""
    @Published var paymentMethod = PaymentMethod.cash
    @Published var paymentNotes = ""
    @Published var isLoanPayment = false
    @Published var selectedLoan: Loan?
    @Published var paymentDate = Date()
    
    // Payment breakdown
    @Published var contributionAmount: Double = 0
    @Published var loanRepaymentAmount: Double = 0
    
    private let dataManager = DataManager.shared
    private let businessRules = BusinessRulesEngine.shared
    private var cancellables = Set<AnyCancellable>()
    
    var filteredPayments: [Payment] {
        var filtered = payments
        
        // Date filter
        filtered = filtered.filter { payment in
            guard let paymentDate = payment.paymentDate else { return false }
            return paymentDate >= startDate && paymentDate <= endDate
        }
        
        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { payment in
                payment.member?.name?.localizedCaseInsensitiveContains(searchText) ?? false ||
                payment.notes?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        // Type filter
        if let type = filterType {
            filtered = filtered.filter { $0.paymentType == type }
        }
        
        // Method filter
        if let method = filterMethod {
            filtered = filtered.filter { $0.paymentMethodType == method }
        }
        
        return filtered.sorted { ($0.paymentDate ?? Date()) > ($1.paymentDate ?? Date()) }
    }
    
    var totalPaymentsAmount: Double {
        filteredPayments.reduce(0) { $0 + $1.amount }
    }
    
    var totalContributions: Double {
        filteredPayments.reduce(0) { $0 + $1.contributionAmount }
    }
    
    var totalLoanRepayments: Double {
        filteredPayments.reduce(0) { $0 + $1.loanRepaymentAmount }
    }
    
    var membersWithActiveLoans: [Member] {
        dataManager.members.filter { $0.hasActiveLoans }
    }
    
    var paymentSummary: PaymentSummary {
        PaymentSummary(
            totalAmount: totalPaymentsAmount,
            totalContributions: totalContributions,
            totalLoanRepayments: totalLoanRepayments,
            paymentCount: filteredPayments.count,
            averagePayment: filteredPayments.isEmpty ? 0 : totalPaymentsAmount / Double(filteredPayments.count)
        )
    }
    
    init() {
        setupObservers()
        // Defer loading to avoid publishing changes during view updates
        DispatchQueue.main.async { [weak self] in
            self?.loadPayments()
        }
    }
    
    private func setupObservers() {
        // Observe member selection changes
        $selectedMember
            .sink { [weak self] member in
                self?.updateAvailableLoans(for: member)
                self?.calculatePaymentBreakdown()
            }
            .store(in: &cancellables)
        
        // Observe payment amount changes
        $paymentAmount
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.calculatePaymentBreakdown()
            }
            .store(in: &cancellables)
        
        // Observe loan payment toggle
        $isLoanPayment
            .sink { [weak self] _ in
                self?.calculatePaymentBreakdown()
            }
            .store(in: &cancellables)
        
        // Observe selected loan changes
        $selectedLoan
            .sink { [weak self] _ in
                self?.calculatePaymentBreakdown()
            }
            .store(in: &cancellables)
    }
    
    func loadPayments() {
        isLoading = true
        
        let request = Payment.paymentsBetween(startDate: startDate, endDate: endDate)
        do {
            payments = try PersistenceController.shared.container.viewContext.fetch(request)
        } catch {
            errorMessage = "Failed to load payments: \(error.localizedDescription)"
            showingError = true
        }
        
        isLoading = false
    }
    
    // MARK: - Payment Operations
    
    func processPayment() {
        clearError()
        
        guard let member = selectedMember,
              let amount = Double(paymentAmount) else {
            errorMessage = "Please select a member and enter a valid amount"
            showingError = true
            return
        }
        
        let paymentType: PaymentType = isLoanPayment ? .loanRepayment : .contribution
        
        // Validate payment
        let validation = businessRules.validatePayment(
            member: member,
            amount: amount,
            loan: selectedLoan,
            paymentType: paymentType
        )
        
        if !validation.isValid {
            errorMessage = validation.errorMessage
            showingError = true
            return
        }
        
        if validation.hasWarnings {
            validationWarnings = validation.warnings
        }
        
        do {
            let payment = try dataManager.processPayment(
                for: member,
                amount: amount,
                loan: selectedLoan,
                method: paymentMethod,
                paymentDate: paymentDate,
                notes: paymentNotes.isEmpty ? nil : paymentNotes
            )
            
            clearNewPaymentForm()
            showingNewPayment = false
            selectedPayment = payment
            showingPaymentDetails = true
            
            loadPayments()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    // MARK: - Payment Calculations
    
    private func updateAvailableLoans(for member: Member?) {
        guard let member = member else {
            selectedLoan = nil
            return
        }
        
        let activeLoans = member.activeLoans
        if activeLoans.isEmpty {
            selectedLoan = nil
            isLoanPayment = false
        } else if activeLoans.count == 1 {
            selectedLoan = activeLoans.first
        }
    }
    
    private func calculatePaymentBreakdown() {
        guard let amount = Double(paymentAmount), amount > 0 else {
            contributionAmount = 0
            loanRepaymentAmount = 0
            return
        }
        
        if isLoanPayment && selectedLoan != nil {
            // For loan payments, entire amount goes to loan
            contributionAmount = 0
            loanRepaymentAmount = amount
        } else {
            // For contribution-only payments
            contributionAmount = amount
            loanRepaymentAmount = 0
        }
    }
    
    // MARK: - Payment History
    
    func getPaymentsByMember(_ member: Member) -> [Payment] {
        return payments.filter { $0.member == member }
            .sorted { ($0.paymentDate ?? Date()) > ($1.paymentDate ?? Date()) }
    }
    
    func getPaymentsByDate(_ date: Date) -> [Payment] {
        let calendar = Calendar.current
        return payments.filter { payment in
            guard let paymentDate = payment.paymentDate else { return false }
            return calendar.isDate(paymentDate, inSameDayAs: date)
        }
    }
    
    func exportPayments() -> String {
        var csv = "Date,Member,Amount,Type,Method,Contribution,Loan Repayment,Notes\n"
        
        for payment in filteredPayments {
            let date = formatDate(payment.paymentDate)
            let member = payment.member?.name ?? "Unknown"
            let amount = formatCurrency(payment.amount)
            let type = payment.paymentType.displayName
            let method = payment.paymentMethodType.displayName
            let contribution = formatCurrency(payment.contributionAmount)
            let loanRepayment = formatCurrency(payment.loanRepaymentAmount)
            let notes = payment.notes ?? ""
            
            csv += "\"\(date)\",\"\(member)\",\"\(amount)\",\"\(type)\",\"\(method)\",\"\(contribution)\",\"\(loanRepayment)\",\"\(notes)\"\n"
        }
        
        return csv
    }
    
    // MARK: - Form Management
    
    func clearNewPaymentForm() {
        selectedMember = nil
        paymentAmount = ""
        paymentMethod = .cash
        paymentNotes = ""
        isLoanPayment = false
        selectedLoan = nil
        contributionAmount = 0
        loanRepaymentAmount = 0
        validationWarnings = []
    }
    
    func prepareNewPayment() {
        clearNewPaymentForm()
        showingNewPayment = true
    }
    
    func selectPayment(_ payment: Payment) {
        selectedPayment = payment
        showingPaymentDetails = true
    }
    
    private func clearError() {
        errorMessage = nil
        showingError = false
    }
    
    // MARK: - Formatting Helpers
    
    func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "KES"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "KSH 0"
    }
    
    func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Payment Summary Model

struct PaymentSummary {
    let totalAmount: Double
    let totalContributions: Double
    let totalLoanRepayments: Double
    let paymentCount: Int
    let averagePayment: Double
}