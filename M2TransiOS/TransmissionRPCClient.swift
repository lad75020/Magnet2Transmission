//
//  TransmissionRPCClient.swift
//  M2TransiOS
//
//  Created by Laurent Dubertrand on 25/04/2026.
//

import Foundation

@MainActor
final class TransmissionRPCClient {
    private let session: URLSession
    private var sessionID: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func addMagnetLink(_ magnetLink: String, configuration: TransmissionConfiguration) async throws -> TransmissionAddResult {
        let requestBody = TransmissionRPCRequest(
            arguments: .init(filename: magnetLink, metainfo: nil),
            method: "torrent-add",
            tag: Int.random(in: 1...Int.max)
        )

        return try await addTorrent(requestBody, configuration: configuration)
    }

    func addTorrentFile(_ torrentData: Data, configuration: TransmissionConfiguration) async throws -> TransmissionAddResult {
        let requestBody = TransmissionRPCRequest(
            arguments: .init(filename: nil, metainfo: torrentData.base64EncodedString()),
            method: "torrent-add",
            tag: Int.random(in: 1...Int.max)
        )

        return try await addTorrent(requestBody, configuration: configuration)
    }

    private func addTorrent(_ requestBody: TransmissionRPCRequest, configuration: TransmissionConfiguration) async throws -> TransmissionAddResult {
        let response: TransmissionRPCResponse<TransmissionAddPayload> = try await send(requestBody, configuration: configuration)

        if response.result != "success" {
            throw TransmissionRPCError.rpcError(message: response.result)
        }

        guard let payload = response.arguments else {
            throw TransmissionRPCError.invalidResponse(body: nil)
        }

        if let addedTorrent = payload.torrentAdded {
            return .added(addedTorrent.name)
        }

        if let duplicateTorrent = payload.torrentDuplicate {
            return .duplicate(duplicateTorrent.name)
        }

        throw TransmissionRPCError.invalidResponse(body: nil)
    }

    private func send<ResponseBody: Decodable>(
        _ rpcRequest: TransmissionRPCRequest,
        configuration: TransmissionConfiguration
    ) async throws -> TransmissionRPCResponse<ResponseBody> {
        let body = try JSONEncoder().encode(rpcRequest)

        for _ in 0..<2 {
            var request = URLRequest(url: configuration.rpcURL)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if let sessionID {
                request.setValue(sessionID, forHTTPHeaderField: "X-Transmission-Session-Id")
            }

            if !configuration.username.isEmpty || !configuration.password.isEmpty {
                let credentials = "\(configuration.username):\(configuration.password)"
                let encodedCredentials = Data(credentials.utf8).base64EncodedString()
                request.setValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TransmissionRPCError.invalidResponse(body: nil)
            }

            if httpResponse.statusCode == 409 {
                sessionID = httpResponse.value(forHTTPHeaderField: "X-Transmission-Session-Id")
                continue
            }

            if httpResponse.statusCode == 401 {
                throw TransmissionRPCError.authenticationFailed
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw TransmissionRPCError.httpStatus(httpResponse.statusCode)
            }

            do {
                return try JSONDecoder().decode(TransmissionRPCResponse<ResponseBody>.self, from: data)
            } catch {
                let bodySnippet = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(500)

                throw TransmissionRPCError.invalidResponse(body: bodySnippet.map(String.init))
            }
        }

        throw TransmissionRPCError.sessionIDNegotiationFailed
    }
}

enum TransmissionAddResult {
    case added(String)
    case duplicate(String)
}

private struct TransmissionRPCRequest: Encodable {
    let arguments: TransmissionRPCArguments
    let method: String
    let tag: Int
}

private struct TransmissionRPCArguments: Encodable {
    let filename: String?
    let metainfo: String?
}

private struct TransmissionRPCResponse<ResultBody: Decodable>: Decodable {
    let arguments: ResultBody?
    let result: String
    let tag: Int?
}

private struct TransmissionAddPayload: Decodable {
    let torrentAdded: TransmissionTorrent?
    let torrentDuplicate: TransmissionTorrent?

    private enum CodingKeys: String, CodingKey {
        case torrentAdded = "torrent_added"
        case torrentDuplicate = "torrent_duplicate"
    }
}

private struct TransmissionTorrent: Decodable {
    let name: String
}

enum TransmissionRPCError: LocalizedError {
    case authenticationFailed
    case httpStatus(Int)
    case invalidResponse(body: String?)
    case rpcError(message: String)
    case sessionIDNegotiationFailed

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Transmission rejected the supplied username or password."
        case .httpStatus(let statusCode):
            return "Transmission returned HTTP \(statusCode)."
        case .invalidResponse(let body):
            if let body, !body.isEmpty {
                return "Transmission returned an invalid RPC response: \(body)"
            }
            return "Transmission returned an invalid RPC response."
        case .rpcError(let message):
            return "Transmission RPC error: \(message)"
        case .sessionIDNegotiationFailed:
            return "Could not negotiate a Transmission session ID."
        }
    }
}
