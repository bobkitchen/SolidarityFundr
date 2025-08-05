//
//  MemberViewModel.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class MemberViewModel: ObservableObject {
    @Published var members: [Member] = []
    @Published var selectedMember: Member?
    @Published var searchText = ""
    @Published var selectedRole: MemberRole?
    @Published var selectedStatus: MemberStatus?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingError = false
    @Published var showingAddMember = false
    @Published var showingEditMember = false
    @Published var showingDeleteConfirmation = false
    @Published var validationWarnings: [String] = []
    
    // New member form fields
    @Published var newMemberName = ""
    @Published var newMemberRole = MemberRole.partTime
    @Published var newMemberEmail = ""
    @Published var newMemberPhone = ""
    @Published var newMemberJoinDate = Date()
    @Published var newMemberSMSOptIn = false
    
    private let dataManager = DataManager.shared
    private let businessRules = BusinessRulesEngine.shared
    private let fundCalculator = FundCalculator.shared
    private var cancellables = Set<AnyCancellable>()
    
    var filteredMembers: [Member] {
        var filtered = members
        
        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { member in
                member.name?.localizedCaseInsensitiveContains(searchText) ?? false ||
                member.email?.localizedCaseInsensitiveContains(searchText) ?? false ||
                member.phoneNumber?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        // Role filter
        if let role = selectedRole {
            filtered = filtered.filter { $0.memberRole == role }
        }
        
        // Status filter
        if let status = selectedStatus {
            filtered = filtered.filter { $0.memberStatus == status }
        }
        
        return filtered
    }
    
    var activeMembersCount: Int {
        members.filter { $0.memberStatus == .active }.count
    }
    
    var totalContributions: Double {
        members.reduce(0) { $0 + $1.totalContributions }
    }
    
    init() {
        setupObservers()
        // Defer loading to avoid publishing changes during view updates
        DispatchQueue.main.async { [weak self] in
            self?.loadMembers()
        }
    }
    
    private func setupObservers() {
        dataManager.$members
            .receive(on: DispatchQueue.main)
            .assign(to: &$members)
    }
    
    func loadMembers() {
        isLoading = true
        dataManager.fetchMembers()
        isLoading = false
    }
    
    // MARK: - Member Operations
    
    func addMember() {
        clearError()
        
        // Validate input
        let validation = businessRules.validateNewMember(
            name: newMemberName,
            role: newMemberRole,
            email: newMemberEmail.isEmpty ? nil : newMemberEmail,
            phoneNumber: newMemberPhone.isEmpty ? nil : newMemberPhone
        )
        
        if !validation.isValid {
            errorMessage = validation.errorMessage
            showingError = true
            return
        }
        
        validationWarnings = validation.warnings
        
        // Create member
        dataManager.createMember(
            name: newMemberName,
            role: newMemberRole,
            email: newMemberEmail.isEmpty ? nil : newMemberEmail,
            phoneNumber: newMemberPhone.isEmpty ? nil : newMemberPhone,
            joinDate: newMemberJoinDate,
            smsOptIn: newMemberSMSOptIn
        )
        
        // Reset form
        clearNewMemberForm()
        showingAddMember = false
    }
    
    func updateMember() {
        guard let member = selectedMember else { return }
        
        clearError()
        
        // Validate updates
        let validation = businessRules.validateNewMember(
            name: member.name ?? "",
            role: member.memberRole,
            email: member.email,
            phoneNumber: member.phoneNumber
        )
        
        if !validation.isValid {
            errorMessage = validation.errorMessage
            showingError = true
            return
        }
        
        dataManager.updateMember(member)
        showingEditMember = false
    }
    
    func deleteMember() {
        guard let member = selectedMember else { return }
        
        clearError()
        
        do {
            try dataManager.deleteMember(member)
            selectedMember = nil
            showingDeleteConfirmation = false
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    func suspendMember(_ member: Member) {
        clearError()
        dataManager.suspendMember(member)
    }
    
    func reactivateMember(_ member: Member) {
        clearError()
        dataManager.reactivateMember(member)
    }
    
    func cashOutMember(_ member: Member) {
        clearError()
        
        // Validate cash out
        let validation = businessRules.validateCashOut(member: member)
        
        if !validation.isValid {
            errorMessage = validation.errorMessage
            showingError = true
            return
        }
        
        let cashOutAmount = fundCalculator.calculateMemberCashOut(member: member)
        
        do {
            try dataManager.cashOutMember(member, amount: cashOutAmount)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    // MARK: - Member Details
    
    func getMemberReport(for member: Member) -> MemberReport {
        return dataManager.generateMemberReport(for: member)
    }
    
    func getMemberContributions(for member: Member) -> [MonthlyContribution] {
        return fundCalculator.calculateMemberMonthlyContributions(member: member)
    }
    
    func getMemberLoanHistory(for member: Member) -> [Loan] {
        return (member.loans?.allObjects as? [Loan] ?? [])
            .sorted { ($0.issueDate ?? Date()) > ($1.issueDate ?? Date()) }
    }
    
    func canDeleteMember(_ member: Member) -> Bool {
        return businessRules.canDeleteMember(member)
    }
    
    // MARK: - Form Management
    
    func clearNewMemberForm() {
        newMemberName = ""
        newMemberRole = .partTime
        newMemberEmail = ""
        newMemberPhone = ""
        newMemberJoinDate = Date()
        newMemberSMSOptIn = false
        validationWarnings = []
    }
    
    func prepareEditForm(for member: Member) {
        selectedMember = member
        showingEditMember = true
    }
    
    func confirmDelete(for member: Member) {
        selectedMember = member
        
        if !canDeleteMember(member) {
            errorMessage = "Cannot delete member with active loans"
            showingError = true
            return
        }
        
        showingDeleteConfirmation = true
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
}