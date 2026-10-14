import SwiftUI

// MARK: - 根视图：签名 / 检查 / 设置

struct ContentView: View {
    @State private var tab: Tab = .sign
    @StateObject private var updateCenter = UpdateCenter()

    enum Tab: String, Hashable {
        case sign = "签名"
        case inspect = "检查"
        case settings = "设置"

        var icon: String {
            switch self {
            case .sign: return "signature"
            case .inspect: return "doc.text.magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationView { SignView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label(Tab.sign.rawValue, systemImage: Tab.sign.icon)
                }
                .tag(Tab.sign)

            NavigationView { InspectView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label(Tab.inspect.rawValue, systemImage: Tab.inspect.icon)
                }
                .tag(Tab.inspect)

            NavigationView { SettingsView() }
                .navigationViewStyle(.stack)
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
        .accentColor(Palette.brandBottom)
        .environmentObject(updateCenter)
        // 启动静默查一次（内部有 6 小时节流 + 跳过版本记忆，不会反复打扰）
        .task { await updateCenter.checkOnLaunch() }
        .sheet(isPresented: $updateCenter.showSheet) {
            UpdateSheet(center: updateCenter)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppSettings())
            .environmentObject(UpdateCenter())
    }
}
