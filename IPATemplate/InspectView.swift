import SwiftUI
import UniformTypeIdentifiers

// MARK: - 检查页
// 在本地解析 IPA / 描述文件 / p12，不联网、不上传。

struct InspectView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var showPicker = false
    @State private var result: InspectResult?
    @State private var fileName: String?
    @State private var error: String?
    @State private var p12Password = ""
    @State private var askPassword = false
    @State private var pendingURL: URL?

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(spacing: Metrics.gap) {
                    pickerCard
                    if let r = result { contentCard(r) }
                    if let e = error {
                        VStack(alignment: .leading, spacing: 8) {
                            CardTitle(icon: "xmark.octagon", title: "解析失败")
                            Text(e).font(.system(size: 13)).foregroundColor(Palette.danger)
                        }
                        .padding(Metrics.paddingCard)
                        .glassCard(scheme)
                    }
                    if result == nil && error == nil {
                        EmptyHint(icon: "doc.text.magnifyingglass",
                                  text: "选择一个文件查看它的真实信息\nIPA 会读出 Bundle ID 与版本号，描述文件会读出到期时间与已登记设备")
                    }
                }
                .padding(.horizontal, Metrics.paddingCard)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("检查")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            DocumentPicker(extensions: ["ipa", "mobileprovision", "p12", "pfx"]) { url in
                handle(url)
            }
        }
        .alert("证书密码", isPresented: $askPassword) {
            SecureField("密码（可为空）", text: $p12Password)
            Button("取消", role: .cancel) { pendingURL = nil }
            Button("确定") {
                if let u = pendingURL { parse(u, password: p12Password) }
                pendingURL = nil
            }
        } message: {
            Text("这个 p12 是加密的，请输入它的导出密码")
        }
    }

    // MARK: UI

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(icon: "folder.badge.questionmark", title: "选择文件",
                      subtitle: "支持 .ipa / .mobileprovision / .p12")
            FileRow(icon: "doc.badge.plus", title: "从「文件」中选择",
                    hint: "解析过程完全在本机完成", fileName: fileName,
                    action: { showPicker = true })
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    @ViewBuilder
    private func contentCard(_ r: InspectResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(icon: iconFor(r.kind), title: "解析结果", subtitle: r.kind)
            if let ipa = r.ipa { ipaBlock(ipa) }
            if let p = r.provision { provisionBlock(p) }
            if let c = r.cert { certBlock(c) }
        }
        .padding(Metrics.paddingCard)
        .glassCard(scheme)
    }

    private func iconFor(_ kind: String) -> String {
        switch kind {
        case "IPA": return "app.dashed"
        case "描述文件": return "doc.badge.checkmark"
        default: return "key.viewfinder"
        }
    }

    private func ipaBlock(_ i: IpaInfo) -> some View {
        VStack(spacing: 4) {
            InfoLine(label: "文件名", value: i.fileName)
            InfoLine(label: "Bundle ID", value: i.bundleId, mono: true)
            InfoLine(label: "显示名称", value: i.displayName)
            InfoLine(label: "版本", value: "\(i.version)（build \(i.build)）")
            InfoLine(label: "最低系统", value: "iOS " + i.minOS)
            if !i.platforms.isEmpty { InfoLine(label: "设备", value: i.platforms) }
            InfoLine(label: "大小", value: ByteCountFormatter.string(fromByteCount: i.fileSize, countStyle: .file))
            InfoLine(label: "条目数", value: "\(i.entryCount)")
            InfoLine(label: "SHA256", value: String(i.sha256.prefix(32)) + "…", mono: true)
        }
    }

    private func provisionBlock(_ p: ProvisionInfo) -> some View {
        VStack(spacing: 4) {
            InfoLine(label: "名称", value: p.name)
            InfoLine(label: "团队", value: p.teamName)
            InfoLine(label: "Team ID", value: p.teamId, mono: true)
            InfoLine(label: "Bundle ID", value: p.bundleId, mono: true)
            HStack(spacing: 10) {
                Text("到期")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .frame(width: 92, alignment: .leading)
                Text(expiresText(p))
                    .font(.system(size: 13))
                    .foregroundColor(p.isExpired ? Palette.danger : Palette.ok)
                Spacer()
            }
            HStack(spacing: 10) {
                Text("调试权限")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .frame(width: 92, alignment: .leading)
                StatusPill(text: p.getTaskAllow ? "可调试" : "发布型",
                           state: p.getTaskAllow ? .ok : .idle)
                Spacer()
            }
            HStack(spacing: 10) {
                Text("企业版")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .frame(width: 92, alignment: .leading)
                StatusPill(text: p.isEnterprise ? "是" : "否",
                           state: p.isEnterprise ? .warn : .idle)
                Spacer()
            }
            Divider().padding(.vertical, 4)
            Text("已登记设备（\(p.udids.count)）")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            ForEach(p.udids, id: \.self) { u in
                Text(u).font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func certBlock(_ c: CertInfo) -> some View {
        VStack(spacing: 4) {
            InfoLine(label: "证书", value: c.summary)
            InfoLine(label: "Team ID", value: c.teamId, mono: true)
            InfoLine(label: "有效期", value: "\(dateText(c.notBefore)) → \(dateText(c.notAfter))")
            HStack(spacing: 10) {
                Text("状态")
                    .font(.system(size: 13)).foregroundColor(.secondary)
                    .frame(width: 92, alignment: .leading)
                StatusPill(text: c.isExpired ? "已过期" : "有效",
                           state: c.isExpired ? .danger : .ok)
                Spacer()
            }
        }
    }

    // MARK: 逻辑

    private func handle(_ url: URL) {
        fileName = url.lastPathComponent
        error = nil
        result = nil
        if ["p12", "pfx"].contains(url.pathExtension.lowercased()) {
            pendingURL = url
            p12Password = ""
            askPassword = true
        } else {
            parse(url, password: "")
        }
    }

    private func parse(_ url: URL, password: String) {
        do {
            let r = try Inspector.inspect(url: url, password: password)
            result = r
            error = nil
        } catch {
            result = nil
            self.error = error.localizedDescription
        }
    }

    private func expiresText(_ p: ProvisionInfo) -> String {
        guard let d = p.expires else { return "—" }
        let s = dateText(p.expires)
        if p.isExpired { return "\(s)（已过期）" }
        if let days = p.daysLeft { return "\(s)（还剩 \(days) 天）" }
        return s
    }

    private func dateText(_ d: Date?) -> String {
        guard let d = d else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
