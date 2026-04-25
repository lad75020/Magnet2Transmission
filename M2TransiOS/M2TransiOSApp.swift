//
//  M2TransiOSApp.swift
//  M2TransiOS
//
//  Created by Laurent Dubertrand on 25/04/2026.
//

import SwiftUI

@main
struct M2TransiOSApp: App {
    @StateObject private var appModel = AppModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
                .onOpenURL { url in
                    Task {
                        await appModel.handleIncomingURL(url)
                    }
                }
        }
    }
}
