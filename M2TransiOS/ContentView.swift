//
//  ContentView.swift
//  M2TransiOS
//
//  Created by Laurent Dubertrand on 25/04/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var appModel: AppModel
    @AppStorage("transmissionHost") private var host = ""
    @AppStorage("transmissionPort") private var port = 9091
    @AppStorage("transmissionUsername") private var username = ""
    @AppStorage("transmissionPassword") private var password = ""
    @State private var draftMagnetLink = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                Section("Transmission Server") {
                    TextField("Host or URL", text: $host)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("9091", value: $port, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    TextField("Username (optional)", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("Password (optional)", text: $password)
                }

                Section("Manual Send") {
                    TextField("magnet:?xt=...", text: $draftMagnetLink, axis: .vertical)
                        .lineLimit(2...4)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button("Send Magnet Link") {
                        submitDraftMagnetLink()
                    }
                    .disabled(draftMagnetLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Status") {
                    LabeledContent("Last Link") {
                        Text(appModel.lastMagnetLink ?? "None")
                            .foregroundStyle(appModel.lastMagnetLink == nil ? .secondary : .primary)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Last Update") {
                        Text(appModel.statusMessage)
                            .foregroundStyle(statusColor)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Button("Open Transmission Web UI") {
                        openTransmissionWebUI()
                    }
                }
            }
            .navigationTitle("M2TransiOS")
        }
    }

    private var statusColor: Color {
        switch appModel.statusLevel {
        case .idle: return .secondary
        case .success: return .green
        case .failure: return .red
        }
    }

    private func submitDraftMagnetLink() {
        let magnetLink = draftMagnetLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !magnetLink.isEmpty else { return }
        Task {
            await appModel.handleIncomingMagnetLink(magnetLink)
        }
    }

    private func openTransmissionWebUI() {
        do {
            let configuration = try TransmissionConfiguration.load(from: .standard)
            openURL(configuration.webURL)
        } catch {
            appModel.appendTrace("Failed to open web UI: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView(appModel: AppModel.shared)
}
