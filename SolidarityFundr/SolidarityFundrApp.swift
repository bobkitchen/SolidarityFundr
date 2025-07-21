//
//  SolidarityFundrApp.swift
//  SolidarityFundr
//
//  Created by Bob Kitchen on 7/19/25.
//

import SwiftUI

@main
struct SolidarityFundrApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @NSApplicationDelegateAdaptor(WindowConfigurator.self) var windowConfigurator

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated && !authManager.isLocked {
                    DashboardView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(dataManager)
                        .environmentObject(authManager)
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
        .windowToolbarStyle(.unifiedCompact)
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
    }
}

extension Notification.Name {
    static let newMemberRequested = Notification.Name("newMemberRequested")
    static let newLoanRequested = Notification.Name("newLoanRequested")
    static let newPaymentRequested = Notification.Name("newPaymentRequested")
}