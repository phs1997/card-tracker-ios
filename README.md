# Card Tracker – for Pokémon TCG ⚡️

A fast, modern, and privacy-first native iOS application to track your Pokémon Trading Card Game collection, calculate portfolio valuations, and scan cards in real-time.

![Swift](https://img.shields.io/badge/Swift-5.10%20%2F%206.0-orange.svg)
![Platform](https://img.shields.io/badge/Platform-iOS%2017.0%2B-blue.svg)
![Architecture](https://img.shields.io/badge/Architecture-SwiftUI%20%2B%20CoreData%20%2B%20CloudKit-green.svg)
![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)

---

## Features

- 📱 **100% Native & Standalone**: On-device architecture communicating directly with the TCGDex API. No custom backend server required.
- 📷 **Visual FeaturePrint & OCR Scanner**:
  - Real-time camera viewfinder with live text recognition (Vision framework).
  - Multi-photo batch import (up to 100 photos at once).
  - Artwork visual similarity matching via `VNGenerateImageFeaturePrintRequest` + OCR collector number verification.
  - Match confidence percentage scoring with interactive candidate picker.
  - Manual fallback selector with expansion set search.
- 💶 **Cardmarket Pricing**:
  - Live Euro price metrics for Normal and Holo / Reverse Holo variants (Ab, Trend, 30 Tage, 7 Tage, 1 Tag, Ø Gesamt).
  - Automatic 24-hour CoreData caching for instant offline loads.
- ☁️ **Private iCloud Sync**:
  - Seamless multi-device sync across iPhone and iPad using private CloudKit database (`NSPersistentCloudKitContainer`).
- 📦 **Complete Set Catalog**:
  - Chronologically grouped expansion sets across all generations (Scarlet & Violet, Sword & Shield, Sun & Moon, XY, Black & White, Classic, etc.).
  - Set completion progress rings and high-resolution symbol/logo assets with disk caching.
- 💼 **Portfolio Inventory**:
  - Total collection valuation and average card price.
  - Sorting by highest value, lowest value, name, and recently added.
  - One-tap batch price refresh.
- 🌐 **Full Localization**: English and German UI (`de`, `en`).

---

## Project Structure

```text
├── Pokemon Tracker.xcodeproj/     # Xcode 15 / 16 Project
├── Pokemon-Tracker-Info.plist      # Info.plist & background modes
├── Pokemon Tracker/
│   ├── PokemonTrackerApp.swift     # App entrypoint & initial set sync
│   ├── Models/                     # CoreData models & TCGDex Codable types
│   │   ├── PersistenceController.swift
│   │   ├── PokemonCardEntity+CoreData.swift
│   │   ├── PokemonSetEntity+CoreData.swift
│   │   ├── PriceEntry+CoreData.swift
│   │   └── TCGModels.swift
│   ├── Services/                   # Networking, scanner & caching engines
│   │   ├── TCGAPIService.swift
│   │   ├── CardmarketService.swift
│   │   ├── FeaturePrintIndexService.swift
│   │   ├── ScannerService.swift
│   │   ├── LocalThumbnailStore.swift
│   │   └── PriceCache.swift
│   ├── Views/                      # SwiftUI Interface
│   │   ├── SetListView.swift
│   │   ├── CardGridView.swift
│   │   ├── CardDetailView.swift
│   │   ├── InventoryView.swift
│   │   ├── AddCardView.swift
│   │   ├── AdvancedScannerView.swift
│   │   ├── ScannerView.swift
│   │   ├── ManualCardMappingView.swift
│   │   ├── CardThumbnailView.swift
│   │   ├── CameraPhotoCapture.swift
│   │   └── AppInfoView.swift
│   └── Resources/                  # Assets, CoreData Model, Localizations
│       ├── Assets.xcassets
│       ├── PokemonTracker.xcdatamodeld
│       ├── de.lproj/Localizable.strings
│       └── en.lproj/Localizable.strings
├── AppStore_Screenshots/           # Organized App Store preview assets
└── docs/                           # Privacy Policy & Support Webpage
```

---

## Building & Installation

### Requirements
- macOS Sonoma (14.0+) / Sequoia (15.0+)
- Xcode 15.0+ or Xcode 16.0+
- iOS 17.0+ device or simulator

### Build Unsigned IPA for Sideloadly
Run the included build script:
```bash
chmod +x build_ipa.sh
./build_ipa.sh
```
The output `.ipa` file will be generated in `build/IPA/CardTracker.ipa`.

---

## Disclaimer
Pokémon and Pokémon character names are trademarks of Nintendo, Creatures Inc., and GAME FREAK inc. This project is an unofficial fan application and is not affiliated with, endorsed, sponsored, or specifically approved by Nintendo or The Pokémon Company.
