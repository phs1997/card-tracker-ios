// FeaturePrintIndexService.swift
// Vision-based artwork matching (VNGenerateImageFeaturePrintRequest) + multi-candidate OCR indexing engine.

import Vision
import UIKit
import CoreData
import Combine

public struct CardFeatureEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let number: String
    public let setId: String
    public let setName: String?
    public let featurePrint: VNFeaturePrintObservation?
    public let thumbnailURL: URL?
    public let imageURLSmall: String?
    public let imageURLLarge: String?

    public init(
        id: String,
        name: String,
        number: String,
        setId: String,
        setName: String? = nil,
        featurePrint: VNFeaturePrintObservation? = nil,
        thumbnailURL: URL? = nil,
        imageURLSmall: String? = nil,
        imageURLLarge: String? = nil
    ) {
        self.id = id
        self.name = name
        self.number = number
        self.setId = setId
        self.setName = setName
        self.featurePrint = featurePrint
        self.thumbnailURL = thumbnailURL
        self.imageURLSmall = imageURLSmall
        self.imageURLLarge = imageURLLarge
    }
}

public struct FeatureMatchResult: Identifiable, Sendable {
    public var id: String { "\(card.id)_\(confidence)" }
    public let card: CardFeatureEntry
    public let confidence: Double
    public let method: MatchMethod

    public enum MatchMethod: String, Sendable {
        case visualFeaturePrint = "FeaturePrint"
        case opticalCharacter = "OCR"
        case combined = "Combined"
    }
}

public final class FeaturePrintIndexService: ObservableObject, @unchecked Sendable {

    public static let shared = FeaturePrintIndexService()

    @Published public var indexedSetIds: Set<String> = []
    @Published public var activeSetDownloads: [String: Double] = [:]
    @Published public var isBuildingIndex: Bool = false
    @Published public var indexProgress: Double = 0.0

    private var cardEntries: [CardFeatureEntry] = []
    private let queue = DispatchQueue(label: "com.pokemontracker.featurePrintQueue", qos: .userInitiated)
    private let fileManager = FileManager.default
    private let indexDirectory: URL

    private init() {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        indexDirectory = paths[0].appendingPathComponent("FeaturePrintIndex", isDirectory: true)
        if !fileManager.fileExists(atPath: indexDirectory.path) {
            try? fileManager.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        }
        loadPersistedIndices()
    }

    // MARK: - Persistence of Index Data

    private func loadPersistedIndices() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let files = try? self.fileManager.contentsOfDirectory(at: self.indexDirectory, includingPropertiesForKeys: nil) else { return }

            var loadedSets: Set<String> = []
            var allEntries: [CardFeatureEntry] = []

            for file in files where file.pathExtension == "idx" {
                let setId = file.deletingPathExtension().lastPathComponent
                if let data = try? Data(contentsOf: file),
                   let entries = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, VNFeaturePrintObservation.self, NSURL.self], from: data) as? [[String: Any]] {

                    for dict in entries {
                        if let id = dict["id"] as? String,
                           let name = dict["name"] as? String,
                           let number = dict["number"] as? String,
                           let sId = dict["setId"] as? String {
                            let setName = dict["setName"] as? String
                            let fp = dict["featurePrint"] as? VNFeaturePrintObservation
                            let thumb = dict["thumbnailURL"] as? URL
                            let imgSmall = dict["imageURLSmall"] as? String
                            let imgLarge = dict["imageURLLarge"] as? String

                            let entry = CardFeatureEntry(
                                id: id,
                                name: name,
                                number: number,
                                setId: sId,
                                setName: setName,
                                featurePrint: fp,
                                thumbnailURL: thumb,
                                imageURLSmall: imgSmall,
                                imageURLLarge: imgLarge
                            )
                            allEntries.append(entry)
                        }
                    }
                    loadedSets.insert(setId)
                }
            }

            DispatchQueue.main.async {
                self.cardEntries = allEntries
                self.indexedSetIds = loadedSets
            }
        }
    }

    private func saveIndex(for setId: String, entries: [CardFeatureEntry]) {
        let file = indexDirectory.appendingPathComponent("\(setId).idx")
        var serializable: [[String: Any]] = []

        for e in entries {
            var dict: [String: Any] = [
                "id": e.id,
                "name": e.name,
                "number": e.number,
                "setId": e.setId
            ]
            if let sn = e.setName { dict["setName"] = sn }
            if let fp = e.featurePrint { dict["featurePrint"] = fp }
            if let tu = e.thumbnailURL { dict["thumbnailURL"] = tu }
            if let ism = e.imageURLSmall { dict["imageURLSmall"] = ism }
            if let ilg = e.imageURLLarge { dict["imageURLLarge"] = ilg }
            serializable.append(dict)
        }

        if let data = try? NSKeyedArchiver.archivedData(withRootObject: serializable, requiringSecureCoding: false) {
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: - Set Index Building

    public func buildIndex(for set: PokemonSetEntity, context: NSManagedObjectContext, force: Bool = false) async {
        let setId = set.id
        let setName = set.name

        if !force && indexedSetIds.contains(setId) {
            return
        }

        await MainActor.run {
            activeSetDownloads[setId] = 0.05
        }

        var cards: [PokemonCardEntity] = []
        await context.perform {
            let req = PokemonCardEntity.requestForSet(setId)
            cards = (try? context.fetch(req)) ?? []
        }

        guard !cards.isEmpty else {
            await MainActor.run { activeSetDownloads.removeValue(forKey: setId) }
            return
        }

        var builtEntries: [CardFeatureEntry] = []
        let total = Double(cards.count)

        for (idx, card) in cards.enumerated() {
            var entry = CardFeatureEntry(
                id: card.id,
                name: card.name,
                number: card.number ?? "",
                setId: setId,
                setName: setName,
                featurePrint: nil,
                thumbnailURL: card.smallImageURL,
                imageURLSmall: card.imageURLSmall,
                imageURLLarge: card.imageURLLarge
            )

            // Generate feature print from cached or fetched thumbnail
            if let thumbURL = card.smallImageURL {
                if let fp = await generateFeaturePrint(from: thumbURL) {
                    entry = CardFeatureEntry(
                        id: card.id,
                        name: card.name,
                        number: card.number ?? "",
                        setId: setId,
                        setName: setName,
                        featurePrint: fp,
                        thumbnailURL: thumbURL,
                        imageURLSmall: card.imageURLSmall,
                        imageURLLarge: card.imageURLLarge
                    )
                }
            }

            builtEntries.append(entry)

            let progress = Double(idx + 1) / total
            await MainActor.run {
                self.activeSetDownloads[setId] = progress
            }
        }

        saveIndex(for: setId, entries: builtEntries)

        await MainActor.run {
            self.cardEntries.removeAll { $0.setId == setId }
            self.cardEntries.append(contentsOf: builtEntries)
            self.indexedSetIds.insert(setId)
            self.activeSetDownloads.removeValue(forKey: setId)
        }
    }

    private func generateFeaturePrint(from url: URL) async -> VNFeaturePrintObservation? {
        return await withCheckedContinuation { continuation in
            queue.async {
                autoreleasepool {
                    guard let data = try? Data(contentsOf: url),
                          let image = UIImage(data: data)?.cgImage else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let request = VNGenerateImageFeaturePrintRequest()
                    request.imageCropAndScaleOption = .scaleFit

                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    do {
                        try handler.perform([request])
                        if let observation = request.results?.first as? VNFeaturePrintObservation {
                            continuation.resume(returning: observation)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    } catch {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    public func generateFeaturePrint(from image: UIImage) -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    // MARK: - Matching

    public func matchCard(
        image: UIImage,
        ocrLines: [String] = [],
        topK: Int = 10
    ) -> [FeatureMatchResult] {
        var results: [FeatureMatchResult] = []

        let queryPrint = generateFeaturePrint(from: image)

        // 1. Visual FeaturePrint Distance Matching
        if let queryPrint = queryPrint {
            for entry in cardEntries {
                guard let targetPrint = entry.featurePrint else { continue }
                var distance: Float = 0
                do {
                    try queryPrint.computeDistance(&distance, to: targetPrint)
                    let dist = Double(distance)
                    // Confidence curve: distance 0.0 -> 100%, 0.4 -> 85%, 0.7 -> 60%, >= 1.0 -> <30%
                    let confidence = max(0.0, min(1.0, 1.0 - (dist * 0.75)))
                    if confidence >= 0.35 {
                        results.append(FeatureMatchResult(card: entry, confidence: confidence, method: .visualFeaturePrint))
                    }
                } catch {
                    continue
                }
            }
        }

        // 2. OCR Fallback & Reinforcement
        if !ocrLines.isEmpty {
            let ocrMatched = matchByOCR(lines: ocrLines)
            for match in ocrMatched {
                if let idx = results.firstIndex(where: { $0.card.id == match.card.id }) {
                    // Boost confidence if both visual + OCR match
                    let combinedConfidence = min(0.99, results[idx].confidence * 0.5 + match.confidence * 0.5 + 0.15)
                    results[idx] = FeatureMatchResult(card: results[idx].card, confidence: combinedConfidence, method: .combined)
                } else {
                    results.append(match)
                }
            }
        }

        // Sort descending by confidence score
        results.sort { $0.confidence > $1.confidence }
        return Array(results.prefix(topK))
    }

    private func matchByOCR(lines: [String]) -> [FeatureMatchResult] {
        var results: [FeatureMatchResult] = []
        let fractionPattern = #"\b(\d{1,4})\s*[\/|Il!\]]\s*(\d{1,4})\b"#
        let joined = lines.joined(separator: " ")

        var candidateNumbers: [String] = []
        if let regex = try? NSRegularExpression(pattern: fractionPattern) {
            let range = NSRange(joined.startIndex..., in: joined)
            let matches = regex.matches(in: joined, options: [], range: range)
            for m in matches {
                if let r1 = Range(m.range(at: 1), in: joined) {
                    let num = String(joined[r1])
                    candidateNumbers.append(num)
                    let clean = num.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
                    if clean != num { candidateNumbers.append(clean) }
                }
            }
        }

        for entry in cardEntries {
            var ocrConfidence: Double = 0.0

            // Check number match
            if candidateNumbers.contains(entry.number) {
                ocrConfidence += 0.55
            }

            // Check name substring match
            for line in lines {
                if line.localizedCaseInsensitiveContains(entry.name) && entry.name.count >= 4 {
                    ocrConfidence += 0.40
                    break
                }
            }

            if ocrConfidence >= 0.50 {
                results.append(FeatureMatchResult(card: entry, confidence: min(0.95, ocrConfidence), method: .opticalCharacter))
            }
        }

        return results
    }
}
