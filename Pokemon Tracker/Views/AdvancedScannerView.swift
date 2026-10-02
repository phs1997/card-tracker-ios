// AdvancedScannerView.swift
// Advanced multi-photo batch scanner with visual FeaturePrint recognition, OCR, match confidence, and batch addition.

import SwiftUI
import PhotosUI
import Vision
import CoreData
import AVFoundation

public struct ScannedItem: Identifiable {
    public let id = UUID()
    public let originalImage: UIImage
    public var matches: [FeatureMatchResult]
    public var selectedMatchIndex: Int = 0
    public var isProcessed: Bool = false
    public var isSaved: Bool = false

    public var bestMatch: FeatureMatchResult? {
        guard !matches.isEmpty, selectedMatchIndex < matches.count else { return nil }
        return matches[selectedMatchIndex]
    }
}

public struct AdvancedScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var indexService = FeaturePrintIndexService.shared

    @State private var scanner = ScannerService()
    @State private var scannedItems: [ScannedItem] = []
    @State private var selectedItemIndex: Int = 0
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    @State private var isProcessingPhotos: Bool = false
    @State private var processingProgress: Double = 0.0
    @State private var activeFilter: ConfidenceFilter = .all
    @State private var showAllGridSheet: Bool = false
    @State private var showManualMappingSheet: Bool = false
    @State private var showDetailMatchSheet: Bool = false
    @State private var isSavedToast: Bool = false

    public enum ConfidenceFilter: String, CaseIterable, Identifiable {
        case all = "Alle"
        case confident = "Sicher (≥80%)"
        case uncertain = "Unsicher (<80%)"

        public var id: String { rawValue }
    }

    public init() {}

    private var filteredItems: [ScannedItem] {
        switch activeFilter {
        case .all:
            return scannedItems
        case .confident:
            return scannedItems.filter { ($0.bestMatch?.confidence ?? 0) >= 0.80 }
        case .uncertain:
            return scannedItems.filter { ($0.bestMatch?.confidence ?? 0) < 0.80 }
        }
    }

    private var currentItem: ScannedItem? {
        guard !scannedItems.isEmpty, selectedItemIndex < scannedItems.count else { return nil }
        return scannedItems[selectedItemIndex]
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Live Viewfinder if no photos imported, or Photo Preview
                if scannedItems.isEmpty {
                    CameraPreviewView(session: scanner.captureSession)
                        .ignoresSafeArea()

                    // Framing overlay
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.white.opacity(0.85), lineWidth: 2.5)
                            .frame(width: 270, height: 380)
                            .overlay(
                                VStack {
                                    Spacer()
                                    Text("Karte scannen oder Fotos wählen")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(.black.opacity(0.65), in: Capsule())
                                        .padding(.bottom, 12)
                                }
                            )
                        Spacer()
                    }
                } else if let item = currentItem {
                    Image(uiImage: item.originalImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .ignoresSafeArea()
                }

                // Controls & Bottom Strip Overlay
                VStack {
                    // Top Progress Bar if processing
                    if isProcessingPhotos {
                        VStack(spacing: 6) {
                            ProgressView(value: processingProgress)
                                .tint(.accentColor)
                            Text("Analysiere Fotos… (\(Int(processingProgress * 100))%)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                    }

                    Spacer()

                    if !scannedItems.isEmpty {
                        // Filter Chips
                        HStack(spacing: 8) {
                            ForEach(ConfidenceFilter.allCases) { f in
                                Button(action: { activeFilter = f }) {
                                    Text(f.rawValue)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(activeFilter == f ? Color.accentColor : Color.black.opacity(0.6))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            Spacer()

                            Button(action: { showAllGridSheet = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.grid.2x2")
                                    Text("Übersicht (\(scannedItems.count))")
                                }
                                .font(.caption2.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)

                        // Bottom Matched Card Panel
                        if let item = currentItem {
                            VStack(spacing: 10) {
                                if let match = item.bestMatch {
                                    HStack(spacing: 12) {
                                        CardThumbnailView(imageURLString: match.card.imageURLSmall, cardId: match.card.id)
                                            .frame(width: 50, height: 70)
                                            .cornerRadius(6)

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(match.card.name)
                                                    .font(.subheadline.bold())
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)

                                                Spacer()

                                                // Confidence badge
                                                Text("\(Int(match.confidence * 100))%")
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(confidenceColor(match.confidence).opacity(0.2))
                                                    .foregroundColor(confidenceColor(match.confidence))
                                                    .cornerRadius(6)
                                            }

                                            Text("#\(match.card.number) • \(match.card.setName ?? match.card.setId)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)

                                            HStack(spacing: 12) {
                                                Button(action: { showDetailMatchSheet = true }) {
                                                    Text("Treffer ändern (\(item.matches.count))")
                                                        .font(.caption2.bold())
                                                        .foregroundColor(.accentColor)
                                                }

                                                Button(action: { showManualMappingSheet = true }) {
                                                    Text("Manuell zuordnen")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .padding(.top, 2)
                                        }
                                    }
                                } else {
                                    HStack {
                                        Text("Keine automatische Übereinstimmung")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Button("Manuell wählen") {
                                            showManualMappingSheet = true
                                        }
                                        .font(.caption.bold())
                                    }
                                }

                                // Add Button
                                Button(action: addCurrentCardToCollection) {
                                    HStack {
                                        Image(systemName: item.isSaved ? "checkmark" : "plus")
                                        Text(item.isSaved ? "Gespeichert" : "Zur Sammlung hinzufügen")
                                    }
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(item.isSaved ? Color.green : Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            }
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                        }

                        // Horizontal Image Strip
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) {
                                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { idx, it in
                                    let globalIndex = scannedItems.firstIndex(where: { $0.id == it.id }) ?? 0
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: it.originalImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 68)
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(selectedItemIndex == globalIndex ? Color.accentColor : Color.clear, lineWidth: 2)
                                            )

                                        if it.isSaved {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 14, height: 14)
                                                .overlay(Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                                                .padding(2)
                                        }
                                    }
                                    .onTapGesture {
                                        selectedItemIndex = globalIndex
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 74)
                        .padding(.bottom, 12)
                    }
                }
            }
            .navigationTitle("Erweiterter Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 100,
                        matching: .images
                    ) {
                        Image(systemName: "photo.stack")
                    }

                    if scannedItems.isEmpty {
                        Button(action: { scanner.toggleTorch() }) {
                            Image(systemName: scanner.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAllGridSheet) {
                NavigationStack {
                    ScannedGridOverview(items: $scannedItems, onAddAll: addAllScannedCards)
                }
            }
            .sheet(isPresented: $showManualMappingSheet) {
                ManualCardMappingView(capturedImage: currentItem?.originalImage) { card in
                    applyManualCard(card)
                }
            }
            .sheet(isPresented: $showDetailMatchSheet) {
                if let item = currentItem {
                    NavigationStack {
                        MatchCandidatePicker(item: item) { newIdx in
                            if selectedItemIndex < scannedItems.count {
                                scannedItems[selectedItemIndex].selectedMatchIndex = newIdx
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedPhotoItems) { _, newPhotos in
                guard !newPhotos.isEmpty else { return }
                processImportedPhotos(newPhotos)
            }
            .onAppear {
                if scannedItems.isEmpty {
                    scanner.checkPermission()
                    scanner.startScanning()
                }
            }
            .onDisappear {
                scanner.stopScanning()
            }
        }
    }

    private func confidenceColor(_ conf: Double) -> Color {
        if conf >= 0.85 { return .green }
        if conf >= 0.65 { return .orange }
        return .red
    }

    private func processImportedPhotos(_ photos: [PhotosPickerItem]) {
        scanner.stopScanning()
        isProcessingPhotos = true
        processingProgress = 0.0

        Task {
            var loadedItems: [ScannedItem] = []
            let total = Double(photos.count)

            for (idx, pItem) in photos.enumerated() {
                if let data = try? await pItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {

                    // OCR lines recognition
                    let ocrLines = await performOCR(on: image)
                    let matches = indexService.matchCard(image: image, ocrLines: ocrLines, topK: 8)

                    let item = ScannedItem(
                        originalImage: image,
                        matches: matches,
                        selectedMatchIndex: 0,
                        isProcessed: true,
                        isSaved: false
                    )
                    loadedItems.append(item)
                }

                await MainActor.run {
                    processingProgress = Double(idx + 1) / total
                }
            }

            await MainActor.run {
                self.scannedItems = loadedItems
                self.selectedItemIndex = 0
                self.isProcessingPhotos = false
                self.selectedPhotoItems.removeAll()
            }
        }
    }

    private func performOCR(on image: UIImage) async -> [String] {
        guard let cgImg = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                guard err == nil, let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
            try? handler.perform([request])
        }
    }

    private func addCurrentCardToCollection() {
        guard let item = currentItem, let match = item.bestMatch else { return }

        let cardId = match.card.id
        let req = PokemonCardEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", cardId)

        let existing = (try? viewContext.fetch(req))?.first ?? PokemonCardEntity(context: viewContext)
        existing.id = cardId
        existing.name = match.card.name
        existing.number = match.card.number
        existing.imageURLSmall = match.card.imageURLSmall
        existing.imageURLLarge = match.card.imageURLLarge
        existing.owned = true
        existing.ownedCount += 1
        existing.addedAt = Date()

        try? viewContext.save()

        if selectedItemIndex < scannedItems.count {
            scannedItems[selectedItemIndex].isSaved = true
        }
    }

    private func addAllScannedCards() {
        for (idx, item) in scannedItems.enumerated() {
            guard let match = item.bestMatch else { continue }
            let cardId = match.card.id
            let req = PokemonCardEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", cardId)

            let existing = (try? viewContext.fetch(req))?.first ?? PokemonCardEntity(context: viewContext)
            existing.id = cardId
            existing.name = match.card.name
            existing.number = match.card.number
            existing.imageURLSmall = match.card.imageURLSmall
            existing.imageURLLarge = match.card.imageURLLarge
            existing.owned = true
            existing.ownedCount += 1
            existing.addedAt = Date()

            scannedItems[idx].isSaved = true
        }

        try? viewContext.save()
    }

    private func applyManualCard(_ card: PokemonCardEntity) {
        card.owned = true
        card.ownedCount += 1
        card.addedAt = Date()
        try? viewContext.save()

        if selectedItemIndex < scannedItems.count {
            scannedItems[selectedItemIndex].isSaved = true
        }
    }
}

private struct ScannedGridOverview: View {
    @Binding var items: [ScannedItem]
    let onAddAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button(action: {
                    onAddAll()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Alle (\(items.count)) zur Sammlung hinzufügen")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.top, 10)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { it in
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: it.originalImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 125)
                                    .cornerRadius(8)
                                    .clipped()

                                if it.isSaved {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 20, height: 20)
                                        .overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                                        .padding(4)
                                }
                            }

                            Text(it.bestMatch?.card.name ?? "Unbekannt")
                                .font(.caption2.bold())
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle("Erkannte Karten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }
            }
        }
    }
}

private struct MatchCandidatePicker: View {
    let item: ScannedItem
    let onSelectIndex: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(Array(item.matches.enumerated()), id: \.offset) { idx, match in
                Button(action: {
                    onSelectIndex(idx)
                    dismiss()
                }) {
                    HStack(spacing: 12) {
                        CardThumbnailView(imageURLString: match.card.imageURLSmall, cardId: match.card.id)
                            .frame(width: 44, height: 60)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(match.card.name)
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("#\(match.card.number) • \(match.card.setName ?? match.card.setId)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text("\(Int(match.confidence * 100))%")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .navigationTitle("Treffer auswählen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
