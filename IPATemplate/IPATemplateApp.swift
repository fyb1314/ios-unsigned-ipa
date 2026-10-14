import SwiftUI

@main
struct IPATemplateApp: App {
    init() {
        UITableView.appearance().backgroundColor = .clear
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
