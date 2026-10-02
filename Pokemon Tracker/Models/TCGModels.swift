// TCGModels.swift
// Decodable and domain value types for Pokémon TCG data.

import Foundation

// MARK: - Sets

struct TCGSetResponse: Decodable, Sendable {
    let data: [TCGSet]
    let page: Int?
    let pageSize: Int?
    let count: Int?
    let totalCount: Int?
}

struct TCGSet: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let series: String
    let printedTotal: Int
    let total: Int
    let releaseDate: String?
    let updatedAt: String?
    let images: TCGSetImages
    let legalities: TCGLegalities?

    init(
        id: String,
        name: String,
        series: String,
        printedTotal: Int,
        total: Int,
        releaseDate: String? = nil,
        updatedAt: String? = nil,
        images: TCGSetImages = TCGSetImages(symbol: nil, logo: nil),
        legalities: TCGLegalities? = nil
    ) {
        self.id = id
        self.name = name
        self.series = series
        self.printedTotal = printedTotal
        self.total = total
        self.releaseDate = releaseDate
        self.updatedAt = updatedAt
        self.images = images
        self.legalities = legalities
    }
}

struct TCGSetImages: Decodable, Sendable {
    let symbol: String?
    let logo: String?

    init(symbol: String? = nil, logo: String? = nil) {
        self.symbol = symbol
        self.logo = logo
    }
}

struct TCGLegalities: Decodable, Sendable {
    let standard: String?
    let expanded: String?
    let unlimited: String?
}

// MARK: - Cards

struct TCGCardResponse: Decodable, Sendable {
    let data: [TCGCard]
    let page: Int?
    let pageSize: Int?
    let count: Int?
    let totalCount: Int?
}

struct TCGCard: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let number: String
    let rarity: String?
    let artist: String?
    let hp: String?
    let types: [String]?
    let images: TCGCardImages
    let set: TCGCardSetRef?
    let tcgplayer: TCGPlayerPrices?
    let cardmarket: TCGCardmarketPrices?

    var localId: String { number }
    var imageURLSmall: String? { images.small }
    var imageURLLarge: String? { images.large }

    init(
        id: String,
        name: String,
        number: String,
        rarity: String? = nil,
        artist: String? = nil,
        hp: String? = nil,
        types: [String]? = nil,
        images: TCGCardImages = TCGCardImages(small: nil, large: nil),
        set: TCGCardSetRef? = nil,
        tcgplayer: TCGPlayerPrices? = nil,
        cardmarket: TCGCardmarketPrices? = nil
    ) {
        self.id = id
        self.name = name
        self.number = number
        self.rarity = rarity
        self.artist = artist
        self.hp = hp
        self.types = types
        self.images = images
        self.set = set
        self.tcgplayer = tcgplayer
        self.cardmarket = cardmarket
    }
}

struct TCGCardImages: Decodable, Sendable {
    let small: String?
    let large: String?

    init(small: String? = nil, large: String? = nil) {
        self.small = small
        self.large = large
    }
}

struct TCGCardSetRef: Decodable, Sendable {
    let id: String
    let name: String
}

// MARK: - Pricing Types

struct TCGPlayerPrices: Decodable, Sendable {
    let url: String?
    let updatedAt: String?
    let prices: [String: TCGPricePoint]?
}

struct TCGPricePoint: Decodable, Sendable {
    let low: Double?
    let mid: Double?
    let high: Double?
    let market: Double?
    let directLow: Double?
}

struct TCGCardmarketPrices: Decodable, Sendable {
    let url: String?
    let updatedAt: String?
    let prices: TCGCardmarketPriceMetrics?
}

struct TCGCardmarketPriceMetrics: Decodable, Sendable {
    let averageSellPrice: Double?
    let lowPrice: Double?
    let trendPrice: Double?
    let germanProLow: Double?
    let suggestedPrice: Double?
    let reverseHoloSell: Double?
    let reverseHoloLow: Double?
    let reverseHoloTrend: Double?
    let lowPriceExPlus: Double?
    let avg1: Double?
    let avg7: Double?
    let avg30: Double?
    let reverseHoloAvg1: Double?
    let reverseHoloAvg7: Double?
    let reverseHoloAvg30: Double?
}

// MARK: - Domain / UI Price Structures

public struct PricePoint: Sendable {
    public let low: Double?
    public let trend: Double?
    public let avg30: Double?
    public let avg7: Double?
    public let avg1: Double?
    public let avg: Double?

    public init(
        low: Double? = nil,
        trend: Double? = nil,
        avg30: Double? = nil,
        avg7: Double? = nil,
        avg1: Double? = nil,
        avg: Double? = nil
    ) {
        self.low = low
        self.trend = trend
        self.avg30 = avg30
        self.avg7 = avg7
        self.avg1 = avg1
        self.avg = avg
    }

    public var hasData: Bool {
        low != nil || trend != nil || avg30 != nil || avg7 != nil || avg1 != nil || avg != nil
    }

    public static func formatted(_ val: Double?) -> String {
        guard let val, val > 0 else { return "–" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "EUR"
        fmt.locale = Locale(identifier: "de_DE")
        return fmt.string(from: NSNumber(value: val)) ?? String(format: "%.2f €", val)
    }
}

public struct CardmarketPriceData: Sendable {
    public let normal: PricePoint
    public let holo: PricePoint
    public let fetchedAt: Date

    public init(
        normal: PricePoint = PricePoint(),
        holo: PricePoint = PricePoint(),
        fetchedAt: Date = Date()
    ) {
        self.normal = normal
        self.holo = holo
        self.fetchedAt = fetchedAt
    }

    public var primaryTrendPrice: Double? {
        normal.trend ?? holo.trend ?? normal.avg ?? holo.avg
    }
}
