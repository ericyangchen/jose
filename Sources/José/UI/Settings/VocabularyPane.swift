import SwiftUI

struct VocabularyPane: View {
    @Bindable var settings: Settings
    @State private var newTerm: String = ""

    var body: some View {
        PaneScaffold(title: "Vocabulary", subtitle: "Technical terms José tells the model to expect.") {
            categoriesCard
            customCard
            statsCard
        }
    }

    private var categoriesCard: some View {
        SettingsCard("Default Categories") {
            Text("Toggle which dev-friendly term packs to inject into every transcription prompt.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(VocabularyCategory.allCases, id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { settings.enabledVocabularyCategories.contains(category) },
                        set: { isOn in
                            var set = settings.enabledVocabularyCategories
                            if isOn { set.insert(category) } else { set.remove(category) }
                            settings.enabledVocabularyCategories = set
                        }
                    )) {
                        Text(category.displayName)
                            .font(.system(size: 13))
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var customCard: some View {
        SettingsCard("Custom Terms") {
            HStack {
                TextField("Add a term…", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTerm)
                Button("Add") { addTerm() }
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if settings.customVocabulary.isEmpty {
                Text("No custom terms yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(settings.customVocabulary, id: \.self) { term in
                            HStack {
                                Text(term)
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Button {
                                    settings.customVocabulary.removeAll { $0 == term }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private var statsCard: some View {
        SettingsCard("Prompt Length") {
            let chars = estimatedPromptLength
            let tokens = chars / 4
            HStack(spacing: 24) {
                stat(label: "Characters", value: "\(chars)")
                stat(label: "Estimated tokens", value: "~\(tokens)")
                Spacer()
            }
            Text("Long prompts can dilute transcription accuracy. Aim for under 1,500 tokens.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !settings.customVocabulary.contains(trimmed) {
            settings.customVocabulary.append(trimmed)
        }
        newTerm = ""
    }

    private var estimatedPromptLength: Int {
        var total = settings.systemPrompt.count
        for cat in settings.enabledVocabularyCategories {
            total += defaultTerms(for: cat).joined(separator: ", ").count + 2
        }
        if !settings.customVocabulary.isEmpty {
            total += settings.customVocabulary.joined(separator: ", ").count + 2
        }
        return total
    }

    private func defaultTerms(for category: VocabularyCategory) -> [String] {
        switch category {
        case .languagesFrameworks:
            ["TypeScript", "JavaScript", "Python", "Rust", "Go", "Swift", "Kotlin", "Java", "Ruby",
             "React", "Vue", "Svelte", "Next.js", "Nuxt", "SwiftUI", "AppKit",
             "NestJS", "Express", "FastAPI", "Django", "Flask", "Rails", "Spring",
             "Tailwind", "shadcn"]
        case .infrastructure:
            ["Kubernetes", "Docker", "Terraform", "Helm", "nginx", "Caddy",
             "AWS", "GCP", "Azure", "Cloudflare", "Vercel", "Fly.io",
             "CI/CD", "GitHub Actions", "GitLab CI"]
        case .databases:
            ["Postgres", "MySQL", "SQLite", "MongoDB", "Redis", "Elasticsearch",
             "DynamoDB", "Cassandra", "ClickHouse",
             "TypeORM", "Prisma", "Drizzle", "SQLAlchemy"]
        case .protocolsApis:
            ["REST", "GraphQL", "gRPC", "WebSocket", "Webhook", "OAuth", "JWT", "SAML"]
        case .aiMl:
            ["LLM", "GPT", "Claude", "transformer", "embedding",
             "RAG", "vector database", "fine-tuning", "inference",
             "PyTorch", "TensorFlow", "JAX", "Hugging Face"]
        case .generalDev:
            ["microservices", "monorepo", "serverless", "edge function",
             "CRUD", "RBAC", "MFA", "SSO", "idempotent", "eventual consistency",
             "PR", "MR", "diff", "rebase", "squash", "cherry-pick"]
        }
    }
}
