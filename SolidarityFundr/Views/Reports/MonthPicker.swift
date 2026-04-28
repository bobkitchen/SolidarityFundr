//
//  MonthPicker.swift
//  SolidarityFundr
//
//  Single dropdown that scopes a report to a specific calendar month.
//  Replaces the old date-range double-picker, which was easy to bracket
//  wrong for what's always a one-month statement.
//

#if os(macOS)

import SwiftUI

struct MonthPicker: View {
    @Binding var selection: StatementMonth

    /// Two years' worth of months is plenty for a household-scale fund;
    /// the menu stays scrollable but never absurd.
    private let months: [StatementMonth] = StatementMonth.recent(count: 24)

    var body: some View {
        Menu {
            ForEach(months) { month in
                Button {
                    selection = month
                } label: {
                    if month == selection {
                        Label(month.displayName, systemImage: "checkmark")
                    } else {
                        Text(month.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.displayName)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

#endif
