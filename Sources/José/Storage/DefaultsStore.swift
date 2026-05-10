import Foundation

enum DefaultsKey: String {
    case launchAtLogin = "general.launchAtLogin"
    case showInDock = "general.showInDock"
    case showUsageInMenuBar = "general.showUsageInMenuBar"

    case hotkeyAMode = "hotkey.A.mode"
    case hotkeyBMode = "hotkey.B.mode"
    case hotkeyAModifierMask = "hotkey.A.modifierMask"
    case hotkeyBModifierMask = "hotkey.B.modifierMask"

    case inputDeviceUID = "audio.inputDeviceUID"

    case transcriptionModel = "transcription.model"
    case streamingEnabled = "transcription.streaming"
    case systemPrompt = "transcription.systemPrompt"

    case vocabularyEnabledCategories = "vocabulary.enabled"
    case customVocabulary = "vocabulary.custom"

    case restorePreviousClipboard = "output.restorePreviousClipboard"

    case softLimitMinutes = "softLimitMinutes"
    case hardLimitMinutes = "hardLimitMinutes"

    case usageMonthBucket = "usage.monthBucket"
    case usageSecondsByModel = "usage.secondsByModel"

    case onboardingCompleted = "onboarding.completed"

    case bundledPromptVersion = "transcription.bundledPromptVersion"
}

enum Defaults {
    private static let store = UserDefaults.standard

    // MARK: Read
    static func bool(for key: DefaultsKey) -> Bool? {
        store.object(forKey: key.rawValue) == nil ? nil : store.bool(forKey: key.rawValue)
    }
    static func int(for key: DefaultsKey) -> Int? {
        store.object(forKey: key.rawValue) == nil ? nil : store.integer(forKey: key.rawValue)
    }
    static func uint(for key: DefaultsKey) -> UInt? {
        guard let raw = store.object(forKey: key.rawValue) as? NSNumber else { return nil }
        return UInt(truncating: raw)
    }
    static func string(for key: DefaultsKey) -> String? {
        store.string(forKey: key.rawValue)
    }
    static func stringArray(for key: DefaultsKey) -> [String]? {
        store.stringArray(forKey: key.rawValue)
    }
    static func data(for key: DefaultsKey) -> Data? {
        store.data(forKey: key.rawValue)
    }
    static func double(for key: DefaultsKey) -> Double? {
        store.object(forKey: key.rawValue) == nil ? nil : store.double(forKey: key.rawValue)
    }
    static func dictionary(for key: DefaultsKey) -> [String: Any]? {
        store.dictionary(forKey: key.rawValue)
    }

    // MARK: Write
    static func set(_ value: Bool, for key: DefaultsKey) {
        store.set(value, forKey: key.rawValue)
    }
    static func set(_ value: Int, for key: DefaultsKey) {
        store.set(value, forKey: key.rawValue)
    }
    static func set(_ value: Double, for key: DefaultsKey) {
        store.set(value, forKey: key.rawValue)
    }
    static func set(_ value: UInt?, for key: DefaultsKey) {
        if let value {
            store.set(NSNumber(value: value), forKey: key.rawValue)
        } else {
            store.removeObject(forKey: key.rawValue)
        }
    }
    static func set(_ value: String?, for key: DefaultsKey) {
        if let value {
            store.set(value, forKey: key.rawValue)
        } else {
            store.removeObject(forKey: key.rawValue)
        }
    }
    static func set(_ value: [String], for key: DefaultsKey) {
        store.set(value, forKey: key.rawValue)
    }
    static func set(_ value: Data?, for key: DefaultsKey) {
        if let value {
            store.set(value, forKey: key.rawValue)
        } else {
            store.removeObject(forKey: key.rawValue)
        }
    }
    static func set(_ value: [String: Any], for key: DefaultsKey) {
        store.set(value, forKey: key.rawValue)
    }
}
