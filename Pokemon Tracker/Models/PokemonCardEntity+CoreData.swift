// PokemonCardEntity+CoreData.swift
// NSManagedObject subclass for the PokemonCardEntity CoreData entity.

import CoreData
import Foundation

@objc(PokemonCardEntity)
public class PokemonCardEntity: NSManagedObject {

    // MARK: - Attributes

    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var number: String?
    @NSManaged public var rarity: String?
    @NSManaged public var imageURLSmall: String?
    @NSManaged public var imageURLLarge: String?
    @NSManaged public var isHolo: Bool
    @NSManaged public var owned: Bool
    @NSManaged public var ownedCount: Int32
    @NSManaged public var addedAt: Date?

    // MARK: - Relationships

    @NSManaged public var set: PokemonSetEntity?
    @NSManaged public var prices: NSSet?

    // MARK: - Convenience computed properties

    public var pricesArray: [PriceEntry] {
        let set = prices as? Set<PriceEntry> ?? []
        return set.sorted { ($0.language ?? "") < ($1.language ?? "") }
    }

    /// Returns the best price for a given language (most recent non-expired entry)
    public func latestPrice(language: String) -> PriceEntry? {
        let cutoff = Date().addingTimeInterval(-86400) // 24 h
        return pricesArray
            .filter { $0.language == language && ($0.fetchedAt ?? .distantPast) > cutoff }
            .max { ($0.fetchedAt ?? .distantPast) < ($1.fetchedAt ?? .distantPast) }
    }

    /// Best available price in EUR according to variant (Holo vs Normal) and metrics (Trend/Average first)
    public var primaryPriceEUR: Double? {
        let entries = prices as? Set<PriceEntry> ?? []
        if entries.isEmpty { return nil }

        let targetPrefix = isHolo ? "holo_" : "normal_"
        let allEntries: [PriceEntry] = Array(entries)
        let variantEntries: [PriceEntry] = allEntries.filter { $0.condition?.hasPrefix(targetPrefix) == true }
        let candidates: [PriceEntry] = variantEntries.isEmpty ? allEntries : variantEntries

        // Priority 1: Trend
        if let trend = candidates.first(where: { $0.condition?.localizedCaseInsensitiveContains("trend") == true }) {
            return trend.priceEUR
        }
        // Priority 2: 7-day or 30-day average
        if let avg7 = candidates.first(where: { $0.condition?.contains("avg7") == true }) {
            return avg7.priceEUR
        }
        if let avg30 = candidates.first(where: { $0.condition?.contains("avg30") == true }) {
            return avg30.priceEUR
        }
        // Priority 3: Low price ("ab")
        if let low = candidates.first(where: { $0.condition?.contains("low") == true || $0.condition?.contains("Niedrig") == true }) {
            return low.priceEUR
        }
        // Priority 4: Any most recent price
        return candidates.max(by: { ($0.fetchedAt ?? .distantPast) < ($1.fetchedAt ?? .distantPast) })?.priceEUR
    }

    public var smallImageURL: URL? {
        guard let str = imageURLSmall, !str.isEmpty else { return nil }
        if !str.hasSuffix(".png") && !str.hasSuffix(".webp") && !str.hasSuffix(".jpg") {
            return URL(string: "\(str)/low.webp") ?? URL(string: "\(str)/low.png") ?? URL(string: str)
        }
        return URL(string: str)
    }

    public var fallbackImageURL: URL? {
        guard let str = imageURLSmall ?? imageURLLarge, !str.isEmpty else { return nil }
        if str.contains("assets.tcgdex.net/de/") {
            let enStr = str.replacingOccurrences(of: "assets.tcgdex.net/de/", with: "assets.tcgdex.net/en/")
            if !enStr.hasSuffix(".png") && !enStr.hasSuffix(".webp") && !enStr.hasSuffix(".jpg") {
                return URL(string: "\(enStr)/low.webp") ?? URL(string: "\(enStr)/low.png") ?? URL(string: enStr)
            }
            return URL(string: enStr)
        }
        return nil
    }

    public var largeImageURL: URL? {
        guard let str = imageURLLarge ?? imageURLSmall, !str.isEmpty else { return nil }
        if !str.hasSuffix(".png") && !str.hasSuffix(".webp") && !str.hasSuffix(".jpg") {
            return URL(string: "\(str)/high.webp") ?? URL(string: "\(str)/high.png") ?? URL(string: str)
        }
        return URL(string: str)
    }

    // MARK: - FetchRequest factories

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PokemonCardEntity> {
        return NSFetchRequest<PokemonCardEntity>(entityName: "PokemonCardEntity")
    }

    @nonobjc public class func requestForSet(_ setId: String) -> NSFetchRequest<PokemonCardEntity> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "set.id == %@", setId)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \PokemonCardEntity.number, ascending: true)
        ]
        return request
    }

    @nonobjc public class func requestOwnedCards() -> NSFetchRequest<PokemonCardEntity> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "owned == YES")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \PokemonCardEntity.addedAt, ascending: false)
        ]
        return request
    }

    @nonobjc public class func requestSearch(
        _ searchText: String,
        setId: String? = nil
    ) -> NSFetchRequest<PokemonCardEntity> {
        let request = fetchRequest()
        var predicates: [NSPredicate] = []

        if !searchText.isEmpty {
            predicates.append(
                NSPredicate(
                    format: "name CONTAINS[cd] %@ OR number CONTAINS[cd] %@",
                    searchText, searchText
                )
            )
        }
        if let setId {
            predicates.append(NSPredicate(format: "set.id == %@", setId))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \PokemonCardEntity.name, ascending: true)
        ]
        return request
    }
}

extension PokemonCardEntity: Identifiable {}
