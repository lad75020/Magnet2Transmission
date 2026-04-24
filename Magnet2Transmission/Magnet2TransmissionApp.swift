//
//  Magnet2TransmissionApp.swift
//  Magnet2Transmission
//
//  Created by Laurent Dubertrand on 24/04/2026.
//

import AppKit
import CoreServices
import SwiftUI

@main
struct Magnet2TransmissionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel.shared

    var body: some Scene {
        WindowGroup("Receiver", id: "receiver") {
            URLReceiverView(appModel: appModel)
        }
        .defaultLaunchBehavior(.suppressed)
        .handlesExternalEvents(matching: Set([AppModel.magnetScheme]))

        MenuBarExtra("Magnet2Transmission", systemImage: "bolt.horizontal.circle") {
            ContentView(appModel: appModel)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct URLReceiverView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                NSApp.windows
                    .filter { $0.title == "Receiver" }
                    .forEach { $0.orderOut(nil) }
            }
            .onOpenURL { url in
                Task {
                    await appModel.handleIncomingURL(url)
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        Task { @MainActor in
            AppModel.shared.appendTrace("AppDelegate init")
        }
        registerURLHandler()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppModel.shared.appendTrace("applicationWillFinishLaunching")
            AppModel.shared.registerWithLaunchServices()
        }
        registerURLHandler()
        inspectCurrentAppleEvent(context: "applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppModel.shared.appendTrace("applicationDidFinishLaunching args=\(ProcessInfo.processInfo.arguments.joined(separator: " "))")
        }
        registerURLHandler()
        inspectCurrentAppleEvent(context: "applicationDidFinishLaunching")
        handleLaunchArguments()
        NSApp.setActivationPolicy(.accessory)
    }

    private func registerURLHandler() {
        Task { @MainActor in
            AppModel.shared.appendTrace("Registering kAEGetURL handler")
        }
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            AppModel.shared.appendTrace("application(_:open:) count=\(urls.count)")
        }
        for url in urls {
            Task {
                await AppModel.shared.handleIncomingURL(url)
            }
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else {
            Task { @MainActor in
                AppModel.shared.appendTrace("kAEGetURL event without string payload")
            }
            return
        }

        Task {
            AppModel.shared.appendTrace("kAEGetURL payload received")
            await AppModel.shared.handleIncomingURLString(urlString)
        }
    }

    private func handleLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments.dropFirst()
        let magnetArguments = arguments.filter { $0.lowercased().hasPrefix("\(AppModel.magnetScheme):") }

        Task { @MainActor in
            if magnetArguments.isEmpty {
                AppModel.shared.appendTrace("No magnet link found in launch arguments count=\(arguments.count)")
            } else {
                AppModel.shared.appendTrace("Found \(magnetArguments.count) magnet link(s) in launch arguments")
            }
        }

        for argument in magnetArguments {
            Task {
                AppModel.shared.appendTrace("Magnet link found in launch arguments")
                await AppModel.shared.handleIncomingURLString(argument)
            }
        }
    }

    private func inspectCurrentAppleEvent(context: String) {
        let event = NSAppleEventManager.shared().currentAppleEvent

        guard let event else {
            Task { @MainActor in
                AppModel.shared.appendTrace("\(context): no currentAppleEvent")
            }
            return
        }

        let eventClass = event.eventClass
        let eventID = event.eventID
        let payload = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? "<no direct object>"

        Task { @MainActor in
            AppModel.shared.appendTrace("\(context): currentAppleEvent class=\(eventClass) id=\(eventID) payload=\(payload)")
        }

        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue {
            Task {
                AppModel.shared.appendTrace("\(context): handling currentAppleEvent payload")
                await AppModel.shared.handleIncomingURLString(urlString)
            }
        }
    }
}
