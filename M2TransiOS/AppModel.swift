//
//  AppModel.swift
//  M2TransiOS
//
//  Created by Laurent Dubertrand on 25/04/2026.
//

import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let magnetScheme = "magnet"
    private static let lastMagnetLinkDefaultsKey = "lastMagnetLink"
    private static let recentTraceDefaultsKey = "recentTrace"
    private static let traceFileName = "trace.log"

    @Published private(set) var lastMagnetLink: String?
    @Published private(set) var recentTrace: [String]
    @Published private(set) var statusMessage = "Waiting for a magnet link."
    @Published private(set) var statusLevel: StatusLevel = .idle

    private let client = TransmissionRPCClient()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.lastMagnetLink = defaults.string(forKey: Self.lastMagnetLinkDefaultsKey)
        self.recentTrace = defaults.stringArray(forKey: Self.recentTraceDefaultsKey) ?? []
        appendTrace("AppModel initialized")
    }

    func handleIncomingURLString(_ urlString: String) async {
        let trimmedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        appendTrace("Received raw URL string: \(trimmedURLString)")
        guard trimmedURLString.lowercased().hasPrefix("\(Self.magnetScheme):") else {
            statusLevel = .failure
            statusMessage = "Ignored unsupported URL: \(trimmedURLString)"
            return
        }
        await handleIncomingMagnetLink(trimmedURLString)
    }

    func handleIncomingURL(_ url: URL) async {
        appendTrace("Received URL object: \(url.absoluteString)")
        if url.isFileURL {
            await handleIncomingFileURL(url)
            return
        }
        await handleIncomingURLString(url.absoluteString)
    }

    func handleIncomingMagnetLink(_ magnetLink: String) async {
        lastMagnetLink = magnetLink
        defaults.set(magnetLink, forKey: Self.lastMagnetLinkDefaultsKey)
        appendTrace("Handling magnet link")
        statusLevel = .idle
        statusMessage = "Sending torrent to Transmission..."

        do {
            let configuration = try TransmissionConfiguration.load(from: defaults)
            let result = try await client.addMagnetLink(magnetLink, configuration: configuration)
            statusLevel = .success
            switch result {
            case .added(let name):
                statusMessage = "Added \(name)"
            case .duplicate(let name):
                statusMessage = "Already present: \(name)"
            }
        } catch {
            appendTrace("Transmission request failed: \(error.localizedDescription)")
            statusLevel = .failure
            statusMessage = error.localizedDescription
        }
    }

    func handleIncomingFileURL(_ fileURL: URL) async {
        let isTorrentFile = fileURL.pathExtension.caseInsensitiveCompare("torrent") == .orderedSame

        guard isTorrentFile else {
            statusLevel = .failure
            statusMessage = "Ignored unsupported file: \(fileURL.lastPathComponent)"
            return
        }

        lastMagnetLink = fileURL.lastPathComponent
        defaults.set(fileURL.lastPathComponent, forKey: Self.lastMagnetLinkDefaultsKey)
        appendTrace("Handling torrent file: \(fileURL.path)")
        statusLevel = .idle
        statusMessage = "Uploading torrent file to Transmission..."

        let didAccessSecurityScopedResource = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let torrentData = try Data(contentsOf: fileURL)
            let configuration = try TransmissionConfiguration.load(from: defaults)
            let result = try await client.addTorrentFile(torrentData, configuration: configuration)
            statusLevel = .success
            switch result {
            case .added(let name):
                statusMessage = "Added \(name)"
            case .duplicate(let name):
                statusMessage = "Already present: \(name)"
            }
        } catch {
            appendTrace("Transmission file upload failed: \(error.localizedDescription)")
            statusLevel = .failure
            statusMessage = error.localizedDescription
        }
    }

    func appendTrace(_ message: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        let entry = "\(timestamp) \(message)"
        recentTrace = Array((recentTrace + [entry]).suffix(8))
        defaults.set(recentTrace, forKey: Self.recentTraceDefaultsKey)
        writeTraceToDisk(entry)
    }

    var traceLogURL: URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupportURL
            .appendingPathComponent(Bundle.main.displayName, isDirectory: true)
            .appendingPathComponent(Self.traceFileName)
    }

    private func writeTraceToDisk(_ entry: String) {
        guard let traceLogURL else { return }
        let fileManager = FileManager.default
        let directoryURL = traceLogURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let line = "\(entry)\n"
            if fileManager.fileExists(atPath: traceLogURL.path) {
                let handle = try FileHandle(forWritingTo: traceLogURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try Data(line.utf8).write(to: traceLogURL, options: .atomic)
            }
        } catch {
            // Avoid recursive trace logging if writing the trace file itself fails.
        }
    }
}

extension AppModel {
    enum StatusLevel {
        case idle
        case success
        case failure
    }
}

struct TransmissionConfiguration {
    let host: String
    let port: Int
    let username: String
    let password: String

    var rpcURL: URL {
        baseURL.appendingPathComponent("rpc")
    }

    var webURL: URL {
        baseURL
    }

    private var baseURL: URL {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost: String

        if trimmedHost.contains("://") {
            normalizedHost = trimmedHost
        } else {
            normalizedHost = "https://\(trimmedHost)"
        }

        guard var components = URLComponents(string: normalizedHost) else {
            return URL(string: "https://localhost:9091")!
        }

        components.port = port
        components.path = ""

        return components.url ?? URL(string: "https://localhost:9091")!
    }

    static func load(from defaults: UserDefaults) throws -> TransmissionConfiguration {
        let host = defaults.string(forKey: "transmissionHost")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let username = defaults.string(forKey: "transmissionUsername") ?? ""
        let password = defaults.string(forKey: "transmissionPassword") ?? ""
        let configuredPort = defaults.object(forKey: "transmissionPort") as? Int ?? 9091

        guard !host.isEmpty else {
            throw TransmissionConfigurationError.missingHost
        }

        guard (1...65535).contains(configuredPort) else {
            throw TransmissionConfigurationError.invalidPort
        }

        guard URLComponents(string: host.contains("://") ? host : "https://\(host)") != nil else {
            throw TransmissionConfigurationError.invalidHost
        }

        return TransmissionConfiguration(
            host: host,
            port: configuredPort,
            username: username,
            password: password
        )
    }
}

private extension Bundle {
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundleIdentifier
            ?? "This app"
    }
}

enum TransmissionConfigurationError: LocalizedError {
    case missingHost
    case invalidHost
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .missingHost:
            return "Enter a Transmission host before sending a magnet link."
        case .invalidHost:
            return "The Transmission host is invalid."
        case .invalidPort:
            return "The Transmission port must be between 1 and 65535."
        }
    }
}
