// PriceEntry+CoreData.swift
// NSManagedObject subclass for the PriceEntry CoreData entity.

import CoreData
import Foundation

@objc(PriceEntry)
public class PriceEntry: NSManagedObject {

    // MARK: - Attributes

    @NSManaged public var cardId: String
    @NSManaged public var language: String?       // "DE" or "EN"
    @NSManaged public var condition: String?      // "Near Mint", "Lightly Played", etc.
    @NSManaged public var priceEUR: Double
    @NSManaged public var fetchedAt: Date?
    @NSManaged public var source: String?         // "cardmarket"

    // MARK: - Relationships

    @NSManaged public var card: PokemonCardEntity?

    // MARK: - Computed

    /// True if price is still within the 24 h cache window
    public var isValid: Bool {
        guard let fetched = fetchedAt else { return false }
        return Date().timeIntervalSince(fetched) < 86400
    }

    public var formattedPrice: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "EUR"
        fmt.locale = Locale(identifier: "de_DE")
        return fmt.string(from: NSNumber(value: priceEUR)) ?? "–"
    }

    // MARK: - FetchRequest factories

    @nonobjc public class func fetchRequest() -> NSFetchRequest<PriceEntry> {
        return NSFetchRequest<PriceEntry>(entityName: "PriceEntry")
    }

    @nonobjc public class func requestForCard(
        _ cardId: String,
        language: String? = nil
    ) -> NSFetchRequest<PriceEntry> {
        let request = fetchRequest()
        var predicates: [NSPredicate] = [
            NSPredicate(format: "cardId == %@", cardId)
        ]
        if let language {
            predicates.append(NSPredicate(format: "language == %@", language))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \PriceEntry.fetchedAt, ascending: false)
        ]
        return request
    }
}

extension PriceEntry: Identifiable {}
