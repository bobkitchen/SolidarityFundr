//
//  SolidarityFundrApp.swift
//  SolidarityFundr
//
//  Created by Bob Kitchen on 7/19/25.
//

import SwiftUI
import AppIntents

@main
struct SolidarityFundrApp: App {

    init() {
        // Register App Shortcuts
        SolidarityFundShortcuts.updateAppShortcutParameters()
    }
    let persistenceController = PersistenceController.shared
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
                            
                            // Start statement scheduler if enabled
                            let fundSettings = FundSettings.fetchOrCreate(in: persistenceController.container.viewContext)
                            if fundSettings.smsNotificationsEnabled {
                                StatementScheduler.shared.startScheduler()
                            }
                        }
                        .onDisappear {
                            // Stop the scheduler when app closes
                            StatementScheduler.shared.stopScheduler()
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
        // IMPORTANT: Use .automatic instead of .plain to get traffic lights
        .windowStyle(.automatic)
        // Keep the hidden title bar for integrated look
        .windowStyle(.hiddenTitleBar)
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
