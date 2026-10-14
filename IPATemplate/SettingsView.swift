import SwiftUI

// MARK: - 设置页
// 服务器配置 / 根证书安装 / UDID 登记 / 缓存清理 / 连接自检

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updateCenter: UpdateCenter
    @Environment(\.colorScheme) private var scheme

    @State private var state: ServerState?
    @State private var testing = false
    @State private var testResult: TestResult?
    @State private var showCopied = false
    @State private var alert: AlertItem?

    private let backend = Backend()

    struct TestResult {
        let ok: Bool
        let text: String
    }

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    stepsCard
                    serverCard
                    deviceCard
                    aboutCard
                }
                .padding(.horizontal, Metrics.paddingCard)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("好")))
        }
    }

    // MARK: 首次使用三步

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(icon: "list.number", title: "首次使用两步",
                      subtitle: "服务器已启用公开可信证书，无需安装根证书")
            StepRow(index: "1", title: "登记本机 UDID",
                    detail: "安装 UDID 描述文件，设备会自动把真实 UDID 报给服务器。App 自身读不到 UDID，必须走这一步。")
            StepRow(index: "2", title: "登录 Apple ID 开始签名",
                    detail: "建议用一个不绑卡、无余额的专用免费 Apple ID。")
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    // MARK: 服务器

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(icon: "server.rack", title: "服务器",
                      subtitle: state == nil ? "未连接" : "已连接 · zsign \(state?.zsign == true ? "就绪" : "缺失")")
            LabeledField(title: "服务地址", text: Binding(
                get: { settings.base },
                set: { settings.base = $0 }), placeholder: "https://host/idsign")
            LabeledField(title: "签名令牌", text: Binding(
                get: { settings.idToken },
                set: { settings.idToken = $0 }), placeholder: "pia-id-…")
            LabeledField(title: "OTA 令牌", text: Binding(
                get: { settings.otaToken },
                set: { settings.otaToken = $0 }), placeholder: "pia-ota-…")

            PrimaryButton(testing ? "测试中…" : "测试连接", icon: "bolt.horizontal",
                          isLoading: testing) { Task { await test() } }

            if let t = testResult {
                HStack(spacing: 8) {
                    Image(systemName: t.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(t.ok ? Palette.ok : Palette.danger)
                    Text(t.text)
                        .font(.system(size: 12))
                        .foregroundColor(t.ok ? .secondary : Palette.danger)
                    Spacer()
                }
            }
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    // MARK: 设备

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(icon: "iphone", title: "本机",
                      subtitle: "登记 UDID 后服务端才能给你发描述文件")

            // 地址跟随「服务地址」设置，不要写死——服务器换了域名时这里不用改。
            SecondaryButton("登记本机 UDID（Safari）", icon: "number") {
                open(URL(string: settings.baseURL + "/udid.mobileconfig"))
            }

            if let us = state?.udids, !us.isEmpty {
                Divider().padding(.vertical, 2)
                Text("服务器已登记的 UDID（\(us.count)）")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(us) { u in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(u.udid)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Text("\(u.product) · iOS \(u.version)")
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button { copy(u.udid) } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 12))
                        }
                    }
                }
            } else {
                Text("还没有登记任何 UDID")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
        .overlay(alignment: .bottom) {
            if showCopied {
                Text("已复制")
                    .font(.caption).padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: showCopied)
    }

    // MARK: 关于

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(icon: "info.circle", title: "关于")
            Text("偶尔的PIA工具 · 手机端\nApple ID 签与证书签都由你自己的服务器完成；IPA 会上传到该服务器用于签名与生成安装链接。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            InfoLine(label: "版本", value: updateCenter.currentText)
            InfoLine(label: "服务器", value: settings.baseURL)

            PrimaryButton(updateCenter.checking ? "检查中…" : "检查更新",
                          icon: "arrow.triangle.2.circlepath",
                          isLoading: updateCenter.checking) {
                Task { await updateCenter.check(force: true) }
            }

            if let m = updateCenter.message {
                HStack(spacing: 8) {
                    Image(systemName: updateCenter.available == nil
                          ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .foregroundColor(updateCenter.available == nil ? Palette.ok : Palette.brandBottom)
                    Text(m)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            Text("每次启动会静默检查一次；发现新版本会自动弹窗，也可以在这里手动查。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    // MARK: 逻辑

    private func refresh() async {
        do { state = try await backend.state() } catch { state = nil }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let s = try await backend.state()
            await MainActor.run {
                state = s
                testResult = TestResult(
                    ok: true,
                    text: "连接正常 · zsign \(s.zsign ? "就绪" : "缺失") · 已登记 \(s.udids.count) 台设备")
            }
        } catch {
            await MainActor.run {
                testResult = TestResult(ok: false, text: error.localizedDescription)
            }
        }
    }

    private func open(_ url: URL?) {
        guard let u = url else { return }
        UIApplication.shared.open(u)
    }

    private func copy(_ s: String) {
        UIPasteboard.general.string = s
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { showCopied = false }
    }
}

// MARK: - 小组件

struct StepRow: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(brandGradient)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .font(.system(size: 13, design: .monospaced))
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
