// PokemonSetEntity+CoreData.swift
// NSManagedObject subclass for the PokemonSetEntity CoreData entity.

import CoreData
import Foundation

@objc(PokemonSetEntity)
public class PokemonSetEntity: NSManagedObject {

    // MARK: - Attributes

    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var series: String
    @NSManaged public var releaseDate: Date?
    @NSManaged public var totalCards: Int32
    @NSManaged public var logoURL: String?
    @NSManaged public var symbolURL: String?
    @NSManaged public var lastSyncedAt: Date?

    // MARK: - Relationships

    @NSManaged public var cards: NSSet?

    // MARK: - Convenience

    public var cardsArray: [PokemonCardEntity] {
        let set = cards as? Set<PokemonCardEntity> ?? []
        return set.sorted { ($0.number ?? "") < ($1.number ?? "") }
    }

    public var ownedCount: Int {
        (cards as? Set<PokemonCardEntity>)?.filter { $0.owned }.count ?? 0
    }

    public var completionFraction: Double {
        guard totalCards > 0 else { return 0 }
        return Double(ownedCount) / Double(totalCards)
    }

    public static func seriesPath(for setId: String) -> String {
        let lower = setId.lowercased()
        if lower.hasPrefix("sv") { return "sv" }
        if lower.hasPrefix("swsh") { return "swsh" }
        if lower.hasPrefix("sm") { return "sm" }
        if lower.hasPrefix("xy") { return "xy" }
        if lower.hasPrefix("bw") { return "bw" }
        if lower.hasPrefix("hgss") || lower.hasPrefix("col") { return "hgss" }
        if lower.hasPrefix("dp") { return "dp" }
        if lower.hasPrefix("pl") { return "pl" }
        if lower.hasPrefix("ex") { return "ex" }
        if lower.hasPrefix("ecard") { return "ecard" }
        if lower.hasPrefix("neo") { return "neo" }
        if lower.hasPrefix("base") { return "base" }
        if lower.hasPrefix("gym") { return "gym" }
        return "other"
    }

    public var displaySymbolURL: URL? {
        if let sym = symbolURL, !sym.isEmpty {
            var fixed = sym.replacingOccurrences(of: "assets.tcgdex.net/univ/", with: "assets.tcgdex.net/en/")
            if !fixed.hasSuffix(".png") && !fixed.hasSuffix(".webp") && !fixed.hasSuffix(".jpg") {
                fixed += ".png"
            }
            return URL(string: fixed)
        }
        if let logo = logoURL, !logo.isEmpty {
            var fixed = logo.replacingOccurrences(of: "assets.tcgdex.net/univ/", with: "assets.tcgdex.net/en/")
            if !fixed.hasSuffix(".png") && !fixed.hasSuffix(".webp") && !fixed.hasSuffix(".jpg") {
                fixed += ".png"
            }
            return URL(string: fixed)
        }
        let sPath = Self.seriesPath(for: id)
        return URL(string: "https://assets.tcgdex.net/en/\(sPath)/\(id)/symbol.png")
    }

    public var displayLogoURL: URL? {
        if let logo = logoURL, !logo.isEmpty {
            var fixed = logo.replacingOccurrences(of: "assets.tcgdex.net/univ/", with: "assets.tcgdex.net/en/")
            if !fixed.hasSuffix(".png") && !fixed.hasSuffix(".webp") && !fixed.hasSuffix(".jpg") {
                fixed += ".png"
            }
            return URL(string: fixed)
        }
        if let sym = symbolURL, !sym.isEmpty {
            var fixed = sym.replacingOccurrences(of: "assets.tcgdex.net/univ/", with: "assets.tcgdex.net/en/")
            if !fixed.hasSuffix(".png") && !fixed.hasSuffix(".webp") && !fixed.hasSuffix(".jpg") {
                fixed += ".png"
            }
            return URL(string: fixed)
        }
        let sPath = Self.seriesPath(for: id)
        return URL(string: "https://assets.tcgdex.net/en/\(sPath)/\(id)/logo.png")
    }

    // MARK: - FetchRequest factory

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PokemonSetEntity> {
        return NSFetchRequest<PokemonSetEntity>(entityName: "PokemonSetEntity")
    }

    @nonobjc public class func requestAllSets(
        series: String? = nil,
        search: String? = nil
    ) -> NSFetchRequest<PokemonSetEntity> {
        let request = fetchRequest()
        var predicates: [NSPredicate] = []

        if let series, !series.isEmpty {
            predicates.append(NSPredicate(format: "series == %@", series))
        }
        if let search, !search.isEmpty {
            predicates.append(NSPredicate(format: "name CONTAINS[cd] %@", search))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \PokemonSetEntity.releaseDate, ascending: false),
            NSSortDescriptor(keyPath: \PokemonSetEntity.name, ascending: true)
        ]
        return request
    }
}

extension PokemonSetEntity: Identifiable {}
