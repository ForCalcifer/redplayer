import SwiftUI

/// 全局设置
struct SettingsView: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("播放") {
                    Picker("默认倍速", selection: Binding(
                        get: { store.settings.defaultRate },
                        set: { store.settings.defaultRate = $0; store.saveSettings() }
                    )) {
                        ForEach([Float]([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]), id: \.self) { s in
                            Text(String(format: "%.2fx", s)).tag(s)
                        }
                    }

                    Picker("默认宽高比", selection: Binding(
                        get: { store.settings.aspectRatio },
                        set: { store.settings.aspectRatio = $0; store.saveSettings() }
                    )) {
                        ForEach(AspectRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio.rawValue)
                        }
                    }

                    Picker("循环模式", selection: Binding(
                        get: { store.settings.repeatMode },
                        set: { store.settings.repeatMode = $0; store.saveSettings() }
                    )) {
                        ForEach(RepeatMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.symbol).tag(mode.rawValue)
                        }
                    }

                    Toggle("记忆播放位置", isOn: Binding(
                        get: { store.settings.rememberPosition },
                        set: { store.settings.rememberPosition = $0; store.saveSettings() }
                    ))
                }

                Section("播放列表") {
                    NavigationLink("重命名视频") {
                        RenameListView(store: store)
                    }
                    Button("清空所有续播记录") {
                        for i in store.items.indices { store.items[i].lastPosition = 0 }
                        store.saveItems()
                    }
                    .foregroundColor(.accentColor)

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("清空播放列表（不会删除源文件）")
                    }
                    .confirmationDialog("确定清空播放列表？", isPresented: $showClearConfirm) {
                        Button("清空", role: .destructive) {
                            store.items.removeAll()
                            store.saveItems()
                        }
                        Button("取消", role: .cancel) {}
                    }
                }

                Section("关于") {
                    Text("基于 VideoLAN VLCKit 内核，支持 MKV / AVI / MP4 / MOV / FLV / TS / WebM / RMVB 等几乎所有常见格式。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("横屏 / 竖屏 · 手势调音量亮度进度 · 后台播放 · 锁屏控制")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

/// 批量重命名
private struct RenameListView: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        List {
            ForEach(store.items.indices, id: \.self) { i in
                TextField("名称", text: Binding(
                    get: { store.items[i].name },
                    set: { store.items[i].name = $0; store.saveItems() }
                ))
            }
        }
        .navigationTitle("重命名视频")
        .navigationBarTitleDisplayMode(.inline)
    }
}
