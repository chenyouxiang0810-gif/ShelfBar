import Foundation

enum ShelfSearchResult {
    case file(FileShelfItem)
    case stack(ShelfStack)
    case stackFile(stackID: UUID, stackName: String, entry: ShelfStackEntry)
    case clipboard(ClipboardShelfItem)
    case recent(RecentShelfItem)

    var id: UUID {
        switch self {
        case let .file(item): item.id
        case let .stack(stack): stack.id
        case let .stackFile(_, _, entry): entry.id
        case let .clipboard(item): item.id
        case let .recent(item): item.id
        }
    }

    var title: String {
        switch self {
        case let .file(item): item.filename
        case let .stack(stack): stack.name
        case let .stackFile(_, _, entry): entry.displayName ?? entry.url?.lastPathComponent ?? "Stack item"
        case let .clipboard(item): item.title
        case let .recent(item): item.title
        }
    }
}

struct SearchController {
    static func results(
        query: String,
        files: [FileShelfItem],
        favorites: [FileShelfItem],
        stacks: [ShelfStack] = [],
        clipboard: [ClipboardShelfItem],
        recent: [RecentShelfItem]
    ) -> [ShelfSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        var seen: Set<String> = []
        var output: [ShelfSearchResult] = []

        for item in favorites + files where matches(file: item, needle: needle) {
            let key = "file:\(item.url.absoluteString)"
            if seen.insert(key).inserted { output.append(.file(item)) }
        }
        for stack in stacks {
            if matches(stack: stack, needle: needle) {
                let key = "stack:\(stack.id)"
                if seen.insert(key).inserted { output.append(.stack(stack)) }
            }
            for entry in stack.entries where matches(entry: entry, needle: needle) {
                let key = "stack-file:\(stack.id):\(entry.id)"
                if seen.insert(key).inserted {
                    output.append(.stackFile(stackID: stack.id, stackName: stack.name, entry: entry))
                }
            }
        }
        for item in clipboard where matches(clipboard: item, needle: needle) {
            let key = "clipboard:\(item.stableKey)"
            if seen.insert(key).inserted { output.append(.clipboard(item)) }
        }
        for item in recent where matches(recent: item, needle: needle) {
            let key = "recent:\(item.key)"
            if seen.insert(key).inserted { output.append(.recent(item)) }
        }
        return output
    }

    private static func matches(file item: FileShelfItem, needle: String) -> Bool {
        [
            item.filename,
            item.originalFileURL?.lastPathComponent ?? "",
            item.localURL?.lastPathComponent ?? ""
        ].contains { $0.lowercased().contains(needle) }
    }

    private static func matches(stack: ShelfStack, needle: String) -> Bool {
        stack.name.lowercased().contains(needle)
    }

    private static func matches(entry: ShelfStackEntry, needle: String) -> Bool {
        [
            entry.displayName ?? "",
            entry.url?.lastPathComponent ?? "",
            URL(string: entry.urlString)?.lastPathComponent ?? ""
        ].contains { $0.lowercased().contains(needle) }
    }

    private static func matches(clipboard item: ClipboardShelfItem, needle: String) -> Bool {
        [
            item.title,
            item.text ?? "",
            item.urlString ?? "",
            item.fileURLString ?? ""
        ].contains { $0.lowercased().contains(needle) }
    }

    private static func matches(recent item: RecentShelfItem, needle: String) -> Bool {
        [
            item.title,
            item.urlString.flatMap { URL(string: $0)?.lastPathComponent } ?? ""
        ].contains { $0.lowercased().contains(needle) }
    }
}
