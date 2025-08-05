//
//  BatchStatementView.swift
//  SolidarityFundr
//
//  Created on 7/25/25.
//

import SwiftUI

struct BatchStatementView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedMembers: Set<Member> = []
    @State private var selectAll = false
    @State private var filterOption: FilterOption = .active
    @State private var statementStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var statementEndDate = Date()
    @State private var isGenerating = false
    @State private var showingProgress = false
    @State private var currentProgress = 0
    @State private var totalProgress = 0
    @State private var showingSuccess = false
    @State private var generatedStatements: [(member: Member, pdfData: Data)] = []
    
    enum FilterOption: String, CaseIterable {
        case active = "Active Members"
        case all = "All Members"
        case withPhone = "Members with Phone"
        case neverSent = "Never Sent Statement"
        
        var icon: String {
            switch self {
            case .active: return "person.crop.circle.badge.checkmark"
            case .all: return "person.3"
            case .withPhone: return "phone.fill"
            case .neverSent: return "paperplane.circle"
            }
        }
    }
    
    var filteredMembers: [Member] {
        let members = dataManager.members
        
        switch filterOption {
        case .active:
            return members.filter { $0.memberStatus == .active }
        case .all:
            return members
        case .withPhone:
            return members.filter { $0.phoneNumber != nil && !$0.phoneNumber!.isEmpty }
        case .neverSent:
            return members.filter { $0.lastStatementSentDate == nil }
        }
    }
    
    var selectedCount: Int {
        selectedMembers.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Date Range Selector
            dateRangeSelector
            
            // Filter Options
            filterBar
            
            // Members List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredMembers) { member in
                        MemberSelectionRow(
                            member: member,
                            isSelected: selectedMembers.contains(member),
                            onToggle: { toggleMember(member) }
                        )
                    }
                }
                .padding()
            }
            
            // Bottom Action Bar
            actionBar
        }
        .frame(width: 700, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingProgress) {
            ProgressView()
        }
        .sheet(isPresented: $showingSuccess) {
            SuccessView(
                count: generatedStatements.count,
                onShare: shareStatements,
                onDismiss: { dismiss() }
            )
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Batch Statement Generation")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Select members to generate statements for")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var dateRangeSelector: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                DatePicker("From", selection: $statementStartDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                
                Text("–")
                    .foregroundColor(.secondary)
                
                DatePicker("To", selection: $statementEndDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var filterBar: some View {
        HStack(spacing: 16) {
            // Filter Options
            HStack(spacing: 8) {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    FilterButton(
                        option: option,
                        isSelected: filterOption == option,
                        action: { filterOption = option }
                    )
                }
            }
            
            Spacer()
            
            // Select All Toggle
            Button {
                toggleSelectAll()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectAll ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                    Text("Select All")
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var actionBar: some View {
        HStack {
            Text("\(selectedCount) member\(selectedCount == 1 ? "" : "s") selected")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)
            
            Button {
                generateStatements()
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.on.doc.fill")
                    }
                    Text("Generate \(selectedCount) Statement\(selectedCount == 1 ? "" : "s")")
                }
            }
            .keyboardShortcut(.return)
            .disabled(selectedMembers.isEmpty || isGenerating)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Helper Methods
    
    private func toggleMember(_ member: Member) {
        if selectedMembers.contains(member) {
            selectedMembers.remove(member)
        } else {
            selectedMembers.insert(member)
        }
        
        // Update select all state
        selectAll = selectedMembers.count == filteredMembers.count
    }
    
    private func toggleSelectAll() {
        if selectAll {
            selectedMembers.removeAll()
        } else {
            selectedMembers = Set(filteredMembers)
        }
        selectAll.toggle()
    }
    
    private func generateStatements() {
        isGenerating = true
        showingProgress = true
        totalProgress = selectedMembers.count
        currentProgress = 0
        generatedStatements.removeAll()
        
        Task {
            let pdfGenerator = PDFGenerator()
            
            for member in selectedMembers {
                do {
                    let pdfURL = try await pdfGenerator.generateReport(
                        type: .memberStatement,
                        dataManager: dataManager,
                        member: member,
                        startDate: statementStartDate,
                        endDate: statementEndDate
                    )
                    
                    let pdfData = try Data(contentsOf: pdfURL)
                    
                    await MainActor.run {
                        generatedStatements.append((member: member, pdfData: pdfData))
                        currentProgress += 1
                    }
                    
                    // Clean up temporary file
                    try? FileManager.default.removeItem(at: pdfURL)
                    
                    // Record the generation
                    try await StatementService.shared.recordWhatsAppShare(for: member, pdfData: pdfData)
                    
                } catch {
                    print("Failed to generate statement for \(member.name ?? "Unknown"): \(error)")
                }
            }
            
            await MainActor.run {
                isGenerating = false
                showingProgress = false
                showingSuccess = true
            }
        }
    }
    
    private func shareStatements() {
        guard let window = NSApp.windows.first,
              let contentView = window.contentView else { return }
        
        WhatsAppSharingService.shared.shareBatchStatements(
            generatedStatements,
            in: contentView
        )
    }
}

// MARK: - Supporting Views

struct MemberSelectionRow: View {
    let member: Member
    let isSelected: Bool
    let onToggle: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 8) {
                        Text(member.memberRole.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if member.phoneNumber != nil {
                            Image(systemName: "phone.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        
                        if let lastSent = member.lastStatementSentDate {
                            Text("• Last sent: \(DateHelper.formatShortDate(lastSent))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if member.memberStatus != .active {
                    Text(member.memberStatus.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct FilterButton: View {
    let option: BatchStatementView.FilterOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(.caption)
                Text(option.rawValue)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct SuccessView: View {
    let count: Int
    let onShare: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Statements Generated")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("\(count) statement\(count == 1 ? "" : "s") successfully generated")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.escape)
                
                Button {
                    onShare()
                    onDismiss()
                } label: {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("Share via WhatsApp")
                    }
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(40)
        .frame(width: 400)
    }
}

// MARK: - Progress View

struct BatchProgressView: View {
    let current: Int
    let total: Int
    
    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Generating Statements")
                .font(.headline)
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            
            Text("\(current) of \(total)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
}