//
//  Magnet2TransmissionApp.swift
//  Magnet2Transmission
//
//  Created by Laurent Dubertrand on 24/04/2026.
//

import SwiftUI
import SwiftData

@main
struct Magnet2TransmissionApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
