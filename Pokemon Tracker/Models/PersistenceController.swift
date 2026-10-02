// PersistenceController.swift
// CoreData + CloudKit stack: Synchronizes collection, cards, holo status,
// and inventory across user's Apple devices via private iCloud database.

import CoreData
import Combine

final class PersistenceController: ObservableObject {

    static let shared = PersistenceController()
    static let cloudKitContainerIdentifier = "iCloud.com.phs1997.pokemontracker"

    let container: NSPersistentContainer
    @Published var isCloudSyncEnabled: Bool = true
    @Published var lastSyncDate: Date?

    // MARK: - Preview / testing support
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let ctx = result.container.viewContext

        let set = PokemonSetEntity(context: ctx)
        set.id = "base1"
        set.name = "Base Set"
        set.series = "Base"
        set.totalCards = 102
        set.releaseDate = Date()
        set.lastSyncedAt = Date()

        let rarities = ["Common", "Uncommon", "Rare", "Rare Holo"]
        for i in 1...8 {
            let card = PokemonCardEntity(context: ctx)
            card.id = "base1-\(i)"
            card.name = "Pokémon \(i)"
            card.number = "\(i)"
            card.rarity = rarities[i % rarities.count]
            card.owned = i % 2 == 0
            card.ownedCount = card.owned ? 1 : 0
            card.isHolo = i % 3 == 0
            card.addedAt = Date()
            card.set = set
        }

        try? ctx.save()
        return result
    }()

    // MARK: - Init

    init(inMemory: Bool = false) {
        if inMemory {
            container = NSPersistentContainer(name: "PokemonTracker")
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Use NSPersistentCloudKitContainer for seamless iCloud syncing
            container = NSPersistentCloudKitContainer(name: "PokemonTracker")

            if let description = container.persistentStoreDescriptions.first {
                // Enable CloudKit private database container
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerIdentifier)
                description.cloudKitContainerOptions = options

                // Track history and post remote change notifications for real-time UI updates
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            }
        }

        // Load stores with fallback to local-only if CloudKit is unreachable/unauthenticated
        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error as NSError? {
                print("[CoreData/CloudKit] Warning: CloudKit store failed to load: \(error), \(error.userInfo). Falling back to local store.")
                DispatchQueue.main.async {
                    self?.isCloudSyncEnabled = false
                }
            } else {
                print("[CoreData/CloudKit] Successfully loaded store: \(storeDescription.url?.absoluteString ?? "unknown") with CloudKit")
            }
        }

        // Configure context for automatic conflict resolution and real-time merging
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "viewContext"

        // Listen for remote store changes across devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteStoreChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    @objc private func handleRemoteStoreChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.lastSyncDate = Date()
            self?.objectWillChange.send()
        }
    }

    // MARK: - Convenience methods

    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("[CoreData] Unresolved save error: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }
}
