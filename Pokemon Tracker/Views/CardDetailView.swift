// CardDetailView.swift
// Detailed card inspection sheet with artwork zoom, Holo variant toggling, and Cardmarket price metrics.

import SwiftUI
import CoreData

public struct CardDetailView: View {
    @ObservedObject var card: PokemonCardEntity
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var priceData: CardmarketPriceData = CardmarketPriceData()
    @State private var isLoadingPrices: Bool = false
    @State private var isZoomingArtwork: Bool = false
    @State private var errorMessage: String?

    public init(card: PokemonCardEntity) {
        self.card = card
    }

    private var activePricePoint: PricePoint {
        card.isHolo ? priceData.holo : priceData.normal
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Card Artwork Presentation
                ZStack {
                    CardThumbnailView(imageURLString: card.imageURLLarge ?? card.imageURLSmall, cardId: card.id, aspectRatio: 0.72)
                        .frame(maxHeight: 380)
                        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
                        .onTapGesture {
                            isZoomingArtwork = true
                        }

                    if card.isHolo {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.pink.opacity(0.6), .purple.opacity(0.6), .cyan.opacity(0.6), .yellow.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .allowsHitTesting(false)
                    }
                }
                .padding(.top, 10)

                // Owned Status & Quantity Bar
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        Button(action: toggleOwned) {
                            HStack {
                                Image(systemName: card.owned ? "checkmark.circle.fill" : "circle")
                                Text(card.owned ? "In Sammlung" : "Als vorhanden markieren")
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(card.owned ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundColor(card.owned ? .white : .primary)
                            .cornerRadius(10)
                        }

                        if card.owned {
                            HStack(spacing: 12) {
                                Button(action: decrementCount) {
                                    Image(systemName: "minus")
                                        .frame(width: 36, height: 36)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(Circle())
                                }

                                Text("\(card.ownedCount)")
                                    .font(.title3.bold())
                                    .frame(minWidth: 24)

                                Button(action: incrementCount) {
                                    Image(systemName: "plus")
                                        .frame(width: 36, height: 36)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(Circle())
                                }
                            }
                        }
                    }

                    // Holo / Reverse Holo Toggle
                    Toggle(isOn: Binding(
                        get: { card.isHolo },
                        set: { val in
                            card.isHolo = val
                            try? viewContext.save()
                        }
                    )) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text("Holografisch / Reverse Holo")
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal)

                // Card Metadata Info Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        InfoRow(title: "Set", value: card.set?.name ?? "–")
                        InfoRow(title: "Nummer", value: card.number ?? "–")
                        InfoRow(title: "Serie", value: card.set?.series ?? "–")
                        InfoRow(title: "Seltenheit", value: card.rarity ?? "–")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Cardmarket Price Breakdown Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Cardmarket Preise")
                            .font(.headline)

                        Spacer()

                        if isLoadingPrices {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Button(action: {
                                Task { await loadPrices(force: true) }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.subheadline)
                            }
                        }
                    }

                    if activePricePoint.hasData {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            PriceTile(label: "ab", value: PricePoint.formatted(activePricePoint.low))
                            PriceTile(label: "Trend", value: PricePoint.formatted(activePricePoint.trend), isHighlighted: true)
                            PriceTile(label: "30 Tage", value: PricePoint.formatted(activePricePoint.avg30))
                            PriceTile(label: "7 Tage", value: PricePoint.formatted(activePricePoint.avg7))
                            PriceTile(label: "1 Tag", value: PricePoint.formatted(activePricePoint.avg1))
                            PriceTile(label: "Ø Gesamt", value: PricePoint.formatted(activePricePoint.avg))
                        }
                    } else {
                        Text("Keine aktuellen Preise verfügbar.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    // Cardmarket external link
                    if let url = cardmarketWebURL {
                        Link(destination: url) {
                            HStack {
                                Text("Auf Cardmarket öffnen")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.bottom, 30)
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
        .task {
            await loadPrices()
        }
    }

    private var cardmarketWebURL: URL? {
        let nameEncoded = card.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.cardmarket.com/de/Pokemon/Products/Search?searchString=\(nameEncoded)")
    }

    private func toggleOwned() {
        card.owned.toggle()
        if card.owned && card.ownedCount == 0 {
            card.ownedCount = 1
            card.addedAt = Date()
        } else if !card.owned {
            card.ownedCount = 0
        }
        try? viewContext.save()
    }

    private func incrementCount() {
        card.ownedCount += 1
        card.owned = true
        try? viewContext.save()
    }

    private func decrementCount() {
        if card.ownedCount > 1 {
            card.ownedCount -= 1
        } else {
            card.ownedCount = 0
            card.owned = false
        }
        try? viewContext.save()
    }

    private func loadPrices(force: Bool = false) async {
        guard !isLoadingPrices else { return }
        isLoadingPrices = true

        do {
            let data = try await CardmarketService.shared.fetchPrices(for: card, forceRefresh: force, context: viewContext)
            self.priceData = data
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingPrices = false
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
    }
}

private struct PriceTile: View {
    let label: String
    let value: String
    var isHighlighted: Bool = false

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(isHighlighted ? .accentColor : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}
