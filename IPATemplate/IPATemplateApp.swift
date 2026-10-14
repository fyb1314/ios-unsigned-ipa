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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}
