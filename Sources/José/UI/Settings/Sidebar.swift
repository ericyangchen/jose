import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case hotkeys
    case audio
    case transcription
    case vocabulary
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .hotkeys: "Hotkeys"
        case .audio: "Audio"
        case .transcription: "Transcription"
        case .vocabulary: "Vocabulary"
        case .permissions: "Permissions"
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
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

// MARK: - Brand colors

private enum Brand {
    static let accent      = Color(red: 0x8B / 255.0, green: 0x7D / 255.0, blue: 1.0)  // #8B7DFF
    static let siriPink    = Color(red: 0.949, green: 0.659, blue: 0.769)
    static let siriPurple  = Color(red: 0.710, green: 0.659, blue: 0.910)
    static let siriBlue    = Color(red: 0.561, green: 0.737, blue: 0.910)
    static let siriCyan    = Color(red: 0.584, green: 0.863, blue: 0.875)

    static let siriGradient = LinearGradient(
        colors: [siriPink, siriPurple, siriBlue, siriCyan],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Sidebar

/// Sidebar with an app header at the top and a tight selection capsule
/// per row. We avoid `List(selection:)` + `.listStyle(.sidebar)` because
/// AppKit draws its own blue selection rectangle on a different frame
/// timing, producing a blue → purple flash.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            appHeader

            VStack(alignment: .leading, spacing: 1) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarRow(pane: pane, isSelected: pane == selection) {
                        selection = pane
                    }
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 200, alignment: .top)
    }

    private var appHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Brand.siriGradient)
                    .frame(width: 28, height: 28)
                HStack(spacing: 1.5) {
                    Capsule().fill(.white).frame(width: 2.5, height: 9)
                    Capsule().fill(.white).frame(width: 2.5, height: 13)
                    Capsule().fill(.white).frame(width: 2.5, height: 9)
                }
            }
            VStack(alignment: .leading, spacing: -1) {
                Text("José")
                    .font(.system(size: 14, weight: .semibold))
                Text("Hold and Say")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(iconColor)
                Text(pane.title)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // Hover transition is gentle — never compete with the selection
            // capsule for attention.
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private var iconColor: Color {
        if isSelected { return .white }
        return isHovered ? .primary : .secondary
    }

    private var textColor: Color {
        if isSelected { return .white }
        return .primary
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Brand.accent)
        } else if isHovered {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        } else {
            Color.clear
        }
    }
}

// MARK: - Card primitive

/// Modern card: thin material, no visible stroke, subtle shadow for
/// depth. Generous internal padding (28pt) and a small letter-spaced
/// section title in the secondary color set the rhythm — quieter than
/// the previous bordered look, lets the content breathe.
struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 1)
    }
}

// MARK: - Pane scaffold

/// Pane wrapper: large title at the top, optional subtitle, and a
/// 14pt-gap card stack inside a ScrollView. More vertical breath than
/// before so panes don't feel cramped.
struct PaneScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold, design: .default))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 36)
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Settings row

/// Labelled row inside a card. Vertical rhythm: 13pt label + optional
/// 11pt secondary description on the left, control on the right.
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
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13))
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
