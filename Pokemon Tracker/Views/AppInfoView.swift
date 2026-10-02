// AppInfoView.swift
// App version, iCloud CloudKit sync status, cache management, and legal disclaimers.

import SwiftUI

public struct AppInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var persistence = PersistenceController.shared

    @State private var cacheSizeFormatted: String = "–"
    @State private var showCacheClearedAlert: Bool = false

    public init() {}

    public var body: some View {
        List {
            Section("Status") {
                HStack {
                    Label("iCloud Sync", systemImage: "icloud.fill")
                        .foregroundColor(persistence.isCloudSyncEnabled ? .blue : .secondary)
                    Spacer()
                    Text(persistence.isCloudSyncEnabled ? "Aktiv" : "Lokal")
                        .foregroundColor(.secondary)
                }

                if let lastSync = persistence.lastSyncDate {
                    HStack {
                        Label("Letzter Sync", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text(lastSync, style: .time)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Speicher & Cache") {
                HStack {
                    Label("Bild-Cache", systemImage: "internaldrive")
                    Spacer()
                    Text(cacheSizeFormatted)
                        .foregroundColor(.secondary)
                }

                Button(role: .destructive, action: clearCache) {
                    Label("Cache leeren", systemImage: "trash")
                }
            }

            Section("Über") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0 (1)")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Preise")
                    Spacer()
                    Text("Cardmarket via TCGDex API")
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Text("Pokémon und Pokémon-Charakternamen sind Marken von Nintendo, Creatures und Game Freak. Diese App ist ein inoffizielles Fan-Projekt und steht in keiner Verbindung zu Nintendo oder The Pokémon Company.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Info & Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .onAppear {
            updateCacheSize()
        }
        .alert("Cache geleert", isPresented: $showCacheClearedAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func updateCacheSize() {
        let bytes = LocalThumbnailStore.shared.cacheSizeBytes
        let mb = Double(bytes) / (1024 * 1024)
        cacheSizeFormatted = String(format: "%.1f MB", mb)
    }

    private func clearCache() {
        LocalThumbnailStore.shared.clearAll()
        updateCacheSize()
        showCacheClearedAlert = true
    }
}
