import Foundation
import Combine

/// User-tunable preferences plus the per-app capture rules that decide whether
/// (and how) clipi records a given app's clipboard activity.
///
/// Backed by `UserDefaults`. SwiftUI views observe via `@ObservedObject` and
/// mutating values writes through immediately.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var rules: [AppRule] {
        didSet { persistRules() }
    }

    /// When true, copies made while the frontmost app's focused UI element is an
    /// `AXSecureTextField` (i.e., a password input) are dropped before they ever
    /// reach the store. Defends against browser password fields and any app that
    /// doesn't respect the `org.nspasteboard` concealed convention.
    @Published var excludeSecureFields: Bool {
        didSet { defaults.set(excludeSecureFields, forKey: Keys.excludeSecureFields) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let rules = "AppRules"
        static let excludeSecureFields = "ExcludeSecureFields"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Prefs migrate from "no key set" → defaults, on first launch.
        self.excludeSecureFields = (defaults.object(forKey: Keys.excludeSecureFields) as? Bool) ?? true
        self.rules = Self.loadRules(from: defaults) ?? Self.defaultRules
    }

    /// Returns the active capture mode for a given source app. Apps with no
    /// matching rule fall through to `.record` (the default policy).
    func mode(for bundleID: String?) -> AppRule.Mode {
        guard let bundleID,
              let rule = rules.first(where: { $0.bundleID == bundleID }) else {
            return .record
        }
        return rule.mode
    }

    func setRule(_ rule: AppRule) {
        if let idx = rules.firstIndex(where: { $0.bundleID == rule.bundleID }) {
            rules[idx] = rule
        } else {
            rules.append(rule)
        }
    }

    func removeRule(bundleID: String) {
        rules.removeAll { $0.bundleID == bundleID }
    }

    // MARK: – Persistence

    private func persistRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: Keys.rules)
    }

    private static func loadRules(from defaults: UserDefaults) -> [AppRule]? {
        guard let data = defaults.data(forKey: Keys.rules) else { return nil }
        return try? JSONDecoder().decode([AppRule].self, from: data)
    }

    /// Default rules shipped with a fresh install. Aggressively excludes the
    /// well-known password managers — most of them already respect the
    /// `org.nspasteboard` concealed convention, but we layer this denylist on
    /// top so a misbehaving / older version can't leak credentials.
    static let defaultRules: [AppRule] = [
        AppRule(bundleID: "com.agilebits.onepassword7",  appName: "1Password 7",     mode: .exclude),
        AppRule(bundleID: "com.1password.1password",     appName: "1Password",       mode: .exclude),
        AppRule(bundleID: "com.bitwarden.desktop",       appName: "Bitwarden",       mode: .exclude),
        AppRule(bundleID: "com.apple.keychainaccess",    appName: "Keychain Access", mode: .exclude),
        AppRule(bundleID: "com.lastpass.LastPass",       appName: "LastPass",        mode: .exclude),
        AppRule(bundleID: "com.dashlane.DashlaneApp",    appName: "Dashlane",        mode: .exclude),
        AppRule(bundleID: "com.protonpass.macos",        appName: "Proton Pass",     mode: .exclude),
        AppRule(bundleID: "com.apple.Terminal",          appName: "Terminal",        mode: .plain),
        AppRule(bundleID: "com.googlecode.iterm2",       appName: "iTerm",           mode: .plain),
    ]
}

/// One row in the per-app rules table. Identified by bundle ID so a rule
/// survives the user reinstalling/updating the source app.
struct AppRule: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    var appName: String
    var mode: Mode

    enum Mode: String, Codable, CaseIterable {
        /// Never record copies originating in this app.
        case exclude
        /// Record copies but strip rich pasteboard types — store only the plain
        /// `public.utf8-plain-text` representation. Useful for terminals and
        /// other apps that emit text with embedded control sequences.
        case plain
        /// Default — record everything the pasteboard offers.
        case record

        var displayName: String {
            switch self {
            case .exclude: return "Never record"
            case .plain:   return "Plain text only"
            case .record:  return "Record everything"
            }
        }
    }
}
