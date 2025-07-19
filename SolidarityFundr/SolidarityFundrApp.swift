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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
