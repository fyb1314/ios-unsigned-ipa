import SwiftUI
import UniformTypeIdentifiers

// MARK: - 签名页
//
// 两种模式：
//   • Apple ID 签（ID 签）：账号 + 密码 + 二次验证 → 服务器现场向 Apple 申请
//     7 天免费证书与含本机 UDID 的描述文件 → zsign 重签 → OTA 安装。
//   • 证书签：用户自带 p12 + mobileprovision，服务器直接用 zsign 重签。

enum SignMode: String, CaseIterable, Identifiable {
    case appleID = "Apple ID 签"
    case cert = "证书签"
    var id: String { rawValue }
}

struct SignView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var scheme

    @State private var mode: SignMode = .appleID

    // 文件
    @State private var ipaURL: URL?
    @State private var ipaName: String?
    @State private var p12URL: URL?
    @State private var p12Name: String?
    @State private var provURL: URL?
    @State private var provName: String?

    // Apple ID
    @State private var appleId = ""
    @State private var password = ""
    @State private var loggedIn = false
    @State private var teamName = ""
    @State private var verifying = false
    @State private var twoFAModes: [TwoFactorMode] = []
    @State private var twoFAIndex = 0
    @State private var code = ""
    @State private var show2FA = false

    // 证书签
    @State private var p12Password = ""

    // 运行状态
    @State private var busy = false
    @State private var busyText = ""
    @State private var progress: Double = 0
    @State private var logs: [LogLine] = []
    @State private var result: SignResult?
    @State private var alert: AlertItem?
    @State private var showPicker: PickerTarget?

    @State private var ipaInfo: IpaInfo?
    @State private var knownUDIDs: [ServerState.UdidRow] = []

    private let backend = Backend()

    enum PickerTarget: Identifiable {
        case ipa, p12, prov, inspect
        var id: Int { hashValue }
        var extensions: [String] {
            switch self {
            case .ipa: return ["ipa"]
            case .p12: return ["p12", "pfx"]
            case .prov: return ["mobileprovision"]
            case .inspect: return ["ipa", "mobileprovision", "p12", "pfx"]
            }
        }
    }

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    modePicker
                    if mode == .appleID { appleIDSection } else { certSection }
                    actionSection
                    if !logs.isEmpty { logSection }
                    if let r = result { resultSection(r) }
                }
                .padding(.horizontal, Metrics.paddingCard)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("签名")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showPicker) { target in
            DocumentPicker(extensions: target.extensions) { url in
                handlePicked(url, target: target)
            }
        }
        .sheet(isPresented: $show2FA) { twoFASheet }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("好")))
        }
        .task { await refresh() }
    }

    // MARK: 模式切换

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(icon: "signature", title: "签名方式",
                      subtitle: mode == .appleID
                        ? "用你自己的 Apple ID 现场申请免费证书（7 天有效）"
                        : "用你导入的 p12 证书与描述文件签名")
            HStack(spacing: 8) {
                ForEach(SignMode.allCases) { m in
                    Button { mode = m } label: {
                        Text(m.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(mode == m ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                Group {
                                    if mode == m { brandGradient }
                                    else { Color.primary.opacity(scheme == .dark ? 0.10 : 0.06) }
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    // MARK: Apple ID 签

    private var appleIDSection: some View {
        VStack(spacing: Metrics.gap) {
            // 文件
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(icon: "app.badge.checkmark", title: "待签名的 IPA")
                FileRow(icon: "doc.zipper", title: "IPA 文件", hint: "从「文件」中选择 .ipa",
                        fileName: ipaName, action: { showPicker = .ipa })
                if let info = ipaInfo { ipaMetaBlock(info) }
            }
            .padding(Metrics.paddingCard)
            .glassCard(scheme)

            // 账号
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(icon: "person.badge.key", title: "Apple ID",
                          subtitle: loggedIn ? ("已登录" + (teamName.isEmpty ? "" : " · " + teamName))
                                             : "只用于向 Apple 申请免费证书，请用一个不绑卡的专用账号")
                if loggedIn {
                    HStack {
                        StatusPill(text: appleId, state: .ok)
                        Spacer()
                        Button("退出") { Task { await logout() } }
                            .font(.system(size: 13))
                    }
                } else {
                    TextField("Apple ID（邮箱）", text: $appleId)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .padding(12)
                        .background(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05))
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl))
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                        .padding(12)
                        .background(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05))
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl))
                    PrimaryButton(verifying ? "登录中…" : "登录并申请证书",
                                  icon: "key.horizontal",
                                  isLoading: verifying,
                                  isDisabled: appleId.isEmpty || password.isEmpty) {
                        Task { await doLogin() }
                    }
                }

                if knownUDIDs.isEmpty {
                    udidHint
                } else if let u = knownUDIDs.last {
                    InfoLine(label: "本机 UDID", value: String(u.udid.prefix(20)) + "…", mono: true)
                    InfoLine(label: "设备", value: "\(u.product) · iOS \(u.version)")
                }
            }
            .padding(Metrics.paddingCard)
            .glassCard(scheme)
        }
    }

    private var udidHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Palette.warn)
                Text("还没有登记本机 UDID。Apple 免费证书必须包含设备 UDID，请先到「设置」页安装 UDID 描述文件。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Palette.warn.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl))
    }

    private func ipaMetaBlock(_ info: IpaInfo) -> some View {
        VStack(spacing: 4) {
            InfoLine(label: "Bundle ID", value: info.bundleId, mono: true)
            InfoLine(label: "名称", value: info.displayName)
            InfoLine(label: "版本", value: "\(info.version) (\(info.build))")
            InfoLine(label: "大小", value: ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file))
        }
        .padding(12)
        .background(Color.primary.opacity(scheme == .dark ? 0.05 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl))
    }

    // MARK: 证书签

    private var certSection: some View {
        VStack(spacing: Metrics.gap) {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(icon: "doc.badge.gearshape", title: "待签名的 IPA")
                FileRow(icon: "doc.zipper", title: "IPA 文件", hint: "选择 .ipa",
                        fileName: ipaName, action: { showPicker = .ipa })
                if let info = ipaInfo { ipaMetaBlock(info) }
            }
            .padding(Metrics.paddingCard)
            .glassCard(scheme)

            VStack(alignment: .leading, spacing: 10) {
                CardTitle(icon: "key.fill", title: "签名材料", subtitle: "p12 证书 + 描述文件")
                FileRow(icon: "lock.doc", title: "p12 证书", hint: "选择 .p12 / .pfx",
                        fileName: p12Name, action: { showPicker = .p12 })
                FileRow(icon: "doc.text", title: "描述文件", hint: "选择 .mobileprovision",
                        fileName: provName, action: { showPicker = .prov })
                SecureField("证书密码（可为空）", text: $p12Password)
                    .padding(12)
                    .background(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05))
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl))
            }
            .padding(Metrics.paddingCard)
            .glassCard(scheme)
        }
    }

    // MARK: 执行

    private var actionSection: some View {
        VStack(spacing: 10) {
            PrimaryButton(busy ? busyText : "开始签名并上传",
                          icon: "wand.and.rays",
                          isLoading: busy,
                          isDisabled: !canSign) {
                Task { await doSign() }
            }
            if busy && progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
            }
        }
    }

    private var canSign: Bool {
        guard !busy, ipaURL != nil else { return false }
        return mode == .cert ? (p12URL != nil && provURL != nil) : loggedIn
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(icon: "terminal", title: "运行日志")
            LogConsole(lines: logs)
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    private func resultSection(_ r: SignResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(icon: "checkmark.seal", title: "签名完成",
                      subtitle: "\(r.bundleName) \(r.version) · \(ByteCountFormatter.string(fromByteCount: r.size, countStyle: .file))")
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(Palette.ok)
                Text(r.bundleId).font(.system(size: 12, design: .monospaced))
                Spacer()
            }
            PrimaryButton("安装到本机", icon: "arrow.down.app") { install(r) }
            SecondaryButton("在 Safari 打开安装页", icon: "safari") {
                if let u = URL(string: r.installURL) { UIApplication.shared.open(u) }
            }
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    // MARK: 二次验证

    private var twoFASheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("请输入验证码")
                    .font(.headline)
                Text(twoFAModes.indices.contains(twoFAIndex)
                     ? twoFAModes[twoFAIndex].label
                     : "输入设备上显示的 6 位验证码")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .padding()
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if twoFAModes.count > 1 {
                    Picker("验证方式", selection: $twoFAIndex) {
                        ForEach(Array(twoFAModes.enumerated()), id: \.offset) { i, m in
                            Text(m.type == "sms" ? "短信验证码" : "设备验证码").tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                PrimaryButton("验证并继续", icon: "checkmark.shield", isLoading: verifying,
                              isDisabled: code.count < 4) {
                    Task { await doVerify() }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("二次验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { show2FA = false }
                }
            }
        }
    }

    // MARK: 逻辑

    private func handlePicked(_ url: URL, target: PickerTarget) {
        switch target {
        case .ipa:
            ipaURL = url
            ipaName = url.lastPathComponent
            if let info = try? Inspector.inspectIPA(url) { ipaInfo = info }
            result = nil
            addLog("已选择 \(url.lastPathComponent)")
        case .p12:
            p12URL = url; p12Name = url.lastPathComponent
        case .prov:
            provURL = url; provName = url.lastPathComponent
        case .inspect:
            break
        }
    }

    private func addLog(_ msg: String, level: LogLevel = .info) {
        DispatchQueue.main.async { logs.append(LogLine(message: msg, level: level)) }
    }

    private func refresh() async {
        do {
            let st = try await backend.state()
            await MainActor.run {
                knownUDIDs = st.udids
                loggedIn = st.session.logged_in
                teamName = st.session.team_name ?? ""
                if !st.session.appleid.isNilOrEmpty { appleId = st.session.appleid ?? "" }
            }
        } catch {
            await MainActor.run {
                knownUDIDs = []
            }
        }
    }

    private func doLogin() async {
        verifying = true
        addLog("开始登录 \(appleId)…")
        do {
            let r = try await backend.loginStart(appleId: appleId, password: password)
            await MainActor.run {
                verifying = false
                if r["status"] as? String == "2fa", let modes = r["modes"] as? [[String: Any]] {
                    var parsed: [TwoFactorMode] = []
                    for (i, m) in modes.enumerated() {
                        parsed.append(TwoFactorMode(
                            type: (m["type"] as? String) ?? "trusted_device",
                            index: (m["index"] as? Int) ?? (i + 1),
                            label: (m["label"] as? String) ?? "输入验证码"))
                    }
                    twoFAModes = parsed
                    twoFAIndex = 0
                    show2FA = true
                    addLog("需要二次验证", level: .warn)
                } else {
                    loggedIn = true
                    password = ""
                    addLog("登录成功")
                    Task { await refresh() }
                }
            }
        } catch {
            await MainActor.run {
                verifying = false
                addLog("登录失败：\(error.localizedDescription)", level: .error)
                alert = AlertItem(title: "登录失败", message: error.localizedDescription)
            }
        }
    }

    private func doVerify() async {
        guard twoFAModes.indices.contains(twoFAIndex) else { return }
        let m = twoFAModes[twoFAIndex]
        verifying = true
        do {
            let r = try await backend.loginVerify(code: code, mode: m.type, index: m.index)
            await MainActor.run {
                verifying = false
                if r["status"] as? String == "2fa" {
                    addLog("验证码不正确，请重试", level: .warn)
                    code = ""
                } else {
                    show2FA = false
                    loggedIn = true
                    password = ""
                    code = ""
                    addLog("验证通过，登录成功")
                    Task { await refresh() }
                }
            }
        } catch {
            await MainActor.run {
                verifying = false
                addLog("验证失败：\(error.localizedDescription)", level: .error)
            }
        }
    }

    private func logout() async {
        _ = try? await backend.request("/api/logout", method: "POST",
                                       headers: ["X-Auth-Token": settings.idToken])
        await MainActor.run { loggedIn = false; teamName = "" }
    }

    private func doSign() async {
        guard let ipa = ipaURL else { return }
        busy = true
        progress = 0
        result = nil
        busyText = "上传中…"
        addLog(mode == .appleID ? "使用 Apple ID 签" : "使用证书签")

        // 服务端日志轮询，实时把 zsign / Apple 往返的进度回显到手机
        let poller = Task { await pollLogs() }
        defer { poller.cancel() }

        do {
            let r: SignResult
            if mode == .appleID {
                busyText = "申请证书并签名…"
                r = try await backend.sign(ipa: ipa, progress: { p in
                    DispatchQueue.main.async { progress = p }
                })
            } else {
                busyText = "上传并签名…"
                r = try await backend.signWithCert(ipa: ipa, p12: p12URL!, prov: provURL!,
                                                   password: p12Password, progress: { p in
                    DispatchQueue.main.async { progress = p }
                })
            }
            await MainActor.run {
                busy = false
                result = r
                addLog("签名完成：\(r.bundleId)")
                install(r)
            }
        } catch {
            await MainActor.run {
                busy = false
                addLog("失败：\(error.localizedDescription)", level: .error)
                alert = AlertItem(title: "签名失败", message: error.localizedDescription)
            }
        }
    }

    private func pollLogs() async {
        while !Task.isCancelled {
            if let lines = try? await backend.logs() {
                await MainActor.run { logs = lines }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func install(_ r: SignResult) {
        guard let u = URL(string: r.itmsURL) else { return }
        UIApplication.shared.open(u) { ok in
            if !ok { addLog("无法唤醒安装程序", level: .error) }
        }
    }
}

// MARK: - 辅助

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}
