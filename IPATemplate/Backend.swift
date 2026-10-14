import Foundation
import SwiftUI

// MARK: - 配置

enum Defaults {
    /// 走 sslip.io 免费解析的域名，由 Let's Encrypt 签发公开可信证书。
    /// 不要改回裸 IP：iOS 的 Profile Service（UDID 描述文件）走的是 MDM 级
    /// 信任校验，自签证书即使装了根证书也必须手动开「完全信任」，否则报
    /// 「MDM服务器证书无效」。用公开证书域名则完全不需要这一步。
    static let base = "https://3-148-102-133.sslip.io/idsign"
}

final class AppSettings: ObservableObject {
    @AppStorage("srv.base") var base: String = Defaults.base
    @AppStorage("srv.idtoken") var idToken: String = "pia-id-jnk25m3qhggws3iv"
    @AppStorage("srv.otatoken") var otaToken: String = "pia-ota-ahwwurtqt7ubfw2u"
    @AppStorage("sign.appleid") var appleId: String = ""

    var baseURL: String { base.hasSuffix("/") ? String(base.dropLast()) : base }
}

// MARK: - 模型

struct TwoFactorMode: Identifiable, Codable {
    var id: String { type + "-\(index)" }
    let type: String       // trusted_device / sms
    let index: Int
    let label: String
}

struct ServerState: Codable {
    struct UdidRow: Codable, Identifiable {
        var id: String { udid }
        let udid: String
        let product: String
        let version: String
    }
    struct Sess: Codable {
        let logged_in: Bool
        let appleid: String?
        let team_id: String?
        let team_name: String?
    }
    let ok: Bool
    let session: Sess
    let udids: [UdidRow]
    let public_base: String
    let zsign: Bool
}

struct SignResult {
    let bundleId: String
    let bundleName: String
    let version: String
    let itmsURL: String
    let installURL: String
    let size: Int64
}

// MARK: - 后端

enum BackendError: LocalizedError {
    case badURL
    case http(Int, String)
    case server(String)
    case trust

    var errorDescription: String? {
        switch self {
        case .badURL: return "服务器地址不合法"
        case .http(let c, let b):
            if c == -999 || c == -1202 || c == -1201 || c == -1203 || c == -1204 || c == -1205 || c == -1206 {
                return "证书不受信任。请先安装根证书，并在「设置 → 通用 → 关于本机 → 证书信任设置」里启用完全信任。"
            }
            if c == -1001 { return "连接超时，检查网络或服务器是否在线" }
            if c == -1004 { return "无法连接到服务器" }
            return "HTTP \(c)：\(b.prefix(200))"
        case .server(let s): return s
        case .trust: return "证书校验失败"
        }
    }
}

final class Backend {

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 900
        cfg.httpAdditionalHeaders = ["User-Agent": "IPA-Toolbox/1.0"]
        self.session = URLSession(configuration: cfg)
    }

    // MARK: 底层

    func request(_ path: String,
                 method: String = "GET",
                 body: Data? = nil,
                 headers: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: AppSettings().baseURL + path) else { throw BackendError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw BackendError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch let e as BackendError {
            throw e
        } catch {
            let code = (error as NSError).code
            throw BackendError.http(code, error.localizedDescription)
        }
    }

    private func json(_ path: String,
                      method: String = "GET",
                      body: [String: Any]? = nil,
                      auth: Bool = false) async throws -> [String: Any] {
        var headers = ["Content-Type": "application/json"]
        if auth { headers["X-Auth-Token"] = AppSettings().idToken }
        var data: Data? = nil
        if let b = body { data = try? JSONSerialization.data(withJSONObject: b) }
        let out = try await request(path, method: method, body: data, headers: headers)
        guard let js = try? JSONSerialization.jsonObject(with: out) as? [String: Any] else {
            throw BackendError.server("返回不是 JSON：" + (String(data: out, encoding: .utf8) ?? "").prefix(150))
        }
        if js["ok"] as? Bool == false {
            throw BackendError.server(js["error"] as? String ?? "未知错误")
        }
        return js
    }

    // MARK: 状态

    func state() async throws -> ServerState {
        let out = try await request("/state")
        return try JSONDecoder().decode(ServerState.self, from: out)
    }

    func logs() async throws -> [LogLine] {
        struct R: Codable { let lines: [L] }
        struct L: Codable { let t: String; let msg: String; let level: String }
        let out = try await request("/log")
        let r = try JSONDecoder().decode(R.self, from: out)
        return r.lines.map { l in
            LogLine(timeText: l.t, message: l.msg, level: LogLevel(rawValue: l.level) ?? .info)
        }
    }

    // MARK: 云更新
    //
    // 服务端用 CFBundleVersion（build 号，单调递增整数）判断新旧，
    // 客户端只把版本号带上去当展示/日志用，不参与比较。

    func checkUpdate(version: String, build: Int) async throws -> UpdateCheck {
        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "ver", value: version),
            URLQueryItem(name: "build", value: String(build))
        ]
        // 自己拼 query 一定要编码：版本号里理论上不该有特殊字符，
        // 但地址栏里多一个 & 就能把请求打歪，索性交给 URLComponents。
        let query = comps.percentEncodedQuery ?? ""
        let out = try await request("/appcast?\(query)")
        return try JSONDecoder().decode(UpdateCheck.self, from: out)
    }

    // MARK: 登录

    func loginStart(appleId: String, password: String) async throws -> [String: Any] {
        try await json("/api/login/start", method: "POST",
                       body: ["appleid": appleId, "password": password], auth: true)
    }

    func loginVerify(code: String, mode: String, index: Int) async throws -> [String: Any] {
        try await json("/api/login/verify", method: "POST",
                       body: ["code": code, "mode": mode, "index": index], auth: true)
    }

    // MARK: 签名（multipart）

    func sign(ipa: URL,
              bundleId: String? = nil,
              udid: String? = nil,
              progress: @escaping (Double) -> Void) async throws -> SignResult {
        guard let url = URL(string: AppSettings().baseURL + "/api/sign") else { throw BackendError.badURL }
        let boundary = "IPA-TOOLBOX-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(AppSettings().idToken, forHTTPHeaderField: "X-Auth-Token")
        req.timeoutInterval = 900

        let fileName = ipa.lastPathComponent
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        if let b = bundleId { field("bundle_id", b) }
        if let u = udid { field("udid", u) }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        if let ipaData = try? Data(contentsOf: ipa) {
            body.append(ipaData)
        }
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await session.upload(for: req, from: body,
                                                    delegate: ProgressDelegate(progress))
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BackendError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let js = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackendError.server("返回不是 JSON")
        }
        if js["ok"] as? Bool == false {
            throw BackendError.server(js["error"] as? String ?? "签名失败")
        }
        return SignResult(
            bundleId: js["bundle_id"] as? String ?? "",
            bundleName: js["bundle_name"] as? String ?? "",
            version: js["version"] as? String ?? "",
            itmsURL: js["itms_url"] as? String ?? "",
            installURL: js["install_url"] as? String ?? "",
            size: js["size"] as? Int64 ?? 0
        )
    }

    // MARK: 证书签（自带 p12 + 描述文件）

    func signWithCert(ipa: URL,
                      p12: URL,
                      prov: URL,
                      password: String,
                      progress: @escaping (Double) -> Void) async throws -> SignResult {
        guard let url = URL(string: AppSettings().baseURL + "/api/sign/cert") else {
            throw BackendError.badURL
        }
        let boundary = "IPA-TOOLBOX-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(AppSettings().idToken, forHTTPHeaderField: "X-Auth-Token")
        req.timeoutInterval = 900

        var body = Data()
        func attach(_ name: String, _ file: URL, _ mime: String) throws {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(file.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
            body.append(try Data(contentsOf: file))
            body.append("\r\n".data(using: .utf8)!)
        }
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        try attach("file", ipa, "application/octet-stream")
        try attach("p12", p12, "application/x-pkcs12")
        try attach("prov", prov, "application/octet-stream")
        field("password", password)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, resp) = try await session.upload(for: req, from: body,
                                                    delegate: ProgressDelegate(progress))
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BackendError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let js = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackendError.server("返回不是 JSON")
        }
        if js["ok"] as? Bool == false {
            throw BackendError.server(js["error"] as? String ?? "签名失败")
        }
        return SignResult(
            bundleId: js["bundle_id"] as? String ?? "",
            bundleName: js["bundle_name"] as? String ?? "",
            version: js["version"] as? String ?? "",
            itmsURL: js["itms_url"] as? String ?? "",
            installURL: js["install_url"] as? String ?? "",
            size: js["size"] as? Int64 ?? 0
        )
    }
}

// 上传进度回调（URLSessionTaskDelegate 的 URLSession.data 没有进度，用 upload(for:from:delegate:) 才有）
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    let handler: (Double) -> Void
    init(_ handler: @escaping (Double) -> Void) { self.handler = handler }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        handler(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
