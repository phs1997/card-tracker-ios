// LocalThumbnailStore.swift
// Two-tier cache (NSCache memory + on-device Disk cache) for card thumbnails and set symbols.

import UIKit
import CoreData

public final class LocalThumbnailStore: @unchecked Sendable {
    public static let shared = LocalThumbnailStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDir: URL

    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDir = paths[0].appendingPathComponent("LocalCardThumbnails", isDirectory: true)

        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        }

        memoryCache.countLimit = 400
        memoryCache.totalCostLimit = 60 * 1024 * 1024 // 60 MB memory cache
    }

    private func safeFilename(for id: String) -> String {
        return id.replacingOccurrences(of: "/", with: "_")
                 .replacingOccurrences(of: ":", with: "_")
                 .replacingOccurrences(of: "?", with: "_") + ".webp"
    }

    public func thumbnail(for id: String) -> UIImage? {
        if let memImg = memoryCache.object(forKey: id as NSString) {
            return memImg
        }

        let fileURL = cacheDir.appendingPathComponent(safeFilename(for: id))
        if let data = try? Data(contentsOf: fileURL), let diskImg = UIImage(data: data) {
            memoryCache.setObject(diskImg, forKey: id as NSString, cost: data.count)
            return diskImg
        }

        return nil
    }

    public func saveThumbnail(_ image: UIImage, for id: String) {
        memoryCache.setObject(image, forKey: id as NSString)
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            let fileURL = self.cacheDir.appendingPathComponent(self.safeFilename(for: id))
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    public func hasThumbnail(id: String) -> Bool {
        if memoryCache.object(forKey: id as NSString) != nil { return true }
        let fileURL = cacheDir.appendingPathComponent(safeFilename(for: id))
        return fileManager.fileExists(atPath: fileURL.path)
    }

    public func prefetchSetSymbols(sets: [PokemonSetEntity]) {
        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            for set in sets {
                if let sURL = set.symbolURL, !self.hasThumbnail(id: "symbol_\(set.id)") {
                    if let url = URL(string: sURL), let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        self.saveThumbnail(img, for: "symbol_\(set.id)")
                    }
                }
                if let lURL = set.logoURL, !self.hasThumbnail(id: "logo_\(set.id)") {
                    if let url = URL(string: lURL), let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        self.saveThumbnail(img, for: "logo_\(set.id)")
                    }
                }
            }
        }
    }

    public func clearAll() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
    }

    public var cacheSizeBytes: Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for file in files {
            if let res = try? file.resourceValues(forKeys: [.fileSizeKey]), let sz = res.fileSize {
                total += Int64(sz)
            }
        }
        return total
    }
}
