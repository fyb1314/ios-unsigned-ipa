import Foundation
import SwiftUI

// MARK: - 云更新
//
// 工具箱自己也是通过 OTA 分发的，所以它可以在 App 内检查服务器上的新版、
// 直接弹窗提示、一键安装 —— 不用再回到电脑或 Safari。
//
// 版本比较只用 CFBundleVersion（build 号）：它是单调递增的整数，
// 比比较 "1.0.1" 这种字符串可靠得多。

struct UpdateInfo: Codable, Identifiable {
    let version: String
    let build: Int
    let bundle_id: String?
    let bundle_name: String?
    let size: Int
    let notes: String
    let published_at: String?
    let itms_url: String?
    let install_url: String?
    let id: String?

    var identity: String { id ?? "\(version)-\(build)" }
    // sheet(item:) 需要一个稳定的 id
    var displayId: String { identity }
}

struct UpdateCheck: Codable {
    struct Current: Codable { let version: String; let build: Int }
    let ok: Bool
    let has_update: Bool
    let current: Current?
    let latest: UpdateInfo?
    let checked_at: Int?
}

// sheet(item:) 要求元素 Identifiable，而 UpdateInfo 的 id 是可选的，
// 这里包一层给它一个必定存在的 id。
struct UpdateSheetItem: Identifiable {
    let id: String
    let info: UpdateInfo
}

final class UpdateCenter: ObservableObject {

    @Published private(set) var available: UpdateInfo?
    @Published private(set) var checking = false
    @Published private(set) var message: String?
    @Published var showSheet = false

    @AppStorage("update.skippedBuild") private var skippedBuild: Int = 0
    @AppStorage("update.lastCheck") private var lastCheckAt: Double = 0

    private let backend = Backend()

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1
    }

    /// 启动时静默检查（同一版本被跳过过就不再打扰；6 小时内不重复联网）
    func checkOnLaunch() async {
        let now = Date().timeIntervalSince1970
        guard now - lastCheckAt > 6 * 3600 else { return }
        await check(force: false)
    }

    /// 手动检查：忽略「已跳过」和节流
    func check(force: Bool) async {
        guard !checking else { return }
        await MainActor.run { checking = true; message = nil }

        do {
            let r = try await backend.checkUpdate(version: Self.currentVersion,
                                                  build: Self.currentBuild)
            await MainActor.run {
                checking = false
                lastCheckAt = Date().timeIntervalSince1970
                if r.has_update, let latest = r.latest {
                    available = latest
                    if force || latest.build > skippedBuild {
                        showSheet = true
                    } else {
                        message = "已是最新版（\(Self.currentVersion) · build \(Self.currentBuild)）"
                    }
                } else {
                    available = nil
                    message = "已是最新版（\(Self.currentVersion) · build \(Self.currentBuild)）"
                }
            }
        } catch {
            await MainActor.run {
                checking = false
                message = "检查更新失败：" + error.localizedDescription
            }
        }
    }

    func skip() {
        if let b = available?.build { skippedBuild = b }
        showSheet = false
    }

    func install() {
        guard let u = available?.itms_url, let url = URL(string: u) else { return }
        showSheet = false
        UIApplication.shared.open(url)
    }

    var currentText: String {
        "\(Self.currentVersion)（build \(Self.currentBuild)）"
    }
}

// MARK: - 更新提示弹层

struct UpdateSheet: View {
    @ObservedObject var center: UpdateCenter
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.gap) {
                    if let info = center.available {
                        header(info)
                        notes(info)
                        actions
                    }
                }
                .padding(Metrics.paddingCard)
                .padding(.vertical, 12)
            }
            .background(PageBackground())
            .navigationTitle("发现新版本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("以后再说") { center.skip() }
                }
            }
        }
    }

    private func header(_ info: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(icon: "arrow.up.circle", title: "版本 \(info.version)",
                      subtitle: "build \(info.build) · \(info.published_at ?? "")")
            InfoLine(label: "当前版本", value: center.currentText)
            InfoLine(label: "新版本", value: "\(info.version)（build \(info.build)）")
            InfoLine(label: "大小", value: ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file))
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    private func notes(_ info: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(icon: "text.badge.star", title: "更新内容")
            if info.notes.isEmpty {
                Text("（本次没有填写更新说明）")
                    .font(.system(size: 13)).foregroundColor(.secondary)
            } else {
                Text(info.notes)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton("立即更新", icon: "arrow.down.app") { center.install() }
            SecondaryButton("跳过这个版本", icon: "xmark") { center.skip() }
            Text("更新会跳转到系统安装界面，安装过程中请不要锁屏。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
