import Foundation

/// Builds the prompt string fed to OpenAI's `/v1/audio/transcriptions` endpoint.
///
/// Composition (spec §6.4.2 / §5.7):
///
/// ```
/// {settings.systemPrompt}
///
/// Common technical terms in this user's vocabulary:
/// {comma-separated list of enabled default terms ∪ custom terms}
/// ```
///
/// The default term list is bundled as `DefaultVocabulary.yaml` and parsed
/// once on first access. Categories disabled in Settings are dropped before
/// composition. The whole prompt is capped at ~3000 characters because the
/// Whisper / GPT-4o-transcribe prompt has a token budget — when we go over,
/// we drop default categories in priority order (lowest priority first):
///
///     general_dev → ai_ml → protocols_apis → databases →
///     infrastructure → languages_frameworks
///
/// Custom vocabulary is preserved as long as possible.
enum PromptBuilder {

    /// Soft cap on prompt length, in characters. Whisper-family models accept
    /// ~244 tokens of prompt; 3k chars leaves headroom for CJK (which is more
    /// expensive per token) without truncating typical configurations.
    static let maxPromptCharacters = 3000

    /// Order in which default vocabulary categories are dropped when the
    /// composed prompt exceeds `maxPromptCharacters`. First element is the
    /// first to go.
    static let dropPriority: [VocabularyCategory] = [
        .generalDev,
        .aiMl,
        .protocolsApis,
        .databases,
        .infrastructure,
        .languagesFrameworks
    ]

    @MainActor
    static func build(from settings: Settings) -> String {
        let systemPrompt = settings.systemPrompt
        let custom = settings.customVocabulary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Start with all enabled categories; drop them one at a time until
        // we fit within the cap (or run out of categories).
        var enabledCategories = VocabularyCategory.allCases
            .filter { settings.enabledVocabularyCategories.contains($0) }

        let defaults = DefaultVocabulary.shared

        var prompt = compose(
            systemPrompt: systemPrompt,
            categories: enabledCategories,
            defaults: defaults,
            custom: custom
        )

        for category in dropPriority {
            if prompt.count <= maxPromptCharacters { break }
            if let idx = enabledCategories.firstIndex(of: category) {
                enabledCategories.remove(at: idx)
                prompt = compose(
                    systemPrompt: systemPrompt,
                    categories: enabledCategories,
                    defaults: defaults,
                    custom: custom
                )
            }
        }

        // If we are *still* over budget after dropping every default category,
        // truncate the custom-vocabulary tail. The system prompt itself is
        // never truncated — that would silently change model behavior.
        if prompt.count > maxPromptCharacters {
            prompt = truncatingCustom(
                systemPrompt: systemPrompt,
                custom: custom
            )
        }

        return prompt
    }

    // MARK: - Composition

    private static func compose(
        systemPrompt: String,
        categories: [VocabularyCategory],
        defaults: DefaultVocabulary,
        custom: [String]
    ) -> String {
        var terms: [String] = []
        for category in categories {
            terms.append(contentsOf: defaults.terms(for: category))
        }
        terms.append(contentsOf: custom)
        terms = dedupePreservingOrder(terms)

        guard !terms.isEmpty else { return systemPrompt }

        return systemPrompt
            + "\n\nCommon technical terms in this user's vocabulary:\n"
            + terms.joined(separator: ", ")
    }

    /// Last-resort fallback when even an all-categories-dropped prompt is over
    /// budget (i.e., the user's custom list alone is huge). Trims terms from
    /// the end until we fit.
    private static func truncatingCustom(
        systemPrompt: String,
        custom: [String]
    ) -> String {
        let header = "\n\nCommon technical terms in this user's vocabulary:\n"
        var terms = custom
        while !terms.isEmpty {
            let candidate = systemPrompt + header + terms.joined(separator: ", ")
            if candidate.count <= maxPromptCharacters { return candidate }
            terms.removeLast()
        }
        return systemPrompt
    }

    private static func dedupePreservingOrder(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(terms.count)
        for term in terms where seen.insert(term.lowercased()).inserted {
            out.append(term)
        }
        return out
    }
}

// MARK: - DefaultVocabulary

/// Loads `DefaultVocabulary.yaml` from the app bundle once and exposes the
/// parsed `[category: [term]]` map. If the resource cannot be loaded or the
/// YAML cannot be parsed, falls back to a hard-coded copy of the canonical
/// list (spec §6.4.4) so the app stays useful in degraded build configurations.
final class DefaultVocabulary {
    static let shared = DefaultVocabulary()

    private let storage: [String: [String]]

    private init() {
        if let url = Bundle.main.url(
            forResource: "DefaultVocabulary",
            withExtension: "yaml"
        ),
           let yaml = try? String(contentsOf: url, encoding: .utf8),
           let parsed = Self.parse(yaml: yaml),
           !parsed.isEmpty {
            self.storage = parsed
        } else {
            Logger.transcription.warning(
                "DefaultVocabulary.yaml missing or unparseable — using built-in fallback"
            )
            self.storage = Self.fallback
        }
    }

    func terms(for category: VocabularyCategory) -> [String] {
        storage[category.rawValue] ?? []
    }

    // MARK: - Tiny YAML parser
    //
    // The bundled file is a strict subset of YAML: top-level keys map to
    // sequences of bare scalars (no quoting, no nested maps, no flow style).
    // Pulling in a real YAML library for ~30 lines of grammar is overkill.

    static func parse(yaml: String) -> [String: [String]]? {
        var result: [String: [String]] = [:]
        var currentKey: String?

        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            // Strip comments (everything after a `#` not inside a value — we
            // don't support quoted `#` here, the bundled file doesn't need it).
            let line: Substring
            if let hash = rawLine.firstIndex(of: "#") {
                line = rawLine[..<hash]
            } else {
                line = rawLine
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if line.first == "-" || line.first == " " || line.first == "\t" {
                // List item under the current key.
                guard let key = currentKey else { continue }
                let item = trimmed
                    .drop(while: { $0 == "-" })
                    .trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    result[key, default: []].append(String(item))
                }
            } else if let colon = trimmed.firstIndex(of: ":") {
                // Top-level `key:` line.
                let key = String(trimmed[..<colon])
                    .trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { continue }
                currentKey = key
                if result[key] == nil { result[key] = [] }
            }
        }

        return result.isEmpty ? nil : result
    }

    /// Hard-coded mirror of `Resources/DefaultVocabulary.yaml`. Used only when
    /// the bundled resource cannot be loaded (e.g., misconfigured target).
    private static let fallback: [String: [String]] = [
        "languages_frameworks": [
            "TypeScript", "JavaScript", "Python", "Rust", "Go", "Swift",
            "Kotlin", "Java", "Ruby", "React", "Vue", "Svelte", "Next.js",
            "Nuxt", "SwiftUI", "AppKit", "NestJS", "Express", "FastAPI",
            "Django", "Flask", "Rails", "Spring", "Tailwind", "shadcn"
        ],
        "infrastructure": [
            "Kubernetes", "Docker", "Terraform", "Helm", "nginx", "Caddy",
            "AWS", "GCP", "Azure", "Cloudflare", "Vercel", "Fly.io",
            "CI/CD", "GitHub Actions", "GitLab CI"
        ],
        "databases": [
            "Postgres", "MySQL", "SQLite", "MongoDB", "Redis", "Elasticsearch",
            "DynamoDB", "Cassandra", "ClickHouse",
            "TypeORM", "Prisma", "Drizzle", "SQLAlchemy"
        ],
        "protocols_apis": [
            "REST", "GraphQL", "gRPC", "WebSocket", "Webhook",
            "OAuth", "JWT", "SAML"
        ],
        "ai_ml": [
            "LLM", "GPT", "Claude", "transformer", "embedding",
            "RAG", "vector database", "fine-tuning", "inference",
            "PyTorch", "TensorFlow", "JAX", "Hugging Face"
        ],
        "general_dev": [
            "microservices", "monorepo", "serverless", "edge function",
            "CRUD", "RBAC", "MFA", "SSO", "idempotent", "eventual consistency",
            "PR", "MR", "diff", "rebase", "squash", "cherry-pick"
        ]
    ]
}
