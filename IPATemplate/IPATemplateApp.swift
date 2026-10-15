import SwiftUI

@main
struct IPATemplateApp: App {
    @StateObject private var settings = AppSettings()

    init() {
        // 让 List / Form 的背景透明，好让自定义渐变底色透出来
        UITableView.appearance().backgroundColor = .clear
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        // 清掉上次运行残留的导入副本，避免 Documents 越攒越大
        ImportCache.purgeAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}
