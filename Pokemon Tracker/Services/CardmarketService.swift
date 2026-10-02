// CardmarketService.swift
// Handles Cardmarket price synchronization and CoreData persistence for Normal and Holo card variants.

import Foundation
import CoreData

public final class CardmarketService: Sendable {

    public static let shared = CardmarketService()

    private init() {}

    public func fetchPrices(
        for card: PokemonCardEntity,
        language: String = "DE",
        forceRefresh: Bool = false,
        context: NSManagedObjectContext
    ) async throws -> CardmarketPriceData {
        if !forceRefresh, let entries = card.prices as? Set<PriceEntry>, !entries.isEmpty {
            let validEntries = entries.filter { $0.isValid && ($0.language == language || $0.language == nil) }
            if !validEntries.isEmpty {
                return buildPriceData(from: Array(validEntries))
            }
        }

        let tcgCard = try await TCGAPIService.shared.fetchCard(id: card.id, language: language.lowercased())
        guard let cm = tcgCard.cardmarket, let p = cm.prices else {
            return CardmarketPriceData()
        }

        let normalPoint = PricePoint(
            low: p.lowPrice,
            trend: p.trendPrice,
            avg30: p.avg30,
            avg7: p.avg7,
            avg1: p.avg1,
            avg: p.averageSellPrice
        )

        let holoPoint = PricePoint(
            low: p.reverseHoloLow,
            trend: p.reverseHoloTrend,
            avg30: p.reverseHoloAvg30,
            avg7: p.reverseHoloAvg7,
            avg1: p.reverseHoloAvg1,
            avg: p.reverseHoloSell
        )

        let priceData = CardmarketPriceData(
            normal: normalPoint,
            holo: holoPoint,
            fetchedAt: Date()
        )

        await context.perform {
            if let oldEntries = card.prices as? Set<PriceEntry> {
                for entry in oldEntries {
                    context.delete(entry)
                }
            }

            func addEntry(condition: String, price: Double?) {
                guard let price, price > 0 else { return }
                let entry = PriceEntry(context: context)
                entry.cardId = card.id
                entry.language = language
                entry.condition = condition
                entry.priceEUR = price
                entry.fetchedAt = Date()
                entry.source = "cardmarket"
                entry.card = card
            }

            addEntry(condition: "normal_low", price: normalPoint.low)
            addEntry(condition: "normal_trend", price: normalPoint.trend)
            addEntry(condition: "normal_avg30", price: normalPoint.avg30)
            addEntry(condition: "normal_avg7", price: normalPoint.avg7)
            addEntry(condition: "normal_avg1", price: normalPoint.avg1)
            addEntry(condition: "normal_avg", price: normalPoint.avg)

            addEntry(condition: "holo_low", price: holoPoint.low)
            addEntry(condition: "holo_trend", price: holoPoint.trend)
            addEntry(condition: "holo_avg30", price: holoPoint.avg30)
            addEntry(condition: "holo_avg7", price: holoPoint.avg7)
            addEntry(condition: "holo_avg1", price: holoPoint.avg1)
            addEntry(condition: "holo_avg", price: holoPoint.avg)

            try? context.save()
        }

        return priceData
    }

    private func buildPriceData(from entries: [PriceEntry]) -> CardmarketPriceData {
        var nLow: Double?, nTrend: Double?, nAvg30: Double?, nAvg7: Double?, nAvg1: Double?, nAvg: Double?
        var hLow: Double?, hTrend: Double?, hAvg30: Double?, hAvg7: Double?, hAvg1: Double?, hAvg: Double?
        var latestDate = Date.distantPast

        for e in entries {
            if let d = e.fetchedAt, d > latestDate { latestDate = d }
            switch e.condition {
            case "normal_low": nLow = e.priceEUR
            case "normal_trend": nTrend = e.priceEUR
            case "normal_avg30": nAvg30 = e.priceEUR
            case "normal_avg7": nAvg7 = e.priceEUR
            case "normal_avg1": nAvg1 = e.priceEUR
            case "normal_avg": nAvg = e.priceEUR
            case "holo_low": hLow = e.priceEUR
            case "holo_trend": hTrend = e.priceEUR
            case "holo_avg30": hAvg30 = e.priceEUR
            case "holo_avg7": hAvg7 = e.priceEUR
            case "holo_avg1": hAvg1 = e.priceEUR
            case "holo_avg": hAvg = e.priceEUR
            default: break
            }
        }

        return CardmarketPriceData(
            normal: PricePoint(low: nLow, trend: nTrend, avg30: nAvg30, avg7: nAvg7, avg1: nAvg1, avg: nAvg),
            holo: PricePoint(low: hLow, trend: hTrend, avg30: hAvg30, avg7: hAvg7, avg1: hAvg1, avg: hAvg),
            fetchedAt: latestDate == .distantPast ? Date() : latestDate
        )
    }
}
