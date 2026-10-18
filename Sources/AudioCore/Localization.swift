import Foundation

public enum AppLanguage {
    public static let codes = ["en","it","fr","de","es"]
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: codes.compactMap { code in
        guard let path = Bundle.module.path(forResource: code,ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        return (code,bundle)
    })
    public static var current: String { UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "en" }
    public static func translate(_ key: String, language: String) -> String {
        guard let bundle = bundles[language] ?? bundles["en"] else { return key }
        return bundle.localizedString(forKey: key,value: key,table: nil)
    }
}
public func T(_ key: String) -> String { AppLanguage.translate(key,language: AppLanguage.current) }
public func F(_ key: String, _ arguments: CVarArg...) -> String { String(format: T(key),locale: Locale(identifier: AppLanguage.current),arguments: arguments) }
