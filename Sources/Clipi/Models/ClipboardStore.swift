import AppKit
import Combine

final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var maxItems: Int {
        didSet {
            UserDefaults.standard.set(maxItems, forKey: "MaxItems")
            trim()
            save()
        }
    }

    private let persistence: HistoryPersistence
    private static let defaultMaxItems = 10

    init(persistence: HistoryPersistence = .shared) {
        self.persistence = persistence
        let stored = UserDefaults.standard.object(forKey: "MaxItems") as? Int
        self.maxItems = stored ?? Self.defaultMaxItems
        self.items = persistence.load()
        trim()
    }

    func add(_ item: ClipboardItem) {
        // Promote-to-top dedupe: if we've already got this content anywhere in the
        // list, move it to the head instead of inserting a copy.
        if let existingIdx = items.firstIndex(where: { $0.dedupeKey == item.dedupeKey }) {
            if existingIdx == 0 { return }
            let existing = items.remove(at: existingIdx)
            items.insert(existing, at: 0)
            save()
            return
        }
        items.insert(item, at: 0)
        trim()
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func trim() {
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }

    private func save() {
        persistence.save(items)
    }
}
