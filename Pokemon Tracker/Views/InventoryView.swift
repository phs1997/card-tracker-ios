// InventoryView.swift
// Overview of all collected cards, total portfolio valuation, filtering, and batch price refreshes.

import SwiftUI
import CoreData

public struct InventoryView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        entity: PokemonCardEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PokemonCardEntity.addedAt, ascending: false)],
        predicate: NSPredicate(format: "owned == YES")
    )
    private var ownedCards: FetchedResults<PokemonCardEntity>

    @State private var searchText: String = ""
    @State private var selectedSort: InventorySortOption = .valueDescending
    @State private var selectedSetId: String? = nil
    @State private var isUpdatingPrices: Bool = false
    @State private var updateProgress: Double = 0.0
    @State private var selectedCard: PokemonCardEntity?

    public enum InventorySortOption: String, CaseIterable, Identifiable {
        case valueDescending = "Höchster Wert"
        case valueAscending = "Niedrigster Wert"
        case name = "Name"
        case recent = "Zuletzt hinzugefügt"

        public var id: String { rawValue }
    }

    public init() {}

    private var totalPortfolioValue: Double {
        ownedCards.reduce(0.0) { sum, card in
            let price = card.primaryPriceEUR ?? 0.0
            let count = max(1, Double(card.ownedCount))
            return sum + (price * count)
        }
    }

    private var averageCardValue: Double {
        guard !ownedCards.isEmpty else { return 0 }
        return totalPortfolioValue / Double(ownedCards.count)
    }

    private var filteredAndSortedCards: [PokemonCardEntity] {
        var list = Array(ownedCards)

        if !searchText.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.number ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.set?.name ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        if let selectedSetId {
            list = list.filter { $0.set?.id == selectedSetId }
        }

        switch selectedSort {
        case .valueDescending:
            list.sort { ($0.primaryPriceEUR ?? 0) > ($1.primaryPriceEUR ?? 0) }
        case .valueAscending:
            list.sort { ($0.primaryPriceEUR ?? 0) < ($1.primaryPriceEUR ?? 0) }
        case .name:
            list.sort { $0.name < $1.name }
        case .recent:
            list.sort { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        }

        return list
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Portfolio Stats Dashboard
                    HStack(spacing: 12) {
                        StatBox(
                            title: "Gesamtwert",
                            value: String(format: "%.2f €", totalPortfolioValue),
                            icon: "chart.line.uptrend.xyaxis",
                            color: .accentColor
                        )

                        StatBox(
                            title: "Karten",
                            value: "\(ownedCards.count)",
                            icon: "rectangle.stack.fill",
                            color: .purple
                        )

                        StatBox(
                            title: "Ø Wert",
                            value: String(format: "%.2f €", averageCardValue),
                            icon: "gauge.medium",
                            color: .cyan
                        )
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Batch Update Bar if running
                    if isUpdatingPrices {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Preise werden aktualisiert…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(updateProgress * 100))%")
                                    .font(.caption.bold())
                            }
                            ProgressView(value: updateProgress)
                                .tint(.accentColor)
                        }
                        .padding(.horizontal)
                    }

                    // Sort & Filter Bar
                    HStack {
                        Menu {
                            Picker("Sortierung", selection: $selectedSort) {
                                ForEach(InventorySortOption.allCases) { opt in
                                    Text(opt.rawValue).tag(opt)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(selectedSort.rawValue)
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }

                        Spacer()

                        Button(action: refreshAllPrices) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)

                    // Cards Grid / List
                    if filteredAndSortedCards.isEmpty {
                        ContentUnavailableView(
                            "Keine Karten in der Sammlung",
                            systemImage: "tray",
                            description: Text("Füge Karten über die Sets oder den Scanner hinzu.")
                        )
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredAndSortedCards) { card in
                                InventoryCardRow(card: card)
                                    .onTapGesture {
                                        selectedCard = card
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Inventar")
            .searchable(text: $searchText, prompt: "Sammlung durchsuchen…")
            .sheet(item: $selectedCard) { card in
                NavigationStack {
                    CardDetailView(card: card)
                }
            }
        }
    }

    private func refreshAllPrices() {
        guard !isUpdatingPrices else { return }
        isUpdatingPrices = true
        updateProgress = 0.0

        let cardsToUpdate = Array(ownedCards)
        let total = Double(cardsToUpdate.count)

        Task {
            for (idx, card) in cardsToUpdate.enumerated() {
                _ = try? await CardmarketService.shared.fetchPrices(for: card, forceRefresh: true, context: viewContext)
                await MainActor.run {
                    updateProgress = Double(idx + 1) / max(1, total)
                }
            }
            await MainActor.run {
                isUpdatingPrices = false
            }
        }
    }
}

private struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Spacer()
            }

            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

private struct InventoryCardRow: View {
    @ObservedObject var card: PokemonCardEntity

    var body: some View {
        HStack(spacing: 12) {
            CardThumbnailView(imageURLString: card.imageURLSmall, cardId: card.id, aspectRatio: 0.7)
                .frame(width: 48, height: 68)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let sName = card.set?.name {
                        Text(sName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let num = card.number {
                        Text("#\(num)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if card.isHolo {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                            .foregroundColor(.purple)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let price = card.primaryPriceEUR {
                    Text(String(format: "%.2f €", price * max(1, Double(card.ownedCount))))
                        .font(.subheadline.bold())
                        .foregroundColor(.accentColor)
                } else {
                    Text("–")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if card.ownedCount > 1 {
                    Text("\(card.ownedCount)x")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}
