import Foundation
import Compression

// MARK: - 极简 ZIP 读取器
//
// iOS 没有内置 zip 库（libzip / minizip 都不在 SDK 里），而「从 IPA 里读出
// Bundle ID / 版本号」又必须在本地完成 —— 所以这里用系统自带的 Compression
// 框架（raw deflate 解压）实现一个只读的 ZIP 解析器。
// 只支持 ZIP 最常用的两种存储方式：0（不压缩）与 8（deflate）。

struct ZipEntry {
    let name: String
    let uncompressedSize: UInt64
    let compressedSize: UInt64
    let method: UInt16
    let localHeaderOffset: UInt64
}

enum ZipError: LocalizedError {
    case notAZip
    case endOfCentralDirectoryNotFound
    case corruptCentralDirectory
    case unsupportedCompression(method: UInt16)
    case inflateFailed

    var errorDescription: String? {
        switch self {
        case .notAZip:
            return "不是有效的 ZIP/IPA 文件"
        case .endOfCentralDirectoryNotFound:
            return "找不到 ZIP 结尾记录（文件可能损坏）"
        case .corruptCentralDirectory:
            return "ZIP 中央目录损坏"
        case .unsupportedCompression(let m):
            return "不支持的压缩方式（method=\(m)）"
        case .inflateFailed:
            return "解压失败"
        }
    }
}

final class ZipReader {
    private let data: Data

    init(url: URL) throws {
        // IPA 动辄几十上百 MB；用 .mappedIfSafe 走 mmap，避免内存峰值翻倍。
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 4 else { throw ZipError.notAZip }
        guard data[0] == 0x50, data[1] == 0x4B else { throw ZipError.notAZip }  // "PK"
    }

    // MARK: - 小端读取

    private func u16(_ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func u32(_ offset: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(data[offset + i]) << (8 * i) }
        return v
    }

    // MARK: - 中央目录

    private func findEOCD() throws -> (count: UInt16, size: UInt32, offset: UInt32) {
        // EOCD 位于文件尾部（后跟最多 64KB 注释），签名 = 0x06054B50
        guard data.count >= 22 else { throw ZipError.notAZip }
        let maxBack = min(data.count, 65_557)
        let floor = data.count - maxBack
        var i = data.count - 22
        while i >= floor {
            if data[i] == 0x50, data[i + 1] == 0x4B,
               data[i + 2] == 0x05, data[i + 3] == 0x06 {
                return (u16(i + 10), u32(i + 12), u32(i + 16))
            }
            i -= 1
        }
        throw ZipError.endOfCentralDirectoryNotFound
    }

    func entries() throws -> [ZipEntry] {
        let eocd = try findEOCD()
        var out: [ZipEntry] = []
        out.reserveCapacity(Int(eocd.count))
        var p = Int(eocd.offset)
        let limit = min(data.count, p + Int(eocd.size))
        while p + 46 <= limit {
            guard u32(p) == 0x02014B50 else { break }
            let method = u16(p + 10)
            let csize = UInt64(u32(p + 20))
            let usize = UInt64(u32(p + 24))
            let nameLen = Int(u16(p + 28))
            let extraLen = Int(u16(p + 30))
            let commentLen = Int(u16(p + 32))
            let localOffset = UInt64(u32(p + 42))
            let nameStart = p + 46
            guard nameStart + nameLen <= data.count else { break }
            let name = String(decoding: data[nameStart..<(nameStart + nameLen)], as: UTF8.self)
            out.append(ZipEntry(name: name,
                                uncompressedSize: usize,
                                compressedSize: csize,
                                method: method,
                                localHeaderOffset: localOffset))
            p = nameStart + nameLen + extraLen + commentLen
        }
        if out.isEmpty { throw ZipError.corruptCentralDirectory }
        return out
    }

    // MARK: - 读条目内容

    func data(for entry: ZipEntry) throws -> Data {
        let p = Int(entry.localHeaderOffset)
        guard p + 30 <= data.count, u32(p) == 0x04034B50 else {
            throw ZipError.corruptCentralDirectory
        }
        let nameLen = Int(u16(p + 26))
        let extraLen = Int(u16(p + 28))
        let start = p + 30 + nameLen + extraLen
        let csize = Int(entry.compressedSize)
        guard start + csize <= data.count else { throw ZipError.corruptCentralDirectory }
        let raw = data[start..<(start + csize)]

        switch entry.method {
        case 0:
            return Data(raw)
        case 8:
            return try Self.inflate(Data(raw), expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(method: entry.method)
        }
    }

    /// 取 Payload/xxx.app/Info.plist（取路径最短的那个 = 主 App）
    func appInfoPlist() throws -> Data? {
        let all = try entries()
        guard let best = all.filter({ $0.name.hasSuffix(".app/Info.plist") })
            .sorted(by: { $0.name.count < $1.name.count }).first else { return nil }
        return try data(for: best)
    }

    // MARK: - raw deflate

    private static func inflate(_ raw: Data, expectedSize: UInt64) throws -> Data {
        // 中央目录里的 uncompressedSize 是可信的，直接用它开输出缓冲区
        let capacity = max(Int(expectedSize), 64 * 1024)
        var out = Data(count: capacity)

        // compression_stream 的 dst_ptr / src_ptr 在 Swift 里是
        // UnsafeMutablePointer<UInt8> / UnsafePointer<UInt8>（非可选），传 nil 编不过。
        // 用两个栈上的字节取地址当占位：compression_stream_init 只分配内部 state，
        // 不会读写这两个指针；下面紧接着就会把真正的输入输出缓冲赋进去。
        // 用栈变量而不是 allocate，也就不存在忘了释放的泄漏问题。
        var dstProbe: UInt8 = 0
        var srcProbe: UInt8 = 0
        var stream = withUnsafeMutablePointer(to: &dstProbe) { dst in
            withUnsafePointer(to: &srcProbe) { src in
                compression_stream(
                    dst_ptr: dst, dst_size: 0,
                    src_ptr: src, src_size: 0,
                    state: nil
                )
            }
        }
        let initStatus = compression_stream_init(
            &stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB
        )
        guard initStatus == COMPRESSION_STATUS_OK else { throw ZipError.inflateFailed }
        defer { compression_stream_destroy(&stream) }

        var produced = 0
        var status: compression_status = COMPRESSION_STATUS_ERROR

        status = raw.withUnsafeBytes { srcBuf -> compression_status in
            guard let src = srcBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return COMPRESSION_STATUS_ERROR
            }
            stream.src_ptr = src
            stream.src_size = raw.count

            return out.withUnsafeMutableBytes { dstBuf -> compression_status in
                guard let dst = dstBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return COMPRESSION_STATUS_ERROR
                }
                stream.dst_ptr = dst
                stream.dst_size = capacity
                let st = compression_stream_process(&stream, 0)
                produced = capacity - stream.dst_size
                return st
            }
        }

        guard status != COMPRESSION_STATUS_ERROR else { throw ZipError.inflateFailed }
        // COMPRESSION_STATUS_END 表示正好解完；OK 表示输出缓冲先满了（此时已截断）
        return out.prefix(produced)
    }
}
