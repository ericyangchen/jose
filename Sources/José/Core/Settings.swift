import Foundation
import Observation

enum TranscriptionModel: String, Codable, CaseIterable, Sendable {
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"

    var displayName: String {
        switch self {
        case .gpt4oTranscribe: "gpt-4o-transcribe"
        case .gpt4oMiniTranscribe: "gpt-4o-mini-transcribe"
        }
    }

    /// US dollars per minute of audio. Source: OpenAI public pricing as of 2026-05.
    var costPerMinute: Double {
        switch self {
        case .gpt4oTranscribe: 0.006
        case .gpt4oMiniTranscribe: 0.003
        }
    }
}

enum HotkeyMode: String, Codable, CaseIterable, Sendable {
    case hold
    case toggle
}

/// Stable categories for the default vocabulary. Each is independently
/// toggleable in Settings → Vocabulary.
enum VocabularyCategory: String, Codable, CaseIterable, Sendable {
    case languagesFrameworks = "languages_frameworks"
    case infrastructure
    case databases
    case protocolsApis = "protocols_apis"
    case aiMl = "ai_ml"
    case generalDev = "general_dev"

    var displayName: String {
        switch self {
        case .languagesFrameworks: "Languages & Frameworks"
        case .infrastructure: "Infrastructure"
        case .databases: "Databases"
        case .protocolsApis: "Protocols & APIs"
        case .aiMl: "AI / ML"
        case .generalDev: "General Dev"
        }
    }
}

@Observable
@MainActor
final class Settings {
    static let shared = Settings()

    /// Bump when DefaultPrompt.md changes meaningfully. Existing installs
    /// with a stored prompt below this version are auto-refreshed from
    /// the bundle on next launch (unless the user has already edited it).
    static let currentBundledPromptVersion: Int = 3

    /// Bump when default hotkey bindings change. Existing installs whose
    /// stored version is below this get a one-shot reset to the new
    /// defaults (slot A → Fn). User-customized bindings are preserved.
    static let currentHotkeyDefaultsVersion: Int = 1

    // MARK: General
    var launchAtLogin: Bool {
        didSet { Defaults.set(launchAtLogin, for: .launchAtLogin) }
    }
    var showInDock: Bool {
        didSet { Defaults.set(showInDock, for: .showInDock) }
    }
    var showUsageInMenuBar: Bool {
        didSet { Defaults.set(showUsageInMenuBar, for: .showUsageInMenuBar) }
    }
    var showMenuBarIcon: Bool {
        didSet { Defaults.set(showMenuBarIcon, for: .showMenuBarIcon) }
    }

    // MARK: Hotkey modes (the actual key bindings are owned by the
    // KeyboardShortcuts library + a separate ModifierHotkey store).
    var hotkeyAMode: HotkeyMode {
        didSet { Defaults.set(hotkeyAMode.rawValue, for: .hotkeyAMode) }
    }
    var hotkeyBMode: HotkeyMode {
        didSet { Defaults.set(hotkeyBMode.rawValue, for: .hotkeyBMode) }
    }

    /// If a single-modifier hotkey is preferred for slot A/B, store its raw
    /// device-mask bits here. nil means "use the KeyboardShortcuts combo".
    var hotkeyAModifierMask: UInt?  {
        didSet { Defaults.set(hotkeyAModifierMask, for: .hotkeyAModifierMask) }
    }
    var hotkeyBModifierMask: UInt?  {
        didSet { Defaults.set(hotkeyBModifierMask, for: .hotkeyBModifierMask) }
    }

    // MARK: Audio
    var inputDeviceUID: String? {
        didSet { Defaults.set(inputDeviceUID, for: .inputDeviceUID) }
    }

    // MARK: Transcription
    var transcriptionModel: TranscriptionModel {
        didSet { Defaults.set(transcriptionModel.rawValue, for: .transcriptionModel) }
    }
    var streamingEnabled: Bool {
        didSet { Defaults.set(streamingEnabled, for: .streamingEnabled) }
    }
    var systemPrompt: String {
        didSet { Defaults.set(systemPrompt, for: .systemPrompt) }
    }

    /// Languages the user actually speaks. Sent to the model as a
    /// "expect any of these" hint, not a translation target. Free-form
    /// strings — anything the model recognizes works (e.g. "Traditional
    /// Chinese", "English", "Japanese", "Cantonese", "Spanish").
    var spokenLanguages: [String] {
        didSet { Defaults.set(spokenLanguages, for: .spokenLanguages) }
    }

    // MARK: Vocabulary
    var enabledVocabularyCategories: Set<VocabularyCategory> {
        didSet {
            Defaults.set(
                enabledVocabularyCategories.map(\.rawValue),
                for: .vocabularyEnabledCategories
            )
        }
    }
    var customVocabulary: [String] {
        didSet { Defaults.set(customVocabulary, for: .customVocabulary) }
    }

    // MARK: Output
    var restorePreviousClipboard: Bool {
        didSet { Defaults.set(restorePreviousClipboard, for: .restorePreviousClipboard) }
    }

    // MARK: Limits
    var softLimitMinutes: Int {
        didSet { Defaults.set(softLimitMinutes, for: .softLimitMinutes) }
    }
    var hardLimitMinutes: Int {
        didSet { Defaults.set(hardLimitMinutes, for: .hardLimitMinutes) }
    }

    // MARK: Init — load all values, falling back to defaults from spec §7.1
    private init() {
        self.launchAtLogin = Defaults.bool(for: .launchAtLogin) ?? false
        self.showInDock = Defaults.bool(for: .showInDock) ?? false
        self.showUsageInMenuBar = Defaults.bool(for: .showUsageInMenuBar) ?? true
        self.showMenuBarIcon = Defaults.bool(for: .showMenuBarIcon) ?? true

        self.hotkeyAMode = Defaults.string(for: .hotkeyAMode)
            .flatMap(HotkeyMode.init(rawValue:)) ?? .hold
        self.hotkeyBMode = Defaults.string(for: .hotkeyBMode)
            .flatMap(HotkeyMode.init(rawValue:)) ?? .hold

        // Default slot A binding: Fn (the globe / world key on modern Macs).
        // First-time installs get Fn; existing installs whose stored
        // version is below currentHotkeyDefaultsVersion AND who still
        // have the old Right-Option default get migrated to Fn. Anyone
        // who changed their binding manually keeps it.
        let storedHotkeyVersion = Defaults.int(for: .hotkeyDefaultsVersion) ?? 0
        let storedMaskA = Defaults.uint(for: .hotkeyAModifierMask)
        if storedHotkeyVersion < Self.currentHotkeyDefaultsVersion,
           storedMaskA == nil || storedMaskA == ModifierMask.rightOption {
            self.hotkeyAModifierMask = ModifierMask.fn
            Defaults.set(ModifierMask.fn, for: .hotkeyAModifierMask)
        } else {
            self.hotkeyAModifierMask = storedMaskA ?? ModifierMask.fn
        }
        Defaults.set(Self.currentHotkeyDefaultsVersion, for: .hotkeyDefaultsVersion)

        self.hotkeyBModifierMask = Defaults.uint(for: .hotkeyBModifierMask)

        self.inputDeviceUID = Defaults.string(for: .inputDeviceUID)

        self.transcriptionModel = Defaults.string(for: .transcriptionModel)
            .flatMap(TranscriptionModel.init(rawValue:)) ?? .gpt4oTranscribe
        self.streamingEnabled = Defaults.bool(for: .streamingEnabled) ?? false

        // The bundled prompt is the source of truth until the user edits it.
        // We tag releases with a monotonically increasing version; an existing
        // install with a stored prompt < currentBundledVersion gets a one-shot
        // refresh from the bundle so prompt fixes propagate to users without
        // forcing them to "Reset to default" by hand.
        let storedPromptVersion = Defaults.int(for: .bundledPromptVersion) ?? 0
        let resolvedPrompt: String
        if let stored = Defaults.string(for: .systemPrompt),
           storedPromptVersion >= Self.currentBundledPromptVersion {
            resolvedPrompt = stored
        } else {
            resolvedPrompt = Self.bundledDefaultPrompt()
            Defaults.set(resolvedPrompt, for: .systemPrompt)
            Defaults.set(Self.currentBundledPromptVersion, for: .bundledPromptVersion)
        }
        self.systemPrompt = resolvedPrompt

        let storedLangs = Defaults.stringArray(for: .spokenLanguages) ?? []
        self.spokenLanguages = storedLangs.isEmpty
            ? ["Traditional Chinese", "English"]
            : storedLangs

        let storedCats = (Defaults.stringArray(for: .vocabularyEnabledCategories) ?? [])
            .compactMap(VocabularyCategory.init(rawValue:))
        self.enabledVocabularyCategories = storedCats.isEmpty
            ? Set(VocabularyCategory.allCases)
            : Set(storedCats)
        self.customVocabulary = Defaults.stringArray(for: .customVocabulary) ?? []

        self.restorePreviousClipboard = Defaults.bool(for: .restorePreviousClipboard) ?? false

        self.softLimitMinutes = Defaults.int(for: .softLimitMinutes) ?? 2
        self.hardLimitMinutes = Defaults.int(for: .hardLimitMinutes) ?? 10
    }

    /// Loads `DefaultPrompt.md` from the app bundle. Falls back to a hard-coded
    /// string if the resource is missing (shouldn't happen in shipped builds).
    static func bundledDefaultPrompt() -> String {
        if let url = Bundle.main.url(forResource: "DefaultPrompt", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return """
        You are transcribing speech from a software engineer who frequently
        mixes Traditional Chinese (Taiwan) and English in the same sentence.
        Preserve English technical terms in English even when the surrounding
        text is in Chinese. Use Traditional Chinese characters (繁體中文),
        never Simplified. Output only the transcription, no commentary.
        """
    }
}

/// Bit masks for single-modifier hotkey discrimination. These are the
/// device-specific raw bits exposed via `NSEvent.modifierFlags.rawValue`,
/// distinct from the public `NSEvent.ModifierFlags` set which collapses
/// left/right.
enum ModifierMask {
    static let leftShift:    UInt = 0x0002
    static let rightShift:   UInt = 0x0004
    static let leftControl:  UInt = 0x0001
    static let rightControl: UInt = 0x2000
    static let leftOption:   UInt = 0x0020
    static let rightOption:  UInt = 0x0040
    static let leftCommand:  UInt = 0x0008
    static let rightCommand: UInt = 0x0010
    static let fn:           UInt = 0x800000
}
