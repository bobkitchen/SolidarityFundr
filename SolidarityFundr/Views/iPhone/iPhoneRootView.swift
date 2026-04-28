//
//  iPhoneRootView.swift
//  SolidarityFundr
//
//  iPhone shell — three-tab navigation focused on the on-the-go work
//  model: see what needs attention (Today), find a member or record a
//  payment (Members), and tweak preferences (Settings).
//
//  Loans / Payments / Reports / History remain Mac-only or
//  Mac-primary because their day-to-day on-the-phone use is rare.
//  Members provides drill-down to a specific member's loans, payments,
//  and history without dedicating tabs to each.
//

#if !os(macOS)

import SwiftUI

struct iPhoneRootView: View {
    @EnvironmentObject var dataManager: DataManager

    enum Tab: Hashable { case today, members, settings }
    @State private var selection: Tab = .today

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                OverviewView(onViewAllTransactions: {})
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(Tab.today)

            NavigationStack {
                MembersListView()
            }
            .tabItem { Label("Members", systemImage: "person.2") }
            .tag(Tab.members)

            iPhoneSettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
    }
}

#endif
