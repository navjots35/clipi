import AppKit

/// Encodes a `[ClipboardItem]` to disk and back, using a JSON document at
/// `~/Library/Application Support/clipi/history.json`. NSImage isn't Codable,
/// so we serialize each item's raw pasteboard representations and rebuild the
/// `Kind` (and the NSImage) on load by pulling the original PNG/TIFF bytes
/// out of the snapshot — exactly the path that gave us the image in the first
/// place during capture.
final class HistoryPersistence {
    static let shared = HistoryPersistence()

    private let url: URL

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = support.appendingPathComponent("clipi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("history.json")
    }

    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let persisted = try? JSONDecoder().decode([PersistedItem].self, from: data) else { return [] }
        return persisted.compactMap(ClipboardItem.init(persisted:))
    }

    func save(_ items: [ClipboardItem]) {
        let persisted = items.map { $0.toPersisted() }
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Path is exposed for the Settings → History → "Clear history…" flow so
    /// the file can be removed alongside the in-memory store.
    var fileURL: URL { url }
}

// MARK: – Persistence DTOs

struct PersistedRep: Codable {
    var type: String
    var data: Data
}

struct PersistedItem: Codable {
    enum KindTag: String, Codable { case text, image, fileURLs, other }
    var addedAt: Date
    var sourceBundleID: String?
    var sourceAppName: String?
    var representations: [PersistedRep]
    var kindTag: KindTag
    var text: String?
    var fileURLs: [URL]?
    var otherUTI: String?
}

extension ClipboardItem {
    init?(persisted p: PersistedItem) {
        let reps: [(type: NSPasteboard.PasteboardType, data: Data)] = p.representations.map {
            (type: NSPasteboard.PasteboardType($0.type), data: $0.data)
        }
        let snapshot = PasteboardSnapshot(representations: reps)
        let kind: Kind
        switch p.kindTag {
        case .text:
            guard let s = p.text else { return nil }
            kind = .text(s)
        case .image:
            let imgData = reps.first(where: { $0.type == .png || $0.type == .tiff })?.data
            guard let imgData, let img = NSImage(data: imgData) else { return nil }
            kind = .image(img)
        case .fileURLs:
            guard let urls = p.fileURLs, !urls.isEmpty else { return nil }
            kind = .fileURLs(urls)
        case .other:
            kind = .other(uti: p.otherUTI ?? "")
        }
        self.init(snapshot: snapshot, kind: kind, addedAt: p.addedAt,
                  sourceBundleID: p.sourceBundleID, sourceAppName: p.sourceAppName)
    }

    func toPersisted() -> PersistedItem {
        let reps = snapshot.representations.map {
            PersistedRep(type: $0.type.rawValue, data: $0.data)
        }
        let tag: PersistedItem.KindTag
        var text: String?
        var fileURLs: [URL]?
        var otherUTI: String?
        switch kind {
        case .text(let s):     tag = .text;     text = s
        case .image:           tag = .image
        case .fileURLs(let u): tag = .fileURLs; fileURLs = u
        case .other(let uti):  tag = .other;    otherUTI = uti
        }
        return PersistedItem(addedAt: addedAt,
                             sourceBundleID: sourceBundleID,
                             sourceAppName: sourceAppName,
                             representations: reps,
                             kindTag: tag,
                             text: text,
                             fileURLs: fileURLs,
                             otherUTI: otherUTI)
    }
}
