import SwiftUI

// MARK: - 设计系统
// 统一在这里定义颜色/尺寸/圆角，页面只消费不定义，保证视觉一致。

enum Palette {
    // 主色：青蓝渐变（品牌色）
    static let brandTop = Color(red: 0.20, green: 0.78, blue: 1.00)
    static let brandBottom = Color(red: 0.16, green: 0.42, blue: 0.98)

    // 语义色
    static let ok = Color(red: 0.20, green: 0.78, blue: 0.45)
    static let warn = Color(red: 1.00, green: 0.68, blue: 0.20)
    static let danger = Color(red: 1.00, green: 0.42, blue: 0.42)
    static let idle = Color.secondary

    // 卡片描边（适配深浅色）
    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    // 卡片底色（适配深浅色）
    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.85)
    }

    // 页面底色渐变
    static func pageBackground(_ scheme: ColorScheme) -> [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.05, green: 0.07, blue: 0.13),
                Color(red: 0.03, green: 0.04, blue: 0.08)
            ]
        }
        return [
            Color(red: 0.96, green: 0.97, blue: 0.99),
            Color(red: 0.91, green: 0.93, blue: 0.97)
        ]
    }
}

enum Metrics {
    static let radiusCard: CGFloat = 18
    static let radiusControl: CGFloat = 14
    static let paddingCard: CGFloat = 16
    static let gap: CGFloat = 12
}

extension View {
    /// 统一的玻璃卡片外观
    func glassCard(_ scheme: ColorScheme) -> some View {
        self
            .background(Palette.cardBackground(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                    .stroke(Palette.stroke(scheme), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.35 : 0.07),
                radius: scheme == .dark ? 18 : 10,
                x: 0,
                y: scheme == .dark ? 8 : 4
            )
    }
}

/// 品牌渐变（用于主按钮、图标底等）
let brandGradient = LinearGradient(
    colors: [Palette.brandTop, Palette.brandBottom],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// 页面背景
struct PageBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(
            colors: Palette.pageBackground(scheme),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
