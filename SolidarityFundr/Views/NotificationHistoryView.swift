//
//  NotificationHistoryView.swift
//  SolidarityFundr
//
//  Created on 7/23/25.
//

import SwiftUI
import CoreData

struct NotificationHistoryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \NotificationHistory.sentDate, ascending: false)],
        animation: .default)
    private var notifications: FetchedResults<NotificationHistory>
    
    @State private var selectedFilter: NotificationFilter = .all
    @State private var searchText = ""
    @State private var selectedMember: Member?
    @State private var dateRange = DateRange.lastMonth
    
    enum NotificationFilter: String, CaseIterable {
        case all = "All"
        case sent = "Sent"
        case delivered = "Delivered"
        case failed = "Failed"
        case pending = "Pending"
        
        var icon: String {
            switch self {
            case .all: return "tray.2"
            case .sent: return "paperplane"
            case .delivered: return "checkmark.circle"
            case .failed: return "xmark.circle"
            case .pending: return "clock"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .blue
            case .sent: return .blue
            case .delivered: return .green
            case .failed: return .red
            case .pending: return .orange
            }
        }
    }
    
    enum DateRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case lastMonth = "Last Month"
        case last3Months = "Last 3 Months"
        case allTime = "All Time"
        
        var startDate: Date {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .today:
                return calendar.startOfDay(for: now)
            case .week:
                return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            case .lastMonth:
                return calendar.date(byAdding: .month, value: -1, to: now) ?? now
            case .last3Months:
                return calendar.date(byAdding: .month, value: -3, to: now) ?? now
            case .allTime:
                return Date.distantPast
            }
        }
    }
    
    var filteredNotifications: [NotificationHistory] {
        notifications.filter { notification in
            // Date filter
            guard let sentDate = notification.sentDate,
                  sentDate >= dateRange.startDate else { return false }
            
            // Status filter
            if selectedFilter != .all {
                guard notification.status == selectedFilter.rawValue.lowercased() else { return false }
            }
            
            // Member filter
            if let selectedMember = selectedMember {
                guard notification.member == selectedMember else { return false }
            }
            
            // Search filter
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return notification.member?.name?.lowercased().contains(searchLower) ?? false ||
                       notification.recipient?.lowercased().contains(searchLower) ?? false ||
                       notification.messageContent?.lowercased().contains(searchLower) ?? false
            }
            
            return true
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Filters
            filterSection
            
            // Statistics
            statisticsView
            
            // Notifications List
            if filteredNotifications.isEmpty {
                emptyStateView
            } else {
                notificationsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Communication History")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text("SMS Notifications")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            }
            
            Text(Date().formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundColor(Color.secondary.opacity(0.7))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
    
    private var filterSection: some View {
        VStack(spacing: 12) {
            // Search and Member Filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search notifications...", text: $searchText)
                    .textFieldStyle(.plain)
                
                Picker("Member", selection: $selectedMember) {
                    Text("All Members").tag(nil as Member?)
                    ForEach(fetchMembers(), id: \.self) { member in
                        Text(member.name ?? "Unknown").tag(member as Member?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                
                Picker("Date Range", selection: $dateRange) {
                    ForEach(DateRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // Status Filter
            HStack {
                ForEach(NotificationFilter.allCases, id: \.self) { filter in
                    FilterChip(
                        title: filter.rawValue,
                        icon: filter.icon,
                        isSelected: selectedFilter == filter,
                        color: filter.color
                    ) {
                        selectedFilter = filter
                    }
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var statisticsView: some View {
        HStack(spacing: 16) {
            NotificationStatCard(
                title: "Total Sent",
                value: "\(filteredNotifications.count)",
                icon: "paperplane.fill",
                color: .blue
            )
            
            NotificationStatCard(
                title: "Delivered",
                value: "\(deliveredCount)",
                icon: "checkmark.circle.fill",
                color: .green
            )
            
            NotificationStatCard(
                title: "Failed",
                value: "\(failedCount)",
                icon: "xmark.circle.fill",
                color: .red
            )
            
            NotificationStatCard(
                title: "Total Cost",
                value: CurrencyFormatter.shared.format(totalCost),
                icon: "creditcard.fill",
                color: .purple
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredNotifications) { notification in
                    NotificationRow(notification: notification)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No notifications found")
                .font(.headline)
            
            Text("Notifications will appear here once SMS statements are sent")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Helper Properties
    
    private var deliveredCount: Int {
        filteredNotifications.filter { $0.status == "delivered" }.count
    }
    
    private var failedCount: Int {
        filteredNotifications.filter { $0.status == "failed" }.count
    }
    
    private var totalCost: Double {
        filteredNotifications.reduce(0) { $0 + $1.cost }
    }
    
    private func fetchMembers() -> [Member] {
        let request: NSFetchRequest<Member> = Member.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Member.name, ascending: true)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching members: \(error)")
            return []
        }
    }
}

// MARK: - Supporting Views

struct NotificationRow: View {
    let notification: NotificationHistory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                // Status Icon
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(notification.member?.name ?? "Unknown Member")
                            .font(.headline)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(notification.type ?? "statement")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Text(notification.recipient ?? "No recipient")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if let sentDate = notification.sentDate {
                        Text(DateHelper.formatDate(sentDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if notification.cost > 0 {
                        Text(CurrencyFormatter.shared.format(notification.cost))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            
            // Message Preview
            if let content = notification.messageContent {
                Text(content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Error Message
            if let error = notification.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Report Link
            if let url = notification.reportURL {
                HStack {
                    Image(systemName: "link")
                        .font(.caption)
                    
                    Text(url)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var statusIcon: String {
        switch notification.status {
        case "delivered":
            return "checkmark.circle.fill"
        case "sent":
            return "paperplane.fill"
        case "failed":
            return "xmark.circle.fill"
        case "pending":
            return "clock.fill"
        default:
            return "questionmark.circle"
        }
    }
    
    private var statusColor: Color {
        switch notification.status {
        case "delivered":
            return .green
        case "sent":
            return .blue
        case "failed":
            return .red
        case "pending":
            return .orange
        default:
            return .gray
        }
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? color : .secondary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct NotificationStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Spacer()
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    NotificationHistoryView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}