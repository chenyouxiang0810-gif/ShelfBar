import Foundation

enum RecentShelfItemType: String, Codable {
    case file
    case clipboard
}

struct RecentShelfItem: Codable, Equatable {
    let id: UUID
    var type: RecentShelfItemType
    var title: String
    var key: String
    var urlString: String?
    var touchedAt: Date
}

@MainActor
final class RecentItemsStore {
    private static let storageKey = "ShelfBar.recent.items.v1"
    private let defaults: UserDefaults
    private let settings: AppSettingsStore
    private(set) var items: [RecentShelfItem]
    var onChange: (([RecentShelfItem]) -> Void)?

    init(settings: AppSettingsStore, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([RecentShelfItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
        enforceLimit()
    }

    func record(fileURL: URL, title: String? = nil) {
        guard settings.isFeatureEnabled(.recentFiles) else { return }
        upsert(
            RecentShelfItem(
                id: UUID(),
                type: .file,
                title: title ?? fileURL.lastPathComponent,
                key: fileURL.standardizedFileURL.absoluteString,
                urlString: fileURL.absoluteString,
                touchedAt: Date()
            )
        )
    }

    func record(clipboard item: ClipboardShelfItem) {
        guard settings.isFeatureEnabled(.recentFiles) else { return }
        upsert(
            RecentShelfItem(
                id: UUID(),
                type: .clipboard,
                title: item.title,
                key: "clipboard:\(item.stableKey)",
                urlString: item.urlString ?? item.fileURLString,
                touchedAt: Date()
            )
        )
    }

    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        commit()
    }

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        commit()
    }

    func settingsDidChange(_ change: AppSettingsStore.Change) {
        if case let .general(key) = change, key == ShelfBarSettingsKey.recentFilesLimit {
            enforceLimit()
            commit()
        }
    }

    private func upsert(_ item: RecentShelfItem) {
        if let index = items.firstIndex(where: { $0.key == item.key }) {
            items.remove(at: index)
        }
        items.insert(item, at: 0)
        enforceLimit()
        commit()
    }

    private func enforceLimit() {
        items.sort { $0.touchedAt > $1.touchedAt }
        if items.count > settings.recentFilesLimit {
            items = Array(items.prefix(settings.recentFilesLimit))
        }
    }

    private func commit() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.storageKey)
        }
        onChange?(items)
    }
}
