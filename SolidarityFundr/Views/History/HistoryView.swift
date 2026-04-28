//
//  HistoryView.swift
//  SolidarityFundr
//
//  Chronological audit-log timeline. Surfaces the CD_AuditLog records
//  that DataManager already writes on every mutation (member created /
//  modified / suspended / cashed-out / deleted, loan created, payment
//  recorded, interest applied) so the admin has a "what did I change
//  last week?" view they couldn't get before.
//
//  Append-only by policy — the AuditLogger has no public delete API.
//

import SwiftUI
import CoreData

struct HistoryView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AuditLog.timestamp, ascending: false)],
        animation: .default
    )
    private var entries: FetchedResults<AuditLog>

    @State private var searchText: String = ""
    @State private var selectedFilter: EventFilter = .all

    enum EventFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case members = "Members"
        case loans = "Loans"
        case payments = "Payments"
        case fund = "Fund"
        case security = "Security"
        var id: Self { self }
    }

    private var filteredEntries: [AuditLog] {
        let entries = Array(entries)
        let byCategory = entries.filter { entry in
            guard let raw = entry.eventType,
                  let type = AuditLogger.AuditEventType(rawValue: raw) else { return false }
            switch selectedFilter {
            case .all:
                return true
            case .members:
                return [.memberCreated, .memberModified, .memberSuspended,
                        .memberReactivated, .memberCashedOut, .memberDeleted]
                    .contains(type)
            case .loans:
                return [.loanCreated, .loanModified].contains(type)
            case .payments:
                return [.paymentCreated].contains(type)
            case .fund:
                return [.interestApplied, .settingsChanged,
                        .dataExported, .dataImported].contains(type)
            case .security:
                return [.authentication, .accessDenied, .sessionTimeout,
                        .securitySettingsChanged].contains(type)
            }
        }

        guard !searchText.isEmpty else { return byCategory }
        let needle = searchText.lowercased()
        return byCategory.filter {
            ($0.details ?? "").lowercased().contains(needle)
                || ($0.eventType ?? "").lowercased().contains(needle)
        }
    }

    /// Group entries by calendar day (in the user's locale) for the
    /// "Today / Yesterday / Apr 26, 2026" section headers.
    private var groupedEntries: [(date: Date, entries: [AuditLog])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { entry -> Date in
            calendar.startOfDay(for: entry.timestamp ?? Date())
        }
        return groups
            .map { (date: $0.key, entries: $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Member additions, loans, and payments will appear here as they happen.")
                )
            } else if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No matches",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different filter or search term.")
                )
            } else {
                timeline
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search history")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(EventFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        List {
            ForEach(groupedEntries, id: \.date) { group in
                Section {
                    ForEach(group.entries, id: \.eventID) { entry in
                        HistoryRow(entry: entry)
                    }
                } header: {
                    Text(dayHeader(for: group.date))
                        .font(.callout.weight(.medium))
                }
            }
        }
        .listStyle(.inset)
    }

    private func dayHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let f = DateFormatter()
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            f.dateFormat = "EEEE, MMM d"
        } else {
            f.dateFormat = "EEEE, MMM d, yyyy"
        }
        return f.string(from: date)
    }
}

// MARK: - HistoryRow

struct HistoryRow: View {
    let entry: AuditLog

    private var eventType: AuditLogger.AuditEventType? {
        guard let raw = entry.eventType else { return nil }
        return AuditLogger.AuditEventType(rawValue: raw)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: eventType?.systemImage ?? "questionmark.circle")
                .foregroundStyle(eventType?.tint ?? .secondary)
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.eventType ?? "Unknown event")
                        .font(.callout.weight(.medium))
                    Spacer()
                    if let timestamp = entry.timestamp {
                        Text(timestamp, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if let details = entry.details, !details.isEmpty {
                    Text(details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if entry.amount != 0 {
                    Text(CurrencyFormatter.shared.format(entry.amount))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
