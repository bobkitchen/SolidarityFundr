//
//  MembersListView.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//  macOS 26 Tahoe HIG Compliant
//

import SwiftUI

struct MembersListView: View {
    @StateObject private var viewModel = MemberViewModel()
    @State private var showingAddMember = false
    @State private var searchText = ""

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var memberAddedTrigger = false

    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 0) {
                    memberStatisticsHeader
                    filterBar

                    if viewModel.filteredMembers.isEmpty {
                        emptyStateView
                    } else {
                        membersList
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Members list")
            .navigationTitle("Members")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddMember = true } label: {
                        Label("Add Member", systemImage: "plus")
                    }
                    .accessibilityLabel("Add new member")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button { viewModel.loadMembers() } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityLabel("More options")
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search members")
            .sheet(isPresented: $showingAddMember) {
                AddMemberSheet(viewModel: viewModel) { memberAddedTrigger.toggle() }
            }
            .sensoryFeedback(.success, trigger: memberAddedTrigger)
            .alert("Error", isPresented: $viewModel.showingError) {
                Button("OK") { viewModel.showingError = false }
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .onReceive(NotificationCenter.default.publisher(for: .memberDataUpdated)) { _ in
                viewModel.loadMembers()
            }
            .onReceive(NotificationCenter.default.publisher(for: .paymentSaved)) { _ in
                viewModel.loadMembers()
            }
            .onReceive(NotificationCenter.default.publisher(for: .loanBalanceUpdated)) { _ in
                viewModel.loadMembers()
            }
        }
    }

    private func openMemberDetail(_ member: Member) {
        #if os(macOS)
        if let memberID = member.memberID {
            openWindow(id: "member-detail", value: memberID)
        }
        #endif
    }
    
    // MARK: - View Components
    
    private var memberStatisticsHeader: some View {
        // Compact stat strip — title and date were redundant with .navigationTitle.
        HStack(spacing: 16) {
            MiniMetricCard(
                title: "Active Members",
                value: "\(viewModel.activeMembersCount)",
                systemImage: "person.fill.checkmark",
                tint: .green
            )
            MiniMetricCard(
                title: "Total Contributions",
                value: viewModel.formatCurrency(viewModel.totalContributions),
                systemImage: "banknote.fill",
                tint: .blue
            )
            MiniMetricCard(
                title: "Members with Loans",
                value: "\(viewModel.members.filter { $0.hasActiveLoans }.count)",
                systemImage: "creditcard.fill",
                tint: .orange
            )
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
    
    private var filterBar: some View {
        VStack(spacing: 0) {
            // Native search field is provided by .searchable on the parent view.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    // Role Filter
                Menu {
                    Button("All Roles") {
                        viewModel.selectedRole = nil
                    }
                    Divider()
                    ForEach(MemberRole.allCases, id: \.self) { role in
                        Button(role.displayName) {
                            viewModel.selectedRole = role
                        }
                    }
                } label: {
                    Label(
                        viewModel.selectedRole?.displayName ?? "All Roles",
                        systemImage: "person.crop.circle"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Status Filter
                Menu {
                    Button("All Status") {
                        viewModel.selectedStatus = nil
                    }
                    Divider()
                    ForEach(MemberStatus.allCases, id: \.self) { status in
                        Button(status.displayName) {
                            viewModel.selectedStatus = status
                        }
                    }
                } label: {
                    Label(
                        viewModel.selectedStatus?.displayName ?? "All Status",
                        systemImage: "circle.fill"
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var membersList: some View {
        List {
            ForEach(viewModel.filteredMembers) { member in
                MemberRowView(member: member) {
                    openMemberDetail(member)
                }
                .contextMenu {
                    Button {
                        openMemberDetail(member)
                    } label: {
                        Label("View Details", systemImage: "person.text.rectangle")
                    }
                    
                    Divider()
                    
                    if member.memberStatus == .active {
                        Button {
                            viewModel.suspendMember(member)
                        } label: {
                            Label("Suspend Member", systemImage: "pause.circle")
                        }
                    } else if member.memberStatus == .suspended {
                        Button {
                            viewModel.reactivateMember(member)
                        } label: {
                            Label("Reactivate Member", systemImage: "play.circle")
                        }
                    }
                    
                    if viewModel.canDeleteMember(member) {
                        Divider()
                        
                        Button(role: .destructive) {
                            viewModel.confirmDelete(for: member)
                        } label: {
                            Label("Delete Member", systemImage: "trash")
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if member.memberStatus == .active {
                        Button {
                            viewModel.suspendMember(member)
                        } label: {
                            Label("Suspend", systemImage: "pause.circle.fill")
                        }
                        .tint(.orange)
                    } else if member.memberStatus == .suspended {
                        Button {
                            viewModel.reactivateMember(member)
                        } label: {
                            Label("Reactivate", systemImage: "play.circle.fill")
                        }
                        .tint(.green)
                    }
                    
                    if viewModel.canDeleteMember(member) {
                        Button(role: .destructive) {
                            viewModel.confirmDelete(for: member)
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .confirmationDialog(
            "Delete Member",
            isPresented: $viewModel.showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteMember()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this member? This action cannot be undone.")
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Members", systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text("No members match your search criteria")
        } actions: {
            Button("Add Member") {
                showingAddMember = true
            }
        }
    }
    
}

// MARK: - Member Row View

struct MemberRowView: View {
    let member: Member
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Member Avatar — SF Symbol tinted deterministically from the
                // member's name. Each member gets a stable color across sessions
                // without requiring uploaded photos.
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BrandColor.avatarTint(for: member.name))
                    .accessibilityHidden(true)
                
                // Member Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(member.name ?? "Unknown")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if member.memberStatus != .active {
                            StatusBadge(status: member.memberStatus)
                        }
                    }
                    
                    HStack {
                        Label(member.memberRole.displayName, systemImage: "briefcase.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if member.hasActiveLoans {
                            Spacer()
                            Label("Active Loan", systemImage: "creditcard.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                
                Spacer()
                
                // Contribution Info
                VStack(alignment: .trailing, spacing: 4) {
                    Text(CurrencyFormatter.shared.format(member.totalContributions))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()

                    Text("Contributions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Member Sheet

struct AddMemberSheet: View {
    @ObservedObject var viewModel: MemberViewModel
    var onAdded: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, email, phone
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Member Information") {
                    TextField("Full Name", text: $viewModel.newMemberName)
                        .focused($focusedField, equals: .name)
                        .textContentType(.name)
                    
                    Picker("Role", selection: $viewModel.newMemberRole) {
                        ForEach(MemberRole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                }
                
                Section("Contact Information") {
                    TextField("Email (Optional)", text: $viewModel.newMemberEmail)
                        .focused($focusedField, equals: .email)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        #endif
                    
                    HStack {
                        TextField("Phone Number (Optional)", text: $viewModel.newMemberPhone)
                            .focused($focusedField, equals: .phone)
                            .textContentType(.telephoneNumber)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                        
                        if !viewModel.newMemberPhone.isEmpty {
                            Image(systemName: PhoneNumberValidator.validate(viewModel.newMemberPhone) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(PhoneNumberValidator.validate(viewModel.newMemberPhone) ? .green : .red)
                        }
                    }
                    
                    if !viewModel.newMemberPhone.isEmpty && !PhoneNumberValidator.validate(viewModel.newMemberPhone) {
                        Text("Please enter a valid Kenyan phone number")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    Toggle("SMS Notifications", isOn: $viewModel.newMemberSMSOptIn)
                        .disabled(viewModel.newMemberPhone.isEmpty || !PhoneNumberValidator.validate(viewModel.newMemberPhone))
                    
                    if viewModel.newMemberSMSOptIn && PhoneNumberValidator.validate(viewModel.newMemberPhone) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                            Text("Member will receive monthly statements via SMS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Employment Details") {
                    DatePicker("Start Date", selection: $viewModel.newMemberJoinDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
                
                if !viewModel.validationWarnings.isEmpty {
                    Section {
                        ForEach(viewModel.validationWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("New Member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.addMember()
                        if !viewModel.showingError {
                            onAdded?()
                            dismiss()
                        }
                    }
                    .disabled(viewModel.newMemberName.isEmpty)
                }
            }
        }
        .onAppear {
            focusedField = .name
        }
    }
}

// MARK: - Supporting Views

struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StatusBadge: View {
    let status: MemberStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    private var backgroundColor: Color {
        switch status {
        case .active:
            return .green.opacity(0.2)
        case .suspended:
            return .orange.opacity(0.2)
        case .inactive:
            return .gray.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch status {
        case .active:
            return .green
        case .suspended:
            return .orange
        case .inactive:
            return .gray
        }
    }
}

#Preview {
    MembersListView()
        .environmentObject(DataManager.shared)
}