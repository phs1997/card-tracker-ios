// ManualCardMappingView.swift
// Fallback modal to manually select set and card when automated recognition is ambiguous.

import SwiftUI
import CoreData

public struct ManualCardMappingView: View {
    let capturedImage: UIImage?
    let onCardSelected: (PokemonCardEntity) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        entity: PokemonSetEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PokemonSetEntity.releaseDate, ascending: false)]
    )
    private var allSets: FetchedResults<PokemonSetEntity>

    @State private var selectedSet: PokemonSetEntity?
    @State private var setCards: [PokemonCardEntity] = []
    @State private var setCardSearch: String = ""
    @State private var isLoadingCards: Bool = false

    public init(capturedImage: UIImage?, onCardSelected: @escaping (PokemonCardEntity) -> Void) {
        self.capturedImage = capturedImage
        self.onCardSelected = onCardSelected
    }

    private var filteredCards: [PokemonCardEntity] {
        if setCardSearch.isEmpty { return setCards }
        return setCards.filter {
            $0.name.localizedCaseInsensitiveContains(setCardSearch) ||
            ($0.number ?? "").localizedCaseInsensitiveContains(setCardSearch)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack {
                if let selectedSet = selectedSet {
                    // Card Selection inside Set
                    VStack(spacing: 8) {
                        HStack {
                            Button(action: { self.selectedSet = nil }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Sets")
                                }
                            }
                            Spacer()
                            Text(selectedSet.name)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal)

                        if isLoadingCards {
                            ProgressView("Karten werden geladen…")
                                .padding(.top, 40)
                        } else {
                            List(filteredCards) { card in
                                Button(action: {
                                    onCardSelected(card)
                                    dismiss()
                                }) {
                                    HStack(spacing: 12) {
                                        CardThumbnailView(imageURLString: card.imageURLSmall, cardId: card.id)
                                            .frame(width: 40, height: 56)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(card.name)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.primary)
                                            if let num = card.number {
                                                Text("#\(num)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .searchable(text: $setCardSearch, prompt: "Karte im Set suchen…")
                        }
                    }
                } else {
                    // Set Selection List
                    List(allSets) { set in
                        Button(action: {
                            self.selectedSet = set
                            Task { await loadCards(for: set) }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(set.name)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text(set.series)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Set auswählen")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func loadCards(for set: PokemonSetEntity) async {
        isLoadingCards = true
        let existing = set.cardsArray
        if !existing.isEmpty {
            self.setCards = existing
            self.isLoadingCards = false
            return
        }

        if let fetched = try? await TCGAPIService.shared.fetchCards(setId: set.id, language: "de") {
            await viewContext.perform {
                for tcg in fetched {
                    let req = PokemonCardEntity.fetchRequest()
                    req.predicate = NSPredicate(format: "id == %@", tcg.id)
                    let card = (try? viewContext.fetch(req))?.first ?? PokemonCardEntity(context: viewContext)
                    card.id = tcg.id
                    card.name = tcg.name
                    card.number = tcg.number
                    card.imageURLSmall = tcg.images.small
                    card.imageURLLarge = tcg.images.large
                    card.set = set
                }
                try? viewContext.save()
            }
            self.setCards = set.cardsArray
        }
        isLoadingCards = false
    }
}
