import SwiftUI

struct ContentView: View {
    @StateObject private var model = DeviceInfoModel()
    @State private var showCopiedHint = false

    var body: some View {
        NavigationView {
            List {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            InfoRow(label: item.label, value: item.value)
                        }
                    } header: {
                        Text(section.title)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("本工具只读取设备公开信息，不联网、不上传任何数据。", systemImage: "lock.shield")
                        Label("修改 Bundle ID、版本号请编辑工程后重新构建。", systemImage: "hammer")
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                } header: {
                    Text("关于")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("偶尔的PIA工具")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        model.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        copyReport()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("复制报告")
                }
            }
            .overlay(alignment: .bottom) {
                if showCopiedHint {
                    Text("报告已复制到剪贴板")
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showCopiedHint)
        }
        .navigationViewStyle(.stack)
    }

    private func copyReport() {
        UIPasteboard.general.string = model.plainTextReport()
        showCopiedHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            showCopiedHint = false
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
