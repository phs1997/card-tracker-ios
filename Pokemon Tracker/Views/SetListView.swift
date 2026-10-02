// SetListView.swift
// Main expansion set catalog grouped by generation era, sorting, search, and visual index downloader.

import SwiftUI
import CoreData

public struct SetListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject private var indexService = FeaturePrintIndexService.shared

    @FetchRequest(
        entity: PokemonSetEntity.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \PokemonSetEntity.releaseDate, ascending: false),
            NSSortDescriptor(keyPath: \PokemonSetEntity.name, ascending: true)
        ]
    )
    private var sets: FetchedResults<PokemonSetEntity>

    @State private var searchText: String = ""
    @State private var selectedSeriesFilter: String = "Alle"
    @State private var selectedSort: SetSortOption = .releaseNewest
    @State private var isLoadingSets: Bool = false
    @State private var showInfoSheet: Bool = false

    public enum SetSortOption: String, CaseIterable, Identifiable {
        case releaseNewest = "Release (Neueste)"
        case releaseOldest = "Release (Älteste)"
        case nameAZ = "Name (A – Z)"
        case nameZA = "Name (Z – A)"

        public var id: String { rawValue }
    }

    public init() {}

    private var availableSeries: [String] {
        let setSeries = Set(sets.compactMap { $0.series.isEmpty ? nil : $0.series })
        return ["Alle"] + setSeries.sorted()
    }

    private var filteredAndSortedSets: [PokemonSetEntity] {
        var result = Array(sets)

        if selectedSeriesFilter != "Alle" {
            result = result.filter { $0.series == selectedSeriesFilter }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText) ||
                $0.series.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch selectedSort {
        case .releaseNewest:
            result.sort { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        case .releaseOldest:
            result.sort { ($0.releaseDate ?? .distantPast) < ($1.releaseDate ?? .distantPast) }
        case .nameAZ:
            result.sort { $0.name < $1.name }
        case .nameZA:
            result.sort { $0.name > $1.name }
        }

        return result
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if isLoadingSets && sets.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Sets werden geladen…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    } else if filteredAndSortedSets.isEmpty {
                        ContentUnavailableView(
                            "Keine Sets gefunden",
                            systemImage: "folder.badge.questionmark",
                            description: Text("Zum Aktualisieren nach unten ziehen oder Internetverbindung prüfen.")
                        )
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredAndSortedSets) { set in
                                NavigationLink(destination: CardGridView(set: set)) {
                                    SetRowView(set: set)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("Pokémon-Sets")
            .searchable(text: $searchText, prompt: "Sets suchen…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showInfoSheet = true }) {
                        Image(systemName: "info.circle")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sortierung", selection: $selectedSort) {
                            ForEach(SetSortOption.allCases) { opt in
                                Text(opt.rawValue).tag(opt)
                            }
                        }

                        Divider()

                        Picker("Serie", selection: $selectedSeriesFilter) {
                            ForEach(availableSeries, id: \.self) { s in
                                Text(s).tag(s)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showInfoSheet) {
                NavigationStack {
                    AppInfoView()
                }
            }
            .refreshable {
                await syncSets(force: true)
            }
        }
    }

    private func syncSets(force: Bool = false) async {
        guard !isLoadingSets else { return }
        isLoadingSets = true

        do {
            let fetched = try await TCGAPIService.shared.fetchSets(language: "de")
            await viewContext.perform {
                for tcg in fetched {
                    let req = PokemonSetEntity.fetchRequest()
                    req.predicate = NSPredicate(format: "id == %@", tcg.id)
                    let entity = (try? viewContext.fetch(req))?.first ?? PokemonSetEntity(context: viewContext)

                    entity.id = tcg.id
                    entity.name = tcg.name
                    entity.series = tcg.series
                    entity.totalCards = Int32(tcg.total)
                    entity.symbolURL = tcg.images.symbol
                    entity.logoURL = tcg.images.logo
                    entity.lastSyncedAt = Date()

                    if let rDate = tcg.releaseDate {
                        let fmt = DateFormatter()
                        fmt.dateFormat = "yyyy-MM-dd"
                        entity.releaseDate = fmt.date(from: rDate)
                    }
                }
                try? viewContext.save()
            }
        } catch {
            print("[SetList] Sync error: \(error)")
        }

        isLoadingSets = false
    }
}

private struct SetRowView: View {
    @ObservedObject var set: PokemonSetEntity
    @ObservedObject private var indexService = FeaturePrintIndexService.shared

    var body: some View {
        HStack(spacing: 14) {
            // Set Symbol / Logo
            AsyncImage(url: set.displaySymbolURL) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFit()
                } else {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(set.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(set.series)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(set.ownedCount)/\(set.totalCards)")
                        .font(.caption.bold())
                        .foregroundColor(set.completionFraction >= 1.0 ? .green : .accentColor)
                }
            }

            Spacer()

            // Completion ring or download ring
            if let downloadProgress = indexService.activeSetDownloads[set.id] {
                ProgressView(value: downloadProgress)
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 3.5)
                        .frame(width: 28, height: 28)

                    Circle()
                        .trim(from: 0, to: set.completionFraction)
                        .stroke(set.completionFraction >= 1.0 ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
