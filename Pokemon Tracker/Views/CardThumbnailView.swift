// CardThumbnailView.swift
// Robust card image thumbnail with disk/memory caching and multi-tier CDN fallbacks.

import SwiftUI

public struct CardThumbnailView: View {
    let imageURLString: String?
    let cardId: String?
    var aspectRatio: CGFloat = 0.7

    @State private var loadedImage: UIImage?
    @State private var isLoading: Bool = false
    @State private var currentCandidateIndex: Int = 0
    @State private var candidateURLs: [URL] = []

    public init(imageURLString: String?, cardId: String? = nil, aspectRatio: CGFloat = 0.7) {
        self.imageURLString = imageURLString
        self.cardId = cardId
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))

            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .onAppear {
            setupCandidateURLs()
            loadNextCandidate()
        }
    }

    private func setupCandidateURLs() {
        candidateURLs.removeAll()

        if let cardId = cardId, let cached = LocalThumbnailStore.shared.thumbnail(for: cardId) {
            self.loadedImage = cached
            return
        }

        guard let raw = imageURLString, !raw.isEmpty else { return }

        // Primary URL candidate
        var primary = raw
        if !primary.hasSuffix(".png") && !primary.hasSuffix(".webp") && !primary.hasSuffix(".jpg") {
            primary += "/low.webp"
        }
        if let u = URL(string: primary) { candidateURLs.append(u) }

        // Fallback 1: PNG version
        let pngVer = primary.replacingOccurrences(of: "/low.webp", with: "/low.png")
        if let u = URL(string: pngVer), !candidateURLs.contains(u) { candidateURLs.append(u) }

        // Fallback 2: English CDN mirror if German failed
        if primary.contains("assets.tcgdex.net/de/") {
            let en = primary.replacingOccurrences(of: "assets.tcgdex.net/de/", with: "assets.tcgdex.net/en/")
            if let u = URL(string: en), !candidateURLs.contains(u) { candidateURLs.append(u) }
        }
    }

    private func loadNextCandidate() {
        guard loadedImage == nil, currentCandidateIndex < candidateURLs.count else {
            isLoading = false
            return
        }

        let url = candidateURLs[currentCandidateIndex]
        isLoading = true

        URLSession.shared.dataTask(with: url) { data, resp, err in
            if let data = data, let img = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.loadedImage = img
                    self.isLoading = false
                    if let cid = self.cardId {
                        LocalThumbnailStore.shared.saveThumbnail(img, for: cid)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.currentCandidateIndex += 1
                    self.loadNextCandidate()
                }
            }
        }.resume()
    }
}
