import Foundation

enum SettingsKey {
    static let destination = "destinationPath"
    static let maxConcurrent = "maxConcurrentDownloads"
    static let quality = "qualityPreset"
    static let learnSites = "learnSites"
}

enum AppSettings {
    static let concurrencyRange = 1...10
    static let defaultMaxConcurrent = 5

    static var defaultDestination: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
    }

    static var destination: String {
        let stored = UserDefaults.standard.string(forKey: SettingsKey.destination) ?? ""
        return stored.isEmpty ? defaultDestination : stored
    }

    static var maxConcurrent: Int {
        let stored = UserDefaults.standard.integer(forKey: SettingsKey.maxConcurrent)
        return stored == 0 ? defaultMaxConcurrent : min(max(stored, concurrencyRange.lowerBound), concurrencyRange.upperBound)
    }

    static var quality: QualityPreset {
        UserDefaults.standard.string(forKey: SettingsKey.quality).flatMap(QualityPreset.init(rawValue:)) ?? .configFile
    }

    static var learnSites: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.learnSites) as? Bool ?? true
    }
}
