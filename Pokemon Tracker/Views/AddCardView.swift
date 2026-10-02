// AddCardView.swift
// Direct card search, quick addition, and instant scanner launch pad.

import SwiftUI
import CoreData

public struct AddCardView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var searchText: String = ""
    @State private var searchResults: [TCGCard] = []
    @State private var isSearching: Bool = false
    @State private var showAdvancedScanner: Bool = false
    @State private var showCompactScanner: Bool = false
    @State private var selectedCardDetail: PokemonCardEntity?
    @State private var searchTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Scanner Launch Banner
                    Button(action: { showAdvancedScanner = true }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "camera.viewfinder")
                                    .font(.title2.bold())
                                    .foregroundColor(.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Erweiterter Scanner")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Visuelle Bilderkennung & Multi-Foto Import")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Results or placeholder
                    if isSearching {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Karten werden gesucht…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    } else if !searchResults.isEmpty {
                        LazyVStack(spacing: 10) {
                            ForEach(searchResults) { card in
                                SearchResultCardRow(tcgCard: card) { entity in
                                    selectedCardDetail = entity
                                }
                            }
                        }
                        .padding(.horizontal)
                    } else if !searchText.isEmpty {
                        ContentUnavailableView(
                            "Keine Treffer",
                            systemImage: "magnifyingglass",
                            description: Text("Keine Karte gefunden für \"\(searchText)\".")
                        )
                        .padding(.top, 40)
                    } else {
                        ContentUnavailableView(
                            "Karte finden",
                            systemImage: "text.magnifyingglass",
                            description: Text("Kartennamen eingeben oder den Scanner starten.")
                        )
                        .padding(.top, 30)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Karte hinzufügen")
            .searchable(text: $searchText, prompt: "Nach Name oder Nummer suchen…")
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    await performSearch(query: newValue)
                }
            }
            .fullScreenCover(isPresented: $showAdvancedScanner) {
                AdvancedScannerView()
            }
            .sheet(item: $selectedCardDetail) { card in
                NavigationStack {
                    CardDetailView(card: card)
                }
            }
        }
    }

    private func performSearch(query: String) async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            await MainActor.run {
                searchResults.removeAll()
                isSearching = false
            }
            return
        }

        await MainActor.run { isSearching = true }

        do {
            let cards = try await TCGAPIService.shared.searchCards(query: clean, language: "de")
            await MainActor.run {
                self.searchResults = cards
                self.isSearching = false
            }
        } catch {
            await MainActor.run {
                self.searchResults = []
                self.isSearching = false
            }
        }
    }
}

private struct SearchResultCardRow: View {
    let tcgCard: TCGCard
    let onInspect: (PokemonCardEntity) -> Void
    @Environment(\.managedObjectContext) private var viewContext

    @State private var isOwned: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            CardThumbnailView(imageURLString: tcgCard.images.small, cardId: tcgCard.id)
                .frame(width: 44, height: 60)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(tcgCard.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text("#\(tcgCard.number)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: toggleSave) {
                Image(systemName: isOwned ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundColor(isOwned ? .green : .accentColor)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .onAppear { checkOwnership() }
        .onTapGesture {
            let entity = getOrCreateEntity()
            onInspect(entity)
        }
    }

    private func checkOwnership() {
        let req = PokemonCardEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@ AND owned == YES", tcgCard.id)
        let count = (try? viewContext.count(for: req)) ?? 0
        isOwned = count > 0
    }

    private func getOrCreateEntity() -> PokemonCardEntity {
        let req = PokemonCardEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", tcgCard.id)
        let entity = (try? viewContext.fetch(req))?.first ?? PokemonCardEntity(context: viewContext)
        entity.id = tcgCard.id
        entity.name = tcgCard.name
        entity.number = tcgCard.number
        entity.imageURLSmall = tcgCard.images.small
        entity.imageURLLarge = tcgCard.images.large
        return entity
    }

    private func toggleSave() {
        let entity = getOrCreateEntity()
        entity.owned.toggle()
        if entity.owned && entity.ownedCount == 0 {
            entity.ownedCount = 1
            entity.addedAt = Date()
        } else if !entity.owned {
            entity.ownedCount = 0
        }
        try? viewContext.save()
        isOwned = entity.owned
    }
}
