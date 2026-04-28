//
//  SolidarityFundrApp.swift
//  SolidarityFundr
//
//  Created by Bob Kitchen on 7/19/25.
//

import SwiftUI

@main
struct SolidarityFundrApp: App {

    let persistenceController: PersistenceController

    init() {
        // Subscribe the sync manager to NSPersistentCloudKitContainer events
        // BEFORE the container loads stores. The setup / first-import / first-
        // export events fire during loadPersistentStores; if the lazy singleton
        // came alive later (e.g., when the UI first showed the sync panel), the
        // observer would miss them and "Last sync: never" would persist forever.
        _ = CloudKitSyncManager.shared
        self.persistenceController = PersistenceController.shared
    }

    @StateObject private var dataManager = DataManager.shared
    @StateObject private var authManager = AuthenticationManager.shared

    var body: some Scene {
        // MARK: - Main Window
        WindowGroup {
            Group {
                if authManager.isAuthenticated && !authManager.isLocked {
                    DashboardView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(dataManager)
                        .environmentObject(authManager)
                        .onAppear {
                            // Run reconciliation on app startup
                            dataManager.reconcileAllTransactions()
                        }
                } else {
                    AuthenticationView()
                        .environmentObject(authManager)
                }
            }
            .animation(.easeInOut, value: authManager.isAuthenticated)
            #if os(macOS)
            .frame(minWidth: 900, minHeight: 700)
            #endif
        }
        #if os(macOS)
        // Stock window. SwiftUI + NavigationSplitView handle title-bar / toolbar
        // chrome and Liquid Glass on macOS 26 automatically. No NSWindow surgery
        // needed — the previous WindowConfigurator forced `.fullSizeContentView`
        // which let the sidebar selection highlight bleed under the title bar.
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Member") {
                    NotificationCenter.default.post(name: .newMemberRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Loan") {
                    NotificationCenter.default.post(name: .newLoanRequested, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("New Payment") {
                    NotificationCenter.default.post(name: .newPaymentRequested, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
        #endif

        // MARK: - Member Detail Window
        WindowGroup(id: "member-detail", for: UUID.self) { $memberID in
            MemberWindowView(memberID: memberID)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(dataManager)
        }
        #if os(macOS)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 700, height: 800)
        #endif

        // MARK: - Loan Detail Window
        WindowGroup(id: "loan-detail", for: UUID.self) { $loanID in
            LoanWindowView(loanID: loanID)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(dataManager)
        }
        #if os(macOS)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 650, height: 700)
        #endif

        // MARK: - Settings Window (⌘,)
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(dataManager)
        }
        #endif
    }
}

extension Notification.Name {
    static let newMemberRequested = Notification.Name("newMemberRequested")
    static let newLoanRequested = Notification.Name("newLoanRequested")
    static let newPaymentRequested = Notification.Name("newPaymentRequested")
}
