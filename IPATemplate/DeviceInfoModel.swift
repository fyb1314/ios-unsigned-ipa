import Foundation
import UIKit
import Combine

struct InfoItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

struct InfoSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [InfoItem]
}

final class DeviceInfoModel: ObservableObject {
    @Published private(set) var sections: [InfoSection] = []

    init() {
        reload()
    }

    func reload() {
        let disk = Self.diskInfo()
        sections = [
            InfoSection(title: "设备", items: [
                InfoItem(label: "名称", value: UIDevice.current.name),
                InfoItem(label: "硬件型号", value: Self.hardwareIdentifier()),
                InfoItem(label: "系统", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"),
            ]),
            InfoSection(title: "屏幕", items: [
                InfoItem(label: "分辨率", value: Self.screenResolution()),
                InfoItem(label: "缩放比例", value: String(format: "%.1fx", UIScreen.main.scale)),
            ]),
            InfoSection(title: "存储", items: [
                InfoItem(label: "总容量", value: disk.total),
                InfoItem(label: "可用空间", value: disk.free),
            ]),
            InfoSection(title: "内存", items: [
                InfoItem(label: "物理内存", value: Self.byteString(Int64(ProcessInfo.processInfo.physicalMemory))),
            ]),
            InfoSection(title: "电池", items: [
                InfoItem(label: "电量", value: Self.batteryLevel()),
                InfoItem(label: "状态", value: Self.batteryState()),
            ]),
        ]
    }

    func plainTextReport() -> String {
        var lines: [String] = ["偶尔的PIA工具 · 导出报告", ""]
        for section in sections {
            lines.append("[\(section.title)]")
            for item in section.items {
                lines.append("\(item.label): \(item.value)")
            }
            lines.append("")
        }
        lines.append("生成时间: \(Self.timestamp())")
        return lines.joined(separator: "\n")
    }

    static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children
            .compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { String(UnicodeScalar(UInt8($0))) }
            .joined()
        return identifier.isEmpty ? "未知" : identifier
    }

    static func screenResolution() -> String {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        return "\(width) x \(height)"
    }

    static func diskInfo() -> (total: String, free: String) {
        let home = NSHomeDirectory()
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: home),
              let totalSize = attributes[.systemSize] as? Int64,
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return ("未知", "未知")
        }
        return (byteString(totalSize), byteString(freeSize))
    }

    static func byteString(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func batteryLevel() -> String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "未知" }
        return "\(Int((level * 100).rounded()))%"
    }

    static func batteryState() -> String {
        switch UIDevice.current.batteryState {
        case .charging:
            return "充电中"
        case .full:
            return "已充满"
        case .unplugged:
            return "未充电"
        case .unknown:
            fallthrough
        @unknown default:
            return "未知"
        }
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
