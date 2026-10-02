// PokemonTrackerApp.swift
// Main SwiftUI App Entrypoint for Card Tracker – for Pokémon TCG.

import SwiftUI
import CoreData

@main
struct PokemonTrackerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .task {
                    await initialDataSync()
                }
        }
    }

    private func initialDataSync() async {
        let context = persistenceController.container.viewContext
        let req = PokemonSetEntity.fetchRequest()
        let count = (try? context.count(for: req)) ?? 0

        // Fetch all expansion sets if database is empty or stale
        if count == 0 {
            if let sets = try? await TCGAPIService.shared.fetchSets(language: "de") {
                await context.perform {
                    for tcg in sets {
                        let entityReq = PokemonSetEntity.fetchRequest()
                        entityReq.predicate = NSPredicate(format: "id == %@", tcg.id)
                        let entity = (try? context.fetch(entityReq))?.first ?? PokemonSetEntity(context: context)

                        entity.id = tcg.id
                        entity.name = tcg.name
                        entity.series = tcg.series
                        entity.totalCards = Int32(tcg.total)
                        entity.symbolURL = tcg.images.symbol
                        entity.logoURL = tcg.images.logo
                        entity.lastSyncedAt = Date()

                        if let rDate = tcg.releaseDate {
                            let fmt = DateFormatter()
                            fmt.dateFormat = "yyyy-MM-dd"
                            entity.releaseDate = fmt.date(from: rDate)
                        }
                    }
                    try? context.save()
                }
            }
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: TabItem = .sets

    enum TabItem: Hashable {
        case sets
        case inventory
        case addCard
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SetListView()
                .tabItem {
                    Label("Sets", systemImage: "square.stack.3d.up.fill")
                }
                .tag(TabItem.sets)

            InventoryView()
                .tabItem {
                    Label("Inventar", systemImage: "tray.full.fill")
                }
                .tag(TabItem.inventory)

            AddCardView()
                .tabItem {
                    Label("Hinzufügen", systemImage: "plus.circle.fill")
                }
                .tag(TabItem.addCard)
        }
        .tint(.accentColor)
    }
}
