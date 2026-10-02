// CardGridView.swift
// Displays a responsive grid of cards within a set, with ownership status, holo indicators, and filter options.

import SwiftUI
import CoreData

public struct CardGridView: View {
    @ObservedObject var set: PokemonSetEntity
    @Environment(\.managedObjectContext) private var viewContext

    @State private var searchText: String = ""
    @State private var showOwnedOnly: Bool = false
    @State private var selectedCard: PokemonCardEntity?
    @State private var isLoadingCards: Bool = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 105, maximum: 160), spacing: 12)
    ]

    public init(set: PokemonSetEntity) {
        self.set = set
    }

    private var filteredCards: [PokemonCardEntity] {
        let all = set.cardsArray
        return all.filter { card in
            let matchesSearch = searchText.isEmpty ||
                card.name.localizedCaseInsensitiveContains(searchText) ||
                (card.number ?? "").localizedCaseInsensitiveContains(searchText)
            let matchesOwned = !showOwnedOnly || card.owned
            return matchesSearch && matchesOwned
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Stats Bar
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(set.ownedCount) / \(set.totalCards) gesammelt")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)

                        ProgressView(value: set.completionFraction)
                            .tint(.accentColor)
                    }

                    Spacer()

                    Toggle(isOn: $showOwnedOnly) {
                        Image(systemName: showOwnedOnly ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(.accentColor)
                    }
                    .toggleStyle(.button)
                    .clipShape(Circle())
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if isLoadingCards {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Karten werden geladen…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                } else if filteredCards.isEmpty {
                    ContentUnavailableView(
                        "Keine Karten gefunden",
                        systemImage: "rectangle.portrait.on.rectangle.portrait.slash",
                        description: Text(searchText.isEmpty ? "Karten für dieses Set wurden noch nicht heruntergeladen." : "Keine Karten stimmen mit der Suche überein.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredCards) { card in
                            CardCell(card: card)
                                .onTapGesture {
                                    selectedCard = card
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Karten suchen…")
        .sheet(item: $selectedCard) { card in
            NavigationStack {
                CardDetailView(card: card)
            }
        }
        .task {
            if set.cardsArray.isEmpty {
                await loadCardsForSet()
            }
        }
        .refreshable {
            await loadCardsForSet(force: true)
        }
    }

    private func loadCardsForSet(force: Bool = false) async {
        guard !isLoadingCards else { return }
        isLoadingCards = true
        errorMessage = nil

        do {
            let tcgCards = try await TCGAPIService.shared.fetchCards(setId: set.id, language: "de")
            await viewContext.perform {
                for tcg in tcgCards {
                    let req = PokemonCardEntity.fetchRequest()
                    req.predicate = NSPredicate(format: "id == %@", tcg.id)
                    let existing = (try? viewContext.fetch(req))?.first ?? PokemonCardEntity(context: viewContext)

                    existing.id = tcg.id
                    existing.name = tcg.name
                    existing.number = tcg.number
                    existing.imageURLSmall = tcg.images.small
                    existing.imageURLLarge = tcg.images.large
                    existing.set = set
                }
                try? viewContext.save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingCards = false
    }
}

private struct CardCell: View {
    @ObservedObject var card: PokemonCardEntity

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                CardThumbnailView(imageURLString: card.imageURLSmall, cardId: card.id)
                    .opacity(card.owned ? 1.0 : 0.45)
                    .grayscale(card.owned ? 0.0 : 0.85)

                if card.owned {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(6)
                }

                if card.isHolo {
                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundColor(card.owned ? .primary : .secondary)

                HStack {
                    if let num = card.number {
                        Text("#\(num)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let price = card.primaryPriceEUR {
                        Text(String(format: "%.2f €", price))
                            .font(.caption2.bold())
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
    }
}
