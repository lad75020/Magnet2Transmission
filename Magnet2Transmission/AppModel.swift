//
//  AppModel.swift
//  Magnet2Transmission
//
//  Created by Codex on 24/04/2026.
//

import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var lastMagnetLink: String?
    @Published private(set) var statusMessage = "Waiting for a magnet link."
    @Published private(set) var statusLevel: StatusLevel = .idle

    private let client = TransmissionRPCClient()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func handleIncomingURL(_ url: URL) async {
        guard let scheme = url.scheme?.lowercased(), scheme == "magnet" else {
            statusLevel = .failure
            statusMessage = "Ignored unsupported URL: \(url.absoluteString)"
            return
        }

        await handleIncomingMagnetLink(url.absoluteString)
    }

    func handleIncomingMagnetLink(_ magnetLink: String) async {
        lastMagnetLink = magnetLink
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
            statusLevel = .failure
            statusMessage = error.localizedDescription
        }
    }

    func openTransmissionWebInterface() {
        do {
            let configuration = try TransmissionConfiguration.load(from: defaults)
            NSWorkspace.shared.open(configuration.webURL)
        } catch {
            statusLevel = .failure
            statusMessage = error.localizedDescription
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
        baseURL.appendingPathComponent("transmission").appendingPathComponent("rpc")
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
            normalizedHost = "http://\(trimmedHost)"
        }

        guard var components = URLComponents(string: normalizedHost) else {
            return URL(string: "http://localhost:9091")!
        }

        components.port = port
        components.path = ""

        return components.url ?? URL(string: "http://localhost:9091")!
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

        guard URLComponents(string: host.contains("://") ? host : "http://\(host)") != nil else {
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
