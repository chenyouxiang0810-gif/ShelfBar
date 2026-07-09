import Foundation

struct ShelfStackEntry: Codable, Equatable {
    let id: UUID
    let urlString: String
    let bookmarkBase64: String?
    let displayName: String?
    let kind: ShelfItemKind?
    let originalSourceDescription: String?
    let originalFileURLString: String?
    let localURLString: String?

    @MainActor init(id: UUID = UUID(), url: URL) {
        let item = FileShelfModel.makeItem(url: url, id: id)
        self.init(item: item)
    }

    init(item: FileShelfItem) {
        id = item.id
        urlString = item.url.absoluteString
        displayName = item.filename
        kind = item.kind
        originalSourceDescription = item.originalSourceDescription
        originalFileURLString = item.originalFileURL?.absoluteString
        localURLString = item.localURL?.absoluteString
        bookmarkBase64 = try? item.url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ).base64EncodedString()
    }

    var url: URL? {
        var bookmarkIsStale = false
        if let bookmarkBase64,
           let data = Data(base64Encoded: bookmarkBase64),
           let resolved = try? URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkIsStale
           ),
           resolved.isFileURL {
            return resolved
        }
        return URL(string: urlString).flatMap { $0.isFileURL ? $0 : nil }
    }

    @MainActor var fileItem: FileShelfItem? {
        guard let url else { return nil }
        return FileShelfModel.makeItem(
            url: url,
            id: id,
            displayName: displayName ?? url.lastPathComponent,
            kind: kind ?? .file,
            originalSourceDescription: originalSourceDescription ?? "Stack item",
            originalFileURL: originalFileURLString.flatMap(URL.init(string:)),
            localURL: localURLString.flatMap(URL.init(string:))
        )
    }
}

struct ShelfStack: Codable, Equatable {
    let id: UUID
    var name: String
    var entries: [ShelfStackEntry]
    var parentStackID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        entries: [ShelfStackEntry] = [],
        parentStackID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.parentStackID = parentStackID
    }
}

enum ShelfStackRemovalOutcome {
    case kept
    case removedEmpty
    case dissolved(remainingItem: FileShelfItem)
}

@MainActor
final class ShelfStackModel {
    private static let storageKey = "ShelfBar.folderStacks.v1"

    private(set) var stacks: [ShelfStack]
    var onChange: (([ShelfStack]) -> Void)?

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ShelfStack].self, from: data)
        else {
            stacks = []
            return
        }
        stacks = decoded
    }

    @discardableResult
    func create(name: String) -> UUID {
        create(name: name, entries: [])
    }

    @discardableResult
    func create(name: String, entries: [(id: UUID, url: URL)]) -> UUID {
        create(
            name: name,
            items: entries.map { FileShelfModel.makeItem(url: $0.url, id: $0.id) },
            parentStackID: nil
        )
    }

    @discardableResult
    func create(
        name: String,
        items: [FileShelfItem],
        parentStackID: UUID?
    ) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stack = ShelfStack(
            name: trimmed.isEmpty ? nextAutomaticName() : trimmed,
            entries: items.map(ShelfStackEntry.init(item:)),
            parentStackID: parentStackID
        )
        stacks.append(stack)
        commit()
        return stack.id
    }

    func rename(id: UUID, name: String) {
        guard let index = stacks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stacks[index].name = trimmed
        commit()
    }

    func remove(id: UUID) {
        guard let index = stacks.firstIndex(where: { $0.id == id }) else { return }
        stacks.remove(at: index)
        commit()
    }

    func clear() {
        guard !stacks.isEmpty else { return }
        stacks.removeAll()
        commit()
    }

    func add(url: URL, to stackID: UUID, entryID: UUID = UUID()) {
        add(item: FileShelfModel.makeItem(url: url, id: entryID), to: stackID)
    }

    func add(item: FileShelfItem, to stackID: UUID) {
        guard let index = stacks.firstIndex(where: { $0.id == stackID }) else { return }
        let path = item.url.standardizedFileURL.path
        guard !stacks[index].entries.contains(where: { $0.url?.standardizedFileURL.path == path }) else {
            return
        }
        stacks[index].entries.append(ShelfStackEntry(item: item))
        commit()
    }

    @discardableResult
    func removeFile(
        id: UUID,
        from stackID: UUID,
        autoDissolveSingle: Bool
    ) -> ShelfStackRemovalOutcome {
        guard let stackIndex = stacks.firstIndex(where: { $0.id == stackID }),
              let entryIndex = stacks[stackIndex].entries.firstIndex(where: { $0.id == id })
        else { return .kept }
        stacks[stackIndex].entries.remove(at: entryIndex)
        let hasChildStacks = stacks.contains { $0.parentStackID == stackID }
        if stacks[stackIndex].entries.isEmpty && !hasChildStacks {
            stacks.remove(at: stackIndex)
            commit()
            return .removedEmpty
        }
        if autoDissolveSingle,
           !hasChildStacks,
           stacks[stackIndex].entries.count == 1,
           let remainingItem = stacks[stackIndex].entries[0].fileItem {
            stacks.remove(at: stackIndex)
            commit()
            return .dissolved(remainingItem: remainingItem)
        }
        commit()
        return .kept
    }

    func stack(id: UUID) -> ShelfStack? {
        stacks.first { $0.id == id }
    }

    var rootStacks: [ShelfStack] {
        stacks.filter { $0.parentStackID == nil }
    }

    func childStacks(of parentID: UUID) -> [ShelfStack] {
        stacks.filter { $0.parentStackID == parentID }
    }

    func directItemCount(in stackID: UUID) -> Int {
        (stack(id: stackID)?.entries.count ?? 0) + childStacks(of: stackID).count
    }

    func fileItems(in stackID: UUID) -> [FileShelfItem] {
        guard let stack = stack(id: stackID) else { return [] }
        return stack.entries.compactMap(\.fileItem)
    }

    func moveFile(id: UUID, in stackID: UUID, to destinationIndex: Int) {
        guard let stackIndex = stacks.firstIndex(where: { $0.id == stackID }),
              let sourceIndex = stacks[stackIndex].entries.firstIndex(where: { $0.id == id })
        else { return }
        let entry = stacks[stackIndex].entries.remove(at: sourceIndex)
        var adjusted = destinationIndex
        if sourceIndex < adjusted { adjusted -= 1 }
        adjusted = min(max(adjusted, 0), stacks[stackIndex].entries.count)
        stacks[stackIndex].entries.insert(entry, at: adjusted)
        commit()
    }

    func removeFiles(ids: Set<UUID>, from stackID: UUID) {
        guard let index = stacks.firstIndex(where: { $0.id == stackID }) else { return }
        stacks[index].entries.removeAll { ids.contains($0.id) }
        commit()
    }

    func moveStack(id: UUID, toParent parentID: UUID?) {
        guard let index = stacks.firstIndex(where: { $0.id == id }), id != parentID else { return }
        stacks[index].parentStackID = parentID
        commit()
    }

    func normalize(autoDissolveSingle: Bool) -> [FileShelfItem] {
        var recoveredItems: [FileShelfItem] = []
        let original = stacks
        let parentsWithChildren = Set(stacks.compactMap(\.parentStackID))
        stacks.removeAll { stack in
            if stack.entries.isEmpty && !parentsWithChildren.contains(stack.id) {
                return true
            }
            if autoDissolveSingle,
               stack.parentStackID == nil,
               !parentsWithChildren.contains(stack.id),
               stack.entries.count == 1,
               let item = stack.entries[0].fileItem {
                recoveredItems.append(item)
                return true
            }
            return false
        }
        if stacks != original {
            commit()
        }
        return recoveredItems
    }

    private func nextAutomaticName() -> String {
        let existing = Set(stacks.map { $0.name })
        guard existing.contains("Stack") else { return "Stack" }
        var suffix = 2
        while existing.contains("Stack \(suffix)") {
            suffix += 1
        }
        return "Stack \(suffix)"
    }

    private func commit() {
        if let data = try? JSONEncoder().encode(stacks) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        onChange?(stacks)
    }
}
