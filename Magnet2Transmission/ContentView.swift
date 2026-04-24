//
//  ContentView.swift
//  Magnet2Transmission
//
//  Created by Laurent Dubertrand on 24/04/2026.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var appModel: AppModel
    @AppStorage("transmissionHost") private var host = ""
    @AppStorage("transmissionPort") private var port = 9091
    @AppStorage("transmissionUsername") private var username = ""
    @AppStorage("transmissionPassword") private var password = ""
    @State private var draftMagnetLink = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Magnet2Transmission")
                .font(.headline)

            GroupBox("Transmission") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Host or URL", text: $host, prompt: Text("localhost"))
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Port")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("9091", value: $port, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("Optional", text: $username)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        SecureField("Optional", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            GroupBox("Manual Send") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("magnet://… or magnet:?xt=…", text: $draftMagnetLink, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    Button("Send Magnet Link") {
                        submitDraftMagnetLink()
                    }
                    .disabled(draftMagnetLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Magnet Handler") {
                        Text(appModel.currentMagnetHandlerName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(appModel.isDefaultMagnetHandler ? .green : .primary)
                    }

                    LabeledContent("Last Link") {
                        Text(appModel.lastMagnetLink ?? "None")
                            .lineLimit(3)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(appModel.lastMagnetLink == nil ? .secondary : .primary)
                    }

                    LabeledContent("Last Update") {
                        Text(appModel.statusMessage)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(statusColor)
                    }
                }
                .font(.caption)
            }

            Button(appModel.isClaimingMagnetHandler ? "Claiming Magnet Links..." : "Reclaim Magnet Links") {
                Task {
                    await appModel.claimMagnetHandler()
                }
            }
            .disabled(appModel.isClaimingMagnetHandler)

            Divider()

            HStack {
                Button("Open Web UI") {
                    appModel.openTransmissionWebInterface()
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 380)
        .task {
            appModel.refreshMagnetHandlerStatus()
        }
    }

    private var statusColor: Color {
        switch appModel.statusLevel {
        case .idle:
            return .secondary
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    private func submitDraftMagnetLink() {
        let magnetLink = draftMagnetLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !magnetLink.isEmpty else {
            return
        }

        Task {
            await appModel.handleIncomingMagnetLink(magnetLink)
        }
    }
}

#Preview {
    ContentView(appModel: AppModel.shared)
}
