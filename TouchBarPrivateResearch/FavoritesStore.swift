import Foundation

@MainActor
final class FavoritesStore {
    private static let fileURLsKey = "ShelfBar.favorites.fileURLs.v1"
    private let defaults: UserDefaults
    private(set) var fileURLStrings: Set<String>
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fileURLStrings = Set(defaults.stringArray(forKey: Self.fileURLsKey) ?? [])
    }

    func isPinned(fileURL: URL) -> Bool {
        fileURLStrings.contains(fileURL.standardizedFileURL.absoluteString)
    }

    func toggle(fileURL: URL) {
        let key = fileURL.standardizedFileURL.absoluteString
        if fileURLStrings.contains(key) {
            fileURLStrings.remove(key)
        } else {
            fileURLStrings.insert(key)
        }
        commit()
    }

    func remove(fileURL: URL) {
        let key = fileURL.standardizedFileURL.absoluteString
        guard fileURLStrings.remove(key) != nil else { return }
        commit()
    }

    func clear() {
        guard !fileURLStrings.isEmpty else { return }
        fileURLStrings.removeAll()
        commit()
    }

    func pinnedFileItems() -> [FileShelfItem] {
        fileURLStrings
            .compactMap(URL.init(string:))
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map { url in
                let exists = FileManager.default.fileExists(atPath: url.path)
                return FileShelfModel.makeItem(
                    url: url,
                    id: UUID(uuidString: stableUUIDString(for: url.absoluteString)) ?? UUID(),
                    displayName: exists ? url.lastPathComponent : "\(url.lastPathComponent) (Unavailable)",
                    kind: .file,
                    originalSourceDescription: exists ? "Favorite" : "Favorite unavailable",
                    originalFileURL: url,
                    localURL: nil
                )
            }
    }

    private func commit() {
        defaults.set(Array(fileURLStrings).sorted(), forKey: Self.fileURLsKey)
        onChange?()
    }

    private func stableUUIDString(for value: String) -> String {
        let hash = value.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        return String(format: "00000000-0000-4000-8000-%012d", hash % 1_000_000_000_000)
    }
}
