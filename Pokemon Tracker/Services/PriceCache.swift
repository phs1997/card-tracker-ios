// PriceCache.swift
// High performance in-memory price cache layer with automatic expiry.

import Foundation

public actor PriceCache {
    public static let shared = PriceCache()

    private struct CacheEntry {
        let priceData: CardmarketPriceData
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let ttl: TimeInterval = 3600 // 1 hour in-memory cache

    private init() {}

    public func get(cardId: String) -> CardmarketPriceData? {
        guard let entry = cache[cardId] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            cache.removeValue(forKey: cardId)
            return nil
        }
        return entry.priceData
    }

    public func set(cardId: String, priceData: CardmarketPriceData) {
        cache[cardId] = CacheEntry(priceData: priceData, timestamp: Date())
    }

    public func clear() {
        cache.removeAll()
    }
}
