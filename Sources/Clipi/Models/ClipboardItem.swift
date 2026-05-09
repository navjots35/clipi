import AppKit

struct PasteboardSnapshot {
    let representations: [(type: NSPasteboard.PasteboardType, data: Data)]

    init(representations: [(type: NSPasteboard.PasteboardType, data: Data)]) {
        self.representations = representations
    }

    init?(item: NSPasteboardItem) {
        var reps: [(NSPasteboard.PasteboardType, Data)] = []
        for type in item.types {
            if let data = item.data(forType: type) {
                reps.append((type, data))
            }
        }
        guard !reps.isEmpty else { return nil }
        self.representations = reps
    }

    func write(to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        for rep in representations {
            item.setData(rep.data, forType: rep.type)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    var contentSignature: Int {
        var hasher = Hasher()
        for rep in representations {
            hasher.combine(rep.type.rawValue)
            hasher.combine(rep.data)
        }
        return hasher.finalize()
    }
}

struct ClipboardItem: Identifiable {
    enum Kind {
        case text(String)
        case image(NSImage)
        case fileURLs([URL])
        case other(uti: String)
    }

    let id = UUID()
    let snapshot: PasteboardSnapshot
    let kind: Kind
    let addedAt: Date
    /// Bundle ID of the app frontmost when the copy was detected. Used for filtering
    /// and "from Safari" subtitles. Nil if no app was frontmost (rare).
    let sourceBundleID: String?
    /// Localized name of the source app (e.g., "Google Chrome").
    let sourceAppName: String?

    /// Stable key used to suppress duplicates. Kind-aware so two file copies match
    /// even when their pasteboard payloads carry different transient metadata.
    var dedupeKey: String {
        switch kind {
        case .text(let s):
            return "text:\(s)"
        case .image:
            return "image:\(snapshot.contentSignature)"
        case .fileURLs(let urls):
            // Use canonicalized filesystem paths so two copies of the same file always match,
            // regardless of percent-encoding differences in the URL representation.
            let paths = urls.map { $0.standardizedFileURL.path }.sorted().joined(separator: "|")
            return "files:\(paths)"
        case .other(let uti):
            return "other:\(uti):\(snapshot.contentSignature)"
        }
    }

    var previewTitle: String {
        switch kind {
        case .text(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let oneLine = trimmed.replacingOccurrences(of: "\n", with: " ")
            return String(oneLine.prefix(120))
        case .image(let img):
            let size = img.size
            return "Image \(Int(size.width))×\(Int(size.height))"
        case .fileURLs(let urls):
            if urls.count == 1 { return urls[0].lastPathComponent }
            return "\(urls.count) files: " + urls.prefix(3).map { $0.lastPathComponent }.joined(separator: ", ")
        case .other(let uti):
            return "Rich content (\(uti))"
        }
    }

    var typeLabel: String {
        switch kind {
        case .text: return "Text"
        case .image: return "Image"
        case .fileURLs(let urls): return urls.count == 1 ? "File" : "\(urls.count) files"
        case .other(let uti): return uti
        }
    }

    /// Human-readable size hint for the row subtitle. Returns nil when irrelevant.
    var sizeHint: String? {
        switch kind {
        case .text(let s):
            let count = s.count
            return count > 0 ? "\(count) char\(count == 1 ? "" : "s")" : nil
        case .image(let img):
            return "\(Int(img.size.width))×\(Int(img.size.height))"
        case .fileURLs, .other:
            return nil
        }
    }

    /// Lower-cased haystack for the search filter (title + source app name).
    var searchHaystack: String {
        var parts = [previewTitle.lowercased()]
        if let n = sourceAppName { parts.append(n.lowercased()) }
        if case .text(let s) = kind { parts.append(s.lowercased()) }
        return parts.joined(separator: " ")
    }
}

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

extension ClipboardItem {
    /// "now", "2m ago", "1h ago", etc. Recomputed on each access.
    var relativeTimeText: String {
        let secondsAgo = -addedAt.timeIntervalSinceNow
        if secondsAgo < 5 { return "now" }
        return relativeFormatter.localizedString(for: addedAt, relativeTo: Date())
    }
}

/// Visual sub-classification of a clipboard item, used to pick the row's tinted
/// type icon. Matches the categories in the Clipi design (link, code, color,
/// email, json, phone, markdown, file, image, plain text).
enum ContentType {
    case link, code, color(hex: String), email, json, phone, markdown, file, image, text, other
}

extension ClipboardItem {
    var contentType: ContentType {
        switch kind {
        case .image: return .image
        case .fileURLs: return .file
        case .other: return .other
        case .text(let raw):
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return .text }
            if let hex = Self.hexColor(in: s) { return .color(hex: hex) }
            if Self.isLink(s) { return .link }
            if Self.isEmail(s) { return .email }
            if Self.isPhone(s) { return .phone }
            if Self.isJSON(s) { return .json }
            if Self.isMarkdown(s) { return .markdown }
            if Self.looksLikeCode(s) { return .code }
            return .text
        }
    }

    /// Whether the row should render its title in a monospaced font.
    var isMonospaceContent: Bool {
        switch contentType {
        case .code, .json, .file, .markdown: return true
        default: return false
        }
    }

    // MARK: – Detection helpers

    private static func hexColor(in s: String) -> String? {
        // #RRGGBB or #RRGGBBAA — exact-match only, otherwise text wins.
        let pattern = #"^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#
        guard s.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return s.hasPrefix("#") ? s.uppercased() : "#" + s.uppercased()
    }

    private static func isLink(_ s: String) -> Bool {
        guard !s.contains(" "), s.count < 2048 else { return false }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return true }
        // Bare domain like "figma.com/…" — require a 2+ letter TLD so version strings
        // ("1.2.0") and fragmentary text ("Hello.world") don't trigger.
        let pattern = #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}(/.*)?$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isEmail(_ s: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isPhone(_ s: String) -> Bool {
        // Permissive: needs 7+ digits and only phone-y characters.
        let digits = s.filter(\.isNumber).count
        guard digits >= 7, digits <= 15 else { return false }
        let allowed = CharacterSet(charactersIn: "+0123456789()-. ")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isJSON(_ s: String) -> Bool {
        guard let first = s.first, let last = s.last else { return false }
        guard (first == "{" && last == "}") || (first == "[" && last == "]") else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(s.utf8))) != nil
    }

    private static func isMarkdown(_ s: String) -> Bool {
        // Very loose: starts with a heading, list, or fenced code marker.
        let prefixes = ["# ", "## ", "### ", "- ", "* ", "1. ", "```"]
        return prefixes.contains { s.hasPrefix($0) }
    }

    private static func looksLikeCode(_ s: String) -> Bool {
        // Heuristics that catch most snippets without false-positiving on prose.
        if s.contains("\n") {
            let lines = s.split(separator: "\n")
            // Indented multi-line content is almost always code.
            if lines.contains(where: { $0.hasPrefix("  ") || $0.hasPrefix("\t") }) { return true }
        }
        let codeTokens = ["() =>", "function ", "const ", "let ", "var ", "import ", "class ",
                          "def ", "return ", "=>", "#include", "</", "/>"]
        return codeTokens.contains(where: { s.contains($0) })
    }
}

extension ClipboardItem {
    /// Build a `ClipboardItem` from an `NSPasteboardItem`, classifying its kind for display.
    /// Returns nil if the item is empty or marked transient/concealed by other apps.
    /// When `plainOnly` is true (the source app has a `.plain` rule), only the
    /// `public.utf8-plain-text` representation is captured — image/file/rich types
    /// are dropped so a terminal-style rule can't accidentally store screenshots
    /// pasted from the same app, and paste-back can't leak rich payloads.
    static func make(from pbItem: NSPasteboardItem,
                     bundleID: String? = nil,
                     appName: String? = nil,
                     plainOnly: Bool = false) -> ClipboardItem? {
        // Respect the org.nspasteboard.org convention: don't store secrets.
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let autogen = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
        if pbItem.types.contains(transient) || pbItem.types.contains(concealed) || pbItem.types.contains(autogen) {
            return nil
        }

        let types = pbItem.types
        let now = Date()

        if plainOnly {
            guard types.contains(.string),
                  let str = pbItem.string(forType: .string), !str.isEmpty,
                  let data = str.data(using: .utf8) else { return nil }
            let snapshot = PasteboardSnapshot(representations: [(type: .string, data: data)])
            return ClipboardItem(snapshot: snapshot, kind: .text(str),
                                 addedAt: now, sourceBundleID: bundleID, sourceAppName: appName)
        }

        guard let snapshot = PasteboardSnapshot(item: pbItem) else { return nil }

        if types.contains(.fileURL) {
            if let str = pbItem.string(forType: .fileURL), let url = URL(string: str) {
                return ClipboardItem(snapshot: snapshot, kind: .fileURLs([url]),
                                     addedAt: now, sourceBundleID: bundleID, sourceAppName: appName)
            }
        }
        if types.contains(.tiff) || types.contains(.png) {
            let data = pbItem.data(forType: .png) ?? pbItem.data(forType: .tiff)
            if let data, let image = NSImage(data: data) {
                return ClipboardItem(snapshot: snapshot, kind: .image(image),
                                     addedAt: now, sourceBundleID: bundleID, sourceAppName: appName)
            }
        }
        if types.contains(.string) {
            if let str = pbItem.string(forType: .string), !str.isEmpty {
                return ClipboardItem(snapshot: snapshot, kind: .text(str),
                                     addedAt: now, sourceBundleID: bundleID, sourceAppName: appName)
            }
        }
        if let firstType = types.first {
            return ClipboardItem(snapshot: snapshot, kind: .other(uti: firstType.rawValue),
                                 addedAt: now, sourceBundleID: bundleID, sourceAppName: appName)
        }
        return nil
    }
}
