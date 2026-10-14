import Foundation
import SwiftUI
import Security
import CryptoKit

// MARK: - 日志

enum LogLevel: String {
    case info, warn, error

    var color: Color {
        switch self {
        case .info: return Color.primary.opacity(0.85)
        case .warn: return Palette.warn
        case .error: return Palette.danger
        }
    }
}

struct LogLine: Identifiable {
    let id = UUID()
    let timeText: String
    let message: String
    let level: LogLevel

    init(message: String, level: LogLevel = .info) {
        self.message = message
        self.level = level
        self.timeText = Self.nowText()
    }

    /// 用于服务端日志（带上服务器自己的时间戳，而不是本机时间）
    init(timeText: String, message: String, level: LogLevel) {
        self.timeText = timeText
        self.message = message
        self.level = level
    }

    private static func nowText() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

// MARK: - 检查结果模型

struct IpaInfo {
    var fileName = ""
    var fileSize: Int64 = 0
    var sha256 = ""
    var bundleId = ""
    var displayName = ""
    var version = ""
    var build = ""
    var minOS = ""
    var platforms = ""
    var entryCount = 0
}

struct ProvisionInfo {
    var name = ""
    var teamName = ""
    var teamId = ""
    var bundleId = ""
    var created: Date?
    var expires: Date?
    var udids: [String] = []
    var isEnterprise = false
    var getTaskAllow = false

    var isExpired: Bool {
        guard let e = expires else { return false }
        return e < Date()
    }

    var daysLeft: Int? {
        guard let e = expires else { return nil }
        return Int(ceil(e.timeIntervalSinceNow / 86400))
    }
}

struct CertInfo {
    var summary = ""
    var teamId = ""
    var notBefore: Date?
    var notAfter: Date?

    var isExpired: Bool {
        guard let a = notAfter else { return false }
        return a < Date()
    }
}

struct InspectResult {
    var kind: String = ""
    var ipa: IpaInfo?
    var provision: ProvisionInfo?
    var cert: CertInfo?
}

// MARK: - 文件检查

enum Inspector {

    // MARK: 入口

    static func inspect(url: URL, password: String = "") throws -> InspectResult {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "ipa", "zip":
            var r = InspectResult(kind: "IPA")
            r.ipa = try inspectIPA(url)
            return r
        case "mobileprovision", "provisionprofile":
            var r = InspectResult(kind: "描述文件")
            r.provision = try inspectProvision(url)
            return r
        case "p12", "pfx":
            var r = InspectResult(kind: "证书")
            r.cert = try inspectP12(url, password: password)
            return r
        default:
            throw NSError(domain: "Inspector", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "不支持的文件类型：.\(ext)"])
        }
    }

    // MARK: IPA

    static func inspectIPA(_ url: URL) throws -> IpaInfo {
        var info = IpaInfo()
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        info.fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        info.fileName = url.lastPathComponent

        let zip = try ZipReader(url: url)
        info.entryCount = (try? zip.entries().count) ?? 0

        // sha256：大文件分块算，别整块读进内存
        info.sha256 = try sha256(of: url)

        if let plistData = try? zip.appInfoPlist(),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
           let d = plist as? [String: Any] {
            info.bundleId = d["CFBundleIdentifier"] as? String ?? ""
            info.displayName = (d["CFBundleDisplayName"] as? String)
                ?? (d["CFBundleName"] as? String) ?? ""
            info.version = d["CFBundleShortVersionString"] as? String ?? ""
            info.build = d["CFBundleVersion"] as? String ?? ""
            info.minOS = d["MinimumOSVersion"] as? String ?? ""
            let fam = d["UIDeviceFamily"] as? [Int] ?? []
            info.platforms = fam.map { $0 == 1 ? "iPhone" : ($0 == 2 ? "iPad" : "\($0)") }
                .joined(separator: " / ")
        }
        return info
    }

    // MARK: 描述文件（.mobileprovision）

    static func inspectProvision(_ url: URL) throws -> ProvisionInfo {
        let raw = try Data(contentsOf: url)
        guard let plistData = extractEmbeddedPlist(raw),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
              let d = plist as? [String: Any] else {
            throw NSError(domain: "Inspector", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "无法解析描述文件（未找到内嵌 plist）"])
        }
        var p = ProvisionInfo()
        p.name = d["Name"] as? String ?? ""
        p.teamName = d["TeamName"] as? String ?? ""
        p.teamId = (d["TeamIdentifier"] as? [String])?.first ?? ""
        p.created = d["CreationDate"] as? Date
        p.expires = d["ExpirationDate"] as? Date
        p.udids = d["ProvisionedDevices"] as? [String] ?? []
        p.isEnterprise = (d["ProvisionsAllDevices"] as? Bool) ?? false

        if let appId = d["Entitlements"] as? [String: Any] {
            p.getTaskAllow = (appId["get-task-allow"] as? Bool) ?? false
            // 免费账号的 App ID 形如 <TEAMID>.<bundle>
            if let prefix = appId["application-identifier"] as? String, prefix.contains(".") {
                p.bundleId = String(prefix.drop(while: { $0 != "." }).dropFirst())
            }
            if let teamPrefix = d["ApplicationIdentifierPrefix"] as? [String], let t = teamPrefix.first {
                p.teamId = t
            }
        }
        return p
    }

    /// .mobileprovision 是一个 CMS 签名包，真正的 plist 以明文夹在中间
    private static func extractEmbeddedPlist(_ raw: Data) -> Data? {
        guard let start = find(Data("<?xml".utf8), in: raw) else { return nil }
        guard let end = find(Data("</plist>".utf8), in: raw, from: start) else { return nil }
        let stop = end + Data("</plist>".utf8).count
        return raw[start..<stop]
    }

    /// 手写子串查找，避免依赖 `Data.range(of:)` 的系统版本门槛
    private static func find(_ pattern: Data, in data: Data, from: Int = 0) -> Int? {
        let pc = pattern.count
        guard pc > 0, data.count >= pc else { return nil }
        let last = data.count - pc
        var i = max(0, from)
        while i <= last {
            if data[i] == pattern[0] {
                var ok = true
                for j in 1..<pc where data[i + j] != pattern[j] { ok = false; break }
                if ok { return i }
            }
            i += 1
        }
        return nil
    }

    // MARK: p12 证书

    static func inspectP12(_ url: URL, password: String) throws -> CertInfo {
        let data = try Data(contentsOf: url)
        var info = CertInfo()

        var items: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess else {
            let msg = (SecCopyErrorMessageString(status, nil) as String?)
                ?? "SecPKCS12Import 失败（\(status)）"
            throw NSError(domain: "Inspector", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey:
                            (status == -25293 || status == -25264) ? "证书密码错误" : msg])
        }
        guard let arr = items as? [[String: Any]],
              let dict = arr.first,
              let identity = dict[kSecImportItemIdentity as String] else {
            throw NSError(domain: "Inspector", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "p12 里没有可用的身份"])
        }
        let secIdentity = identity as! SecIdentity
        var cert: SecCertificate?
        SecIdentityCopyCertificate(secIdentity, &cert)
        guard let c = cert else {
            throw NSError(domain: "Inspector", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "无法取出证书"])
        }
        info.summary = "iPhone Developer"
        if let s = SecCertificateCopySubjectSummary(c) as String?, !s.isEmpty { info.summary = s }
        // iOS 上没有 SecCertificateCopyValues / kSecOIDX509V1ValidityNotBefore
        // （那是 macOS 专属），有效期只能自己从证书的 DER 里按 ASN.1 走出来。
        let (nb, na) = certValidity(SecCertificateCopyData(c) as Data)
        info.notBefore = nb
        info.notAfter = na

        // Team ID：Apple 开发者证书的 CN 形如「iPhone Developer: Name (A1B2C3D4E5)」，
        // 直接从摘要里取最末一对圆括号，比解析 subject 的 ASN.1 稳。
        if let m = info.summary.range(of: "\\(([A-Z0-9]{10})\\)", options: .regularExpression) {
            info.teamId = String(info.summary[m].dropFirst().dropLast())
        }
        return info
    }

    /// 从 X.509 证书的 DER 里取出 notBefore / notAfter。
    ///
    /// 为什么手写：iOS 的 Security 框架只给了 SecCertificateCopySubjectSummary /
    /// SecCertificateCopyData，查字段的 SecCertificateCopyValues 是 macOS 专属，
    /// iOS 上拿不到有效期。而「证书哪天过期」对签名工具是刚需，所以自己按
    /// ASN.1 走到 validity 那一段。纯 Swift，不依赖任何平台专属 API。
    ///
    /// 走法（RFC 5280）：
    ///   Certificate SEQUENCE
    ///     └ TBSCertificate SEQUENCE
    ///         ├ [0] version        （可选）
    ///         ├ serialNumber INTEGER
    ///         ├ signature SEQUENCE
    ///         ├ issuer SEQUENCE
    ///         └ validity SEQUENCE ── 里面就是 notBefore / notAfter 两个 Time
    static func certValidity(_ der: Data) -> (notBefore: Date?, notAfter: Date?) {
        let b = [UInt8](der)
        var i = 0

        func byte(_ at: Int) -> UInt8? { at < b.count ? b[at] : nil }

        func readLength(_ at: inout Int) -> Int? {
            guard let first = byte(at) else { return nil }
            at += 1
            if first < 0x80 { return Int(first) }          // 短格式
            let n = Int(first & 0x7F)                       // 长格式：后续 n 字节是长度
            guard n >= 1, n <= 4 else { return nil }
            var v = 0
            for _ in 0..<n {
                guard let x = byte(at) else { return nil }
                at += 1
                v = (v << 8) | Int(x)
            }
            return v
        }

        /// 跳过一整个 TLV（tag + length + value），用于绕过不关心的字段
        func skipTLV(_ at: inout Int) -> Bool {
            guard byte(at) != nil else { return false }
            at += 1
            guard let len = readLength(&at) else { return false }
            at += len
            return at <= b.count
        }

        /// 进入一个 SEQUENCE（tag 0x30），消费掉 tag 与长度
        func openSeq(_ at: inout Int) -> Bool {
            guard byte(at) == 0x30 else { return false }
            at += 1
            return readLength(&at) != nil
        }

        func readTime(_ at: inout Int) -> Date? {
            guard let tag = byte(at) else { return nil }
            at += 1
            guard let len = readLength(&at) else { return nil }
            guard at + len <= b.count else { return nil }
            let s = String(decoding: b[at..<(at + len)], as: UTF8.self)
            at += len
            return parseTime(s, generalized: tag == 0x18)
        }

        func parseTime(_ s: String, generalized: Bool) -> Date? {
            var digits: String
            if generalized {
                digits = String(s.prefix(14))               // YYYYMMDDHHMMSS
                guard digits.count == 14, digits.allSatisfy({ $0.isNumber }) else { return nil }
            } else {
                digits = String(s.prefix(12))               // YYMMDDHHMMSS
                guard digits.count == 12, digits.allSatisfy({ $0.isNumber }) else { return nil }
                // RFC 5280：两位年 50-99 归 19xx，00-49 归 20xx
                let yy = Int(digits.prefix(2)) ?? 0
                digits = (yy >= 50 ? "19" : "20") + digits
            }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyyMMddHHmmss"
            return f.date(from: digits)
        }

        guard openSeq(&i) else { return (nil, nil) }        // Certificate
        guard openSeq(&i) else { return (nil, nil) }        // TBSCertificate
        if byte(i) == 0xA0 { guard skipTLV(&i) else { return (nil, nil) } }   // version
        guard skipTLV(&i) else { return (nil, nil) }        // serialNumber
        guard skipTLV(&i) else { return (nil, nil) }        // signature
        guard skipTLV(&i) else { return (nil, nil) }        // issuer
        guard openSeq(&i) else { return (nil, nil) }        // validity
        let before = readTime(&i)
        let after = readTime(&i)
        return (before, after)
    }

    // MARK: 工具

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunk = 1024 * 1024
        while autoreleasepool(invoking: {
            let d = handle.readData(ofLength: chunk)
            if d.isEmpty { return false }
            hasher.update(data: d)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
