import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case hotkeys
    case audio
    case transcription
    case vocabulary
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .hotkeys: "Hotkeys"
        case .audio: "Audio"
        case .transcription: "Transcription"
        case .vocabulary: "Vocabulary"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .hotkeys: "keyboard"
        case .audio: "mic"
        case .transcription: "waveform"
        case .vocabulary: "text.book.closed"
        case .about: "info.circle"
        }
    }
}

/// 180pt sidebar. Selection highlight is `accent-primary` (#8B7DFF) per
/// spec §4.7. We avoid `List(selection:)` because `.listStyle(.sidebar)`
/// draws the system blue selection rectangle under our custom capsule on
/// a separate frame, producing a blue → purple flash + perceived lag.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { pane in
                SidebarRow(pane: pane, isSelected: pane == selection) {
                    selection = pane
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: 180, alignment: .top)
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: pane.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .white : .secondary)
                Text(pane.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(red: 0x8B / 255.0, green: 0x7D / 255.0, blue: 1.0) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card primitive (shared by all panes)

/// Card style per spec §4.7: 12pt corner radius, regular material, 1pt
/// secondary border, 24pt internal padding. 16pt vertical gap is enforced
/// by the `PaneScaffold` VStack spacing.
struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Standard pane scaffold: title header + 16pt-gap card stack inside a
/// `ScrollView`, with 32pt content padding per spec §4.7.
struct PaneScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.bottom, 4)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
    }
}

/// One labelled row inside a card: left description column, right control.
struct SettingsRow<Control: View>: View {
    let label: String
    let description: String?
    @ViewBuilder var control: () -> Control

    init(_ label: String, description: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.description = description
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
