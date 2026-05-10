import Foundation

/// Local usage estimation. Tracks seconds of audio per (month, model) and
/// translates to a dollar estimate using the public OpenAI rates encoded
/// on `TranscriptionModel`. No telemetry leaves the device.
@MainActor
final class UsageTracker {
    static let shared = UsageTracker()

    private(set) var secondsThisMonth: [TranscriptionModel: Double] = [:]
    private var monthBucket: String = ""

    private init() {
        loadFromDefaults()
    }

    var monthlyMinutes: Double {
        secondsThisMonth.values.reduce(0, +) / 60.0
    }

    var estimatedMonthlyCost: Double {
        secondsThisMonth.reduce(0.0) { acc, entry in
            acc + (entry.value / 60.0) * entry.key.costPerMinute
        }
    }

    func record(durationSeconds: Double, model: TranscriptionModel) {
        rolloverIfNeeded()
        secondsThisMonth[model, default: 0] += max(0, durationSeconds)
        persist()
    }

    private func rolloverIfNeeded() {
        let current = Self.currentMonthBucket()
        if monthBucket != current {
            secondsThisMonth = [:]
            monthBucket = current
            persist()
        }
    }

    private static func currentMonthBucket() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = .current
        return f.string(from: Date())
    }

    private func loadFromDefaults() {
        monthBucket = Defaults.string(for: .usageMonthBucket) ?? Self.currentMonthBucket()
        if let raw = Defaults.dictionary(for: .usageSecondsByModel) {
            for (key, value) in raw {
                if let model = TranscriptionModel(rawValue: key),
                   let seconds = value as? Double {
                    secondsThisMonth[model] = seconds
                }
            }
        }
        rolloverIfNeeded()
    }

    private func persist() {
        Defaults.set(monthBucket, for: .usageMonthBucket)
        let raw: [String: Any] = secondsThisMonth.reduce(into: [:]) { dict, entry in
            dict[entry.key.rawValue] = entry.value
        }
        Defaults.set(raw, for: .usageSecondsByModel)
    }
}
