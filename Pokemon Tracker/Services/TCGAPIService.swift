// TCGAPIService.swift
// Handles Pokémon TCG data fetching via TCGDex multi-language REST API.

import Foundation

public final class TCGAPIService: Sendable {

    public static let shared = TCGAPIService()
    private let baseURL = "https://api.tcgdex.net/v2"

    private let urlSession: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024
        )
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Sets

    public func fetchSets(language: String = "de") async throws -> [TCGSet] {
        let lang = language.lowercased() == "de" ? "de" : "en"
        let endpoint = "\(baseURL)/\(lang)/sets"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct TCGDexRawSet: Decodable {
            let id: String
            let name: String
            let logo: String?
            let symbol: String?
            let cardCount: TCGDexSetCardCount?
            let releaseDate: String?

            struct TCGDexSetCardCount: Decodable {
                let total: Int?
                let official: Int?
            }
        }

        let rawSets = try JSONDecoder().decode([TCGDexRawSet].self, from: data)

        func inferSeries(from setId: String, name: String) -> String {
            let id = setId.lowercased()
            if id.hasPrefix("sv") || id.contains("scarlet") || id.contains("karmesin") { return "Scarlet & Violet" }
            if id.hasPrefix("swsh") || id.contains("sword") || id.contains("schwert") { return "Sword & Shield" }
            if id.hasPrefix("sm") || id.contains("sun") || id.contains("sonne") { return "Sun & Moon" }
            if id.hasPrefix("xy") { return "XY" }
            if id.hasPrefix("bw") || id.contains("black") || id.contains("schwarz") { return "Black & White" }
            if id.hasPrefix("hgss") || id.hasPrefix("col") || id.contains("heartgold") { return "HeartGold & SoulSilver" }
            if id.hasPrefix("dp") || id.hasPrefix("pl") || id.contains("diamond") || id.contains("diamant") { return "Diamond & Pearl" }
            if id.hasPrefix("ex") { return "EX Series" }
            if id.hasPrefix("ecard") || id.hasPrefix("e-") { return "E-Card" }
            if id.hasPrefix("neo") { return "Neo" }
            if id.hasPrefix("base") || id.hasPrefix("bs") || id.hasPrefix("gym") { return "Classic" }
            if id.hasPrefix("pop") || id.hasPrefix("mcd") { return "Promos" }
            return "Other"
        }

        return rawSets.map { raw in
            let seriesName = inferSeries(from: raw.id, name: raw.name)
            let total = raw.cardCount?.total ?? raw.cardCount?.official ?? 0
            let printed = raw.cardCount?.official ?? total

            let symUrl: String? = {
                guard let sym = raw.symbol, !sym.isEmpty else { return nil }
                var s = sym
                if !s.hasSuffix(".png") && !s.hasSuffix(".webp") && !s.hasSuffix(".jpg") {
                    s += ".png"
                }
                return s
            }()

            let logoUrl: String? = {
                guard let logo = raw.logo, !logo.isEmpty else { return nil }
                var l = logo
                if !l.hasSuffix(".png") && !l.hasSuffix(".webp") && !l.hasSuffix(".jpg") {
                    l += ".png"
                }
                return l
            }()

            return TCGSet(
                id: raw.id,
                name: raw.name,
                series: seriesName,
                printedTotal: printed,
                total: total,
                releaseDate: raw.releaseDate,
                updatedAt: nil,
                images: TCGSetImages(symbol: symUrl, logo: logoUrl),
                legalities: nil
            )
        }
    }

    // MARK: - Cards for Set

    public func fetchCards(setId: String, language: String = "de") async throws -> [TCGCard] {
        let lang = language.lowercased() == "de" ? "de" : "en"
        let endpoint = "\(baseURL)/\(lang)/sets/\(setId)"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct TCGDexSetDetail: Decodable {
            let id: String
            let name: String
            let cards: [TCGDexCardBrief]?

            struct TCGDexCardBrief: Decodable {
                let id: String
                let localId: String
                let name: String
                let image: String?
            }
        }

        let detail = try JSONDecoder().decode(TCGDexSetDetail.self, from: data)
        guard let briefs = detail.cards else { return [] }

        return briefs.map { brief in
            let imgSmall: String? = {
                guard let img = brief.image, !img.isEmpty else { return nil }
                if !img.hasSuffix(".png") && !img.hasSuffix(".webp") && !img.hasSuffix(".jpg") {
                    return "\(img)/low.webp"
                }
                return img
            }()

            let imgLarge: String? = {
                guard let img = brief.image, !img.isEmpty else { return nil }
                if !img.hasSuffix(".png") && !img.hasSuffix(".webp") && !img.hasSuffix(".jpg") {
                    return "\(img)/high.webp"
                }
                return img
            }()

            return TCGCard(
                id: brief.id,
                name: brief.name,
                number: brief.localId,
                rarity: nil,
                artist: nil,
                hp: nil,
                types: nil,
                images: TCGCardImages(small: imgSmall, large: imgLarge),
                set: TCGCardSetRef(id: detail.id, name: detail.name),
                tcgplayer: nil,
                cardmarket: nil
            )
        }
    }

    // MARK: - Single Card Detail

    public func fetchCard(id: String, language: String = "de") async throws -> TCGCard {
        let lang = language.lowercased() == "de" ? "de" : "en"
        let endpoint = "\(baseURL)/\(lang)/cards/\(id)"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct TCGDexFullCard: Decodable {
            let id: String
            let localId: String
            let name: String
            let image: String?
            let rarity: String?
            let category: String?
            let illustrator: String?
            let hp: Int?
            let types: [String]?
            let set: TCGDexCardSetRef?
            let cardmarket: TCGDexCardmarket?

            struct TCGDexCardSetRef: Decodable {
                let id: String?
                let name: String?
            }

            struct TCGDexCardmarket: Decodable {
                let url: String?
                let updatedAt: String?
                let prices: TCGDexPrices?

                struct TCGDexPrices: Decodable {
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
            }
        }

        let resp = try JSONDecoder().decode(TCGDexFullCard.self, from: data)

        let imgSmall: String? = {
            guard let img = resp.image, !img.isEmpty else { return nil }
            if !img.hasSuffix(".png") && !img.hasSuffix(".webp") && !img.hasSuffix(".jpg") {
                return "\(img)/low.webp"
            }
            return img
        }()

        let imgLarge: String? = {
            guard let img = resp.image, !img.isEmpty else { return nil }
            if !img.hasSuffix(".png") && !img.hasSuffix(".webp") && !img.hasSuffix(".jpg") {
                return "\(img)/high.webp"
            }
            return img
        }()

        var cmPrices: TCGCardmarketPrices? = nil
        if let cm = resp.cardmarket {
            let p = cm.prices
            let metrics = TCGCardmarketPriceMetrics(
                averageSellPrice: p?.averageSellPrice,
                lowPrice: p?.lowPrice,
                trendPrice: p?.trendPrice,
                germanProLow: p?.germanProLow,
                suggestedPrice: p?.suggestedPrice,
                reverseHoloSell: p?.reverseHoloSell,
                reverseHoloLow: p?.reverseHoloLow,
                reverseHoloTrend: p?.reverseHoloTrend,
                lowPriceExPlus: p?.lowPriceExPlus,
                avg1: p?.avg1,
                avg7: p?.avg7,
                avg30: p?.avg30,
                reverseHoloAvg1: p?.reverseHoloAvg1,
                reverseHoloAvg7: p?.reverseHoloAvg7,
                reverseHoloAvg30: p?.reverseHoloAvg30
            )
            cmPrices = TCGCardmarketPrices(
                url: cm.url,
                updatedAt: cm.updatedAt,
                prices: metrics
            )
        }

        let setRef: TCGCardSetRef? = {
            guard let set = resp.set, let sId = set.id, !sId.isEmpty else { return nil }
            return TCGCardSetRef(id: sId, name: set.name ?? "")
        }()

        return TCGCard(
            id: resp.id,
            name: resp.name,
            number: resp.localId,
            rarity: resp.rarity,
            artist: resp.illustrator,
            hp: resp.hp != nil ? "\(resp.hp!)" : nil,
            types: resp.types,
            images: TCGCardImages(small: imgSmall, large: imgLarge),
            set: setRef,
            tcgplayer: nil,
            cardmarket: cmPrices
        )
    }

    // MARK: - Search

    public func searchCards(query: String, language: String = "de") async throws -> [TCGCard] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        let lang = language.lowercased() == "de" ? "de" : "en"
        let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clean
        let endpoint = "\(baseURL)/\(lang)/cards?name=\(encoded)"

        guard let url = URL(string: endpoint) else { throw URLError(.badURL) }
        let (data, response) = try await urlSession.data(from: url)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        struct BriefCard: Decodable {
            let id: String
            let localId: String
            let name: String
            let image: String?
        }

        let briefs = try JSONDecoder().decode([BriefCard].self, from: data)
        return briefs.prefix(30).map { b in
            let imgSmall: String? = {
                guard let img = b.image, !img.isEmpty else { return nil }
                if !img.hasSuffix(".png") && !img.hasSuffix(".webp") && !img.hasSuffix(".jpg") {
                    return "\(img)/low.webp"
                }
                return img
            }()
            return TCGCard(
                id: b.id,
                name: b.name,
                number: b.localId,
                rarity: nil,
                artist: nil,
                hp: nil,
                types: nil,
                images: TCGCardImages(small: imgSmall, large: nil),
                set: nil,
                tcgplayer: nil,
                cardmarket: nil
            )
        }
    }

    // MARK: - OCR Smart Matching

    public func searchCardsByOCR(
        lines: [String],
        language: String = "de"
    ) async throws -> [TCGCard] {
        var queryTerms: [String] = []
        var numberCandidates: [String] = []

        let lineCount = lines.count
        let topLines = lines.prefix(max(2, lineCount / 3))
        let bottomLines = lines.suffix(max(2, lineCount / 3))

        let ocrReplacements: [(String, String)] = [
            ("©", ""), ("®", ""), ("™", ""),
            ("—", "-"), ("–", "-"),
            ("O", "0"), ("o", "0"),
            ("I", "1"), ("l", "1"), ("|", "1"),
            ("S", "5"), ("s", "5"),
            ("B", "8")
        ]

        func sanitizeOCRNumber(_ text: String) -> String {
            var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for (from, to) in ocrReplacements {
                result = result.replacingOccurrences(of: from, with: to)
            }
            return result
        }

        for line in topLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 3 && !queryTerms.contains(trimmed) {
                queryTerms.append(trimmed)
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 3 && !queryTerms.contains(trimmed) {
                queryTerms.append(trimmed)
            }
        }

        let codeSetMap: [String: [String]] = [
            "SVI": ["sv01"], "PAL": ["sv02"], "OBF": ["sv03"], "MEW": ["sv03.5"],
            "PAR": ["sv04"], "PAF": ["sv04.5"], "TEF": ["sv05"], "TWM": ["sv06"],
            "SFA": ["sv06.5"], "SCR": ["sv07"], "SSP": ["sv08"], "PRE": ["sv08.5"],
            "SVP": ["svp"], "SSH": ["swsh1"], "RCL": ["swsh2"], "DAA": ["swsh3"],
            "CPA": ["swsh3.5"], "VIV": ["swsh4"], "SHF": ["swsh4.5"], "BST": ["swsh5"],
            "CRE": ["swsh6"], "EVS": ["swsh7"], "CEL": ["swsh7.5"], "FST": ["swsh8"],
            "BRS": ["swsh9"], "ASR": ["swsh10"], "PGO": ["swsh10.5"], "LOR": ["swsh11"],
            "SIT": ["swsh12"], "CRZ": ["swsh12.5"], "SWSHP": ["swshp"], "SUM": ["sm1"],
            "GRI": ["sm2"], "BUS": ["sm3"], "SLG": ["sm3.5"], "CIN": ["sm4"],
            "UPR": ["sm5"], "FLI": ["sm6"], "CES": ["sm7"], "DRM": ["sm7.5"],
            "LOT": ["sm8"], "TEU": ["sm9"], "UNB": ["sm10"], "UNM": ["sm11"],
            "HIF": ["sm11.5"], "CEC": ["sm12"], "SMP": ["smp"]
        ]

        var detectedSetIds: [String] = []
        let searchInBottom = bottomLines.joined(separator: " ")

        if let r1 = searchInBottom.range(of: #"[A-Z]{3,4}"#, options: .regularExpression) {
            let candidateCode = String(searchInBottom[r1]).uppercased()
            if let matchedSets = codeSetMap[candidateCode] {
                detectedSetIds.append(contentsOf: matchedSets)
            }
        }

        if let r2 = searchInBottom.range(of: #"[A-Za-z0-9]{2,5}\s*\/[A-Za-z0-9]{2,5}"#, options: .regularExpression) {
            let fracStr = String(searchInBottom[r2])
            let parts = fracStr.components(separatedBy: "/")
            if let first = parts.first?.trimmingCharacters(in: .whitespaces) {
                let clean = sanitizeOCRNumber(first)
                if !numberCandidates.contains(clean) {
                    numberCandidates.append(clean)
                }
            }
        }

        var candidateIds: [String] = []
        for setId in detectedSetIds {
            for num in numberCandidates {
                let cleanNoZero = num.replacingOccurrences(of: "^0+", with: "", options: .regularExpression)
                let padded3 = String(format: "%03d", Int(cleanNoZero) ?? 0)
                let id1 = "\(setId)-\(padded3)"
                let id2 = "\(setId)-\(cleanNoZero)"
                if !candidateIds.contains(id1) { candidateIds.append(id1) }
                if !candidateIds.contains(id2) { candidateIds.append(id2) }
            }
        }

        var candidates: [TCGCard] = []

        for cid in candidateIds.prefix(6) {
            if let card = try? await fetchCard(id: cid, language: language) {
                if !candidates.contains(where: { $0.id == card.id }) {
                    candidates.append(card)
                }
            }
        }

        if candidates.isEmpty {
            for term in queryTerms.prefix(3) {
                if let results = try? await searchCards(query: term, language: language) {
                    for card in results where !candidates.contains(where: { $0.id == card.id }) {
                        candidates.append(card)
                    }
                }
                if candidates.count >= 8 { break }
            }
        }

        return Array(candidates.prefix(15))
    }
}
