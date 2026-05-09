import Foundation
import ObjectiveC

// MARK: - LanguageManager

final class LanguageManager: ObservableObject {

    static let shared = LanguageManager()

    @Published private(set) var currentLanguage: String

    /// The active .lproj bundle. Use `loc(_:)` instead of accessing this directly.
    private(set) var currentBundle: Bundle = .main

    let supported: [(code: String, displayName: String)] = [
        ("en", "English"),
        ("bg", "Български"),
    ]

    private init() {
        // Swizzle first so NSLocalizedString in ViewModels also uses the right bundle.
        BundleSwizzle.install()

        let saved = UserDefaults.standard.string(forKey: "appLanguage")
        currentLanguage = ["en", "bg"].contains(saved ?? "") ? saved! : "en"
        applyBundle(currentLanguage)
    }

    func select(_ code: String) {
        guard supported.map(\.code).contains(code), code != currentLanguage else { return }
        currentLanguage = code
        UserDefaults.standard.set(code, forKey: "appLanguage")
        applyBundle(code)
    }

    private func applyBundle(_ code: String) {
        let path = Bundle.main.bundlePath + "/\(code).lproj"
        let b = Bundle(path: path) ?? Bundle.main
        currentBundle = b
        BundleSwizzle.languageBundle = b
    }
}

// MARK: - loc() helper

/// Returns the localised string for `key` from the active language bundle.
///
/// Use this for every SwiftUI `Text` / `Label` literal so the string is
/// resolved through our language bundle rather than SwiftUI's internal cache.
///
///     Text(loc("Camera"))
///     Label(loc("Settings"), systemImage: "gear")
func loc(_ key: String) -> String {
    LanguageManager.shared.currentBundle
        .localizedString(forKey: key, value: key, table: nil)
}

// MARK: - Bundle swizzle (for NSLocalizedString in ViewModels)

private enum BundleSwizzle {
    static var languageBundle: Bundle?

    static func install() {
        let original = #selector(Bundle.localizedString(forKey:value:table:))
        let hooked   = #selector(Bundle._hookedLocalizedString(forKey:value:table:))
        guard
            let orig = class_getInstanceMethod(Bundle.self, original),
            let hook = class_getInstanceMethod(Bundle.self, hooked)
        else { return }
        method_exchangeImplementations(orig, hook)
    }
}

extension Bundle {
    @objc func _hookedLocalizedString(
        forKey key: String, value: String?, table tableName: String?
    ) -> String {
        guard self === Bundle.main, let b = BundleSwizzle.languageBundle else {
            return _hookedLocalizedString(forKey: key, value: value, table: tableName)
        }
        return b._hookedLocalizedString(forKey: key, value: value, table: tableName)
    }
}
