//
//  LoanViewModel.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class LoanViewModel: ObservableObject {
    @Published var loans: [Loan] = []
    @Published var selectedLoan: Loan?
    @Published var searchText = ""
    @Published var filterStatus: LoanStatus?
    @Published var showOverdueOnly = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingError = false
    @Published var showingNewLoan = false
    @Published var showingLoanDetails = false
    @Published var validationWarnings: [String] = []
    @Published var showWarningDialog = false
    
    // New loan form fields
    @Published var selectedMember: Member?
    @Published var loanAmount: String = ""
    @Published var repaymentMonths = 3
    @Published var loanNotes = ""
    @Published var loanSchedule: [LoanPaymentSchedule] = []
    @Published var loanIssueDate = Date()
    
    // Fund status
    @Published var fundBalance: Double = 0
    @Published var utilizationPercentage: Double = 0
    @Published var utilizationWarning = false
    @Published var balanceWarning = false
    
    private let dataManager = DataManager.shared
    private let businessRules = BusinessRulesEngine.shared
    private let fundCalculator = FundCalculator.shared
    private var cancellables = Set<AnyCancellable>()
    
    var filteredLoans: [Loan] {
        var filtered = loans
        
        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { loan in
                loan.member?.name?.localizedCaseInsensitiveContains(searchText) ?? false ||
                loan.notes?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        // Status filter
        if let status = filterStatus {
            filtered = filtered.filter { $0.loanStatus == status }
        }
        
        // Overdue filter
        if showOverdueOnly {
            filtered = filtered.filter { $0.isOverdue }
        }
        
        return filtered.sorted { ($0.issueDate ?? Date()) > ($1.issueDate ?? Date()) }
    }
    
    var activeLoans: [Loan] {
        loans.filter { $0.loanStatus == .active }
    }
    
    var totalActiveLoansAmount: Double {
        activeLoans.reduce(0) { $0 + $1.balance }
    }
    
    var overdueLoans: [Loan] {
        activeLoans.filter { $0.isOverdue }
    }
    
    var eligibleMembers: [Member] {
        dataManager.members.filter { $0.isEligibleForLoan }
    }
    
    init() {
        setupObservers()
        // Defer loading to avoid publishing changes during view updates
        DispatchQueue.main.async { [weak self] in
            self?.loadLoans()
            self?.updateFundStatus()
        }
    }
    
    private func setupObservers() {
        dataManager.$activeLoans
            .receive(on: DispatchQueue.main)
            .assign(to: &$loans)
        
        dataManager.$fundSettings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateFundStatus()
            }
            .store(in: &cancellables)
    }
    
    func loadLoans() {
        isLoading = true
        dataManager.fetchActiveLoans()
        isLoading = false
    }
    
    private func updateFundStatus() {
        fundBalance = fundCalculator.calculateFundBalance()
        utilizationPercentage = fundCalculator.calculateUtilizationPercentage()
        
        if let settings = dataManager.fundSettings {
            utilizationWarning = businessRules.shouldWarnFundUtilization(settings)
            balanceWarning = businessRules.shouldWarnMinimumBalance(settings)
        }
    }
    
    // MARK: - Loan Operations
    
    func createLoan() {
        clearError()
        
        guard let member = selectedMember,
              let amount = Double(loanAmount) else {
            errorMessage = "Please select a member and enter a valid amount"
            showingError = true
            return
        }
        
        // Validate loan
        let validation = businessRules.validateLoanRequest(
            member: member,
            amount: amount,
            repaymentMonths: repaymentMonths,
            fundSettings: dataManager.fundSettings
        )
        
        if !validation.isValid {
            errorMessage = validation.errorMessage
            showingError = true
            return
        }
        
        if validation.hasWarnings {
            validationWarnings = validation.warnings
            showWarningDialog = true
            return
        }
        
        proceedWithLoanCreation()
    }
    
    func proceedWithLoanCreation() {
        guard let member = selectedMember,
              let amount = Double(loanAmount) else { return }
        
        do {
            let loan = try dataManager.createLoan(
                for: member,
                amount: amount,
                repaymentMonths: repaymentMonths,
                issueDate: loanIssueDate,
                notes: loanNotes.isEmpty ? nil : loanNotes
            )
            
            clearNewLoanForm()
            showingNewLoan = false
            selectedLoan = loan
            showingLoanDetails = true
            
            updateFundStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    func completeLoan(_ loan: Loan) {
        clearError()
        dataManager.completeLoan(loan)
        updateFundStatus()
    }
    
    // MARK: - Loan Calculations
    
    func calculateLoanDetails() {
        guard selectedMember != nil,
              let amount = Double(loanAmount),
              amount > 0 else {
            loanSchedule = []
            return
        }
        
        loanSchedule = fundCalculator.calculateLoanSchedule(
            amount: amount,
            months: repaymentMonths,
            startDate: loanIssueDate
        )
    }
    
    func getMaxLoanAmount(for member: Member?) -> Double {
        guard let member = member else { return 0 }
        return businessRules.calculateMaxLoanAmount(for: member)
    }
    
    func getMonthlyPayment(for amount: Double) -> Double {
        return businessRules.calculateMonthlyPayment(
            loanAmount: amount,
            months: repaymentMonths
        )
    }
    
    // MARK: - Loan Details
    
    func getLoanPayments(_ loan: Loan) -> [Payment] {
        return (loan.payments?.allObjects as? [Payment] ?? [])
            .sorted { ($0.paymentDate ?? Date()) > ($1.paymentDate ?? Date()) }
    }
    
    func getLoanSummary(_ loan: Loan) -> LoanSummary {
        let payments = getLoanPayments(loan)
        let totalPaid = payments.reduce(0) { $0 + $1.loanRepaymentAmount }
        let remainingPayments = loan.remainingPayments
        
        return LoanSummary(
            loan: loan,
            totalPaid: totalPaid,
            remainingBalance: loan.balance,
            completionPercentage: loan.completionPercentage,
            remainingPayments: remainingPayments,
            nextPaymentDue: loan.nextPaymentDue,
            isOverdue: loan.isOverdue,
            paymentHistory: payments
        )
    }
    
    // MARK: - Form Management
    
    func clearNewLoanForm() {
        selectedMember = nil
        loanAmount = ""
        repaymentMonths = 3
        loanNotes = ""
        loanSchedule = []
        validationWarnings = []
    }
    
    func prepareNewLoan() {
        clearNewLoanForm()
        showingNewLoan = true
    }
    
    func selectLoan(_ loan: Loan) {
        selectedLoan = loan
        showingLoanDetails = true
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
        return formatter.string(from: date)
    }
    
    func formatPercentage(_ value: Double) -> String {
        return String(format: "%.1f%%", value * 100)
    }
}

// MARK: - Loan Summary Model

struct LoanSummary {
    let loan: Loan
    let totalPaid: Double
    let remainingBalance: Double
    let completionPercentage: Double
    let remainingPayments: Int
    let nextPaymentDue: Date?
    let isOverdue: Bool
    let paymentHistory: [Payment]
}