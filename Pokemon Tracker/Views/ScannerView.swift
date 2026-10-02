// ScannerView.swift
// Compact single-card live camera scanner.

import SwiftUI
import CoreData
import AVFoundation

public struct ScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var scanner = ScannerService()
    @State private var matchedCards: [PokemonCardEntity] = []
    @State private var isSearching: Bool = false
    @State private var selectedCard: PokemonCardEntity?
    @State private var addedToastMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                CameraPreviewView(session: scanner.captureSession)
                    .ignoresSafeArea()

                // Framing Box Overlay
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                        .frame(width: 260, height: 360)
                        .overlay(
                            VStack {
                                Spacer()
                                Text("Karte im Rahmen ausrichten")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.black.opacity(0.6), in: Capsule())
                                    .padding(.bottom, 12)
                            }
                        )
                    Spacer()

                    // Match Bottom Card
                    if let topMatch = matchedCards.first {
                        HStack(spacing: 12) {
                            CardThumbnailView(imageURLString: topMatch.imageURLSmall, cardId: topMatch.id)
                                .frame(width: 44, height: 60)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(topMatch.name)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                if let num = topMatch.number {
                                    Text("#\(num) • \(topMatch.set?.name ?? "")")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Button(action: { addCard(topMatch) }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }

                if let toast = addedToastMessage {
                    VStack {
                        Text(toast)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.85), in: Capsule())
                            .padding(.top, 40)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle("Karte scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { scanner.toggleTorch() }) {
                        Image(systemName: scanner.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                }
            }
            .onAppear {
                scanner.checkPermission()
                scanner.startScanning()
            }
            .onDisappear {
                scanner.stopScanning()
            }
            .onChange(of: scanner.recognizedNumber) { _, newNum in
                if let num = newNum {
                    searchByNumber(num)
                }
            }
        }
    }

    private func searchByNumber(_ number: String) {
        guard !isSearching else { return }
        isSearching = true

        let req = PokemonCardEntity.fetchRequest()
        req.predicate = NSPredicate(format: "number == %@", number)
        let localMatches = (try? viewContext.fetch(req)) ?? []

        if !localMatches.isEmpty {
            self.matchedCards = localMatches
            self.isSearching = false
        } else {
            Task {
                if let results = try? await TCGAPIService.shared.searchCards(query: number, language: "de") {
                    await viewContext.perform {
                        for tcg in results {
                            let cardReq = PokemonCardEntity.fetchRequest()
                            cardReq.predicate = NSPredicate(format: "id == %@", tcg.id)
                            let card = (try? viewContext.fetch(cardReq))?.first ?? PokemonCardEntity(context: viewContext)
                            card.id = tcg.id
                            card.name = tcg.name
                            card.number = tcg.number
                            card.imageURLSmall = tcg.images.small
                        }
                        try? viewContext.save()
                    }
                }
                let refetch = (try? viewContext.fetch(req)) ?? []
                await MainActor.run {
                    self.matchedCards = refetch
                    self.isSearching = false
                }
            }
        }
    }

    private func addCard(_ card: PokemonCardEntity) {
        card.owned = true
        card.ownedCount += 1
        card.addedAt = Date()
        try? viewContext.save()

        withAnimation {
            addedToastMessage = "\(card.name) hinzugefügt!"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                addedToastMessage = nil
            }
        }
    }
}

public struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}

    public class CameraPreviewUIView: UIView {
        public override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        public var previewLayer: AVCaptureVideoPreviewLayer {
            guard let layer = layer as? AVCaptureVideoPreviewLayer else {
                fatalError("Expected AVCaptureVideoPreviewLayer")
            }
            return layer
        }
    }
}
