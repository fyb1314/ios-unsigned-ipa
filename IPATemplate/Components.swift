import SwiftUI
import UniformTypeIdentifiers

// MARK: - 卡片标题

struct CardTitle: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(brandGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - 按钮

struct PrimaryButton: View {
    let title: String
    let icon: String?
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    init(_ title: String, icon: String? = nil, isLoading: Bool = false,
         isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Group {
                    if isDisabled {
                        Color.gray.opacity(0.35)
                    } else {
                        brandGradient
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
        }
        .disabled(isDisabled || isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    let icon: String
    var isDisabled: Bool = false
    let action: () -> Void

    // 必须显式写 init：不写的话 Swift 只给 memberwise init(title:icon:...)，
    // 调用处写 SecondaryButton("文字", icon: "xmark") 会编译不过
    // （error: missing argument label 'title:' in call）。
    // 这个坑本地静态检查抓不到，是 CI 编出来的。
    init(_ title: String, icon: String, isDisabled: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isDisabled ? .secondary : .accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color.accentColor.opacity(isDisabled ? 0.06 : 0.12))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
        }
        .disabled(isDisabled)
    }
}

// MARK: - 状态徽章

enum PillState {
    case idle, ok, warn, danger, busy

    var color: Color {
        switch self {
        case .idle: return Palette.idle
        case .ok: return Palette.ok
        case .warn: return Palette.warn
        case .danger: return Palette.danger
        case .busy: return Palette.brandTop
        }
    }

    var icon: String {
        switch self {
        case .idle: return "circle.dashed"
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .danger: return "xmark.circle.fill"
        case .busy: return "arrow.triangle.2.circlepath"
        }
    }
}

struct StatusPill: View {
    let text: String
    let state: PillState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(state.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(state.color.opacity(0.13))
        .clipShape(Capsule())
    }
}

// MARK: - 键值行

struct InfoLine: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 文件选择行

struct FileRow: View {
    let icon: String
    let title: String
    let hint: String
    var fileName: String?
    var state: PillState = .idle
    var stateText: String = "未选择"
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(state == .ok ? Palette.ok : Palette.brandTop)
                    .frame(width: 34, height: 34)
                    .background(
                        (state == .ok ? Palette.ok : Palette.brandTop).opacity(0.13)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    Text(fileName ?? hint)
                        .font(.system(size: 12))
                        .foregroundColor(fileName == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                StatusPill(text: fileName == nil ? stateText : "已就绪", state: fileName == nil ? state : .ok)
            }
            .padding(12)
            .background(Palette.cardBackground(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .stroke(Palette.stroke(scheme), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 日志控制台

struct LogConsole: View {
    let lines: [LogLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(line.timeText)
                                    .foregroundColor(.secondary)
                                Text(line.message)
                                    .foregroundColor(line.level.color)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 150)
                .onChange(of: lines.count) { _ in
                    if let last = lines.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
    }
}

// MARK: - 空状态

struct EmptyHint: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(.secondary.opacity(0.6))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - 文档选择器

struct DocumentPicker: UIViewControllerRepresentable {
    let extensions: [String]
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = extensions.compactMap { UTType(filenameExtension: $0) }
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: types.isEmpty ? [.data] : types,
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
