import SwiftUI
import UniformTypeIdentifiers

/// 主界面：播放列表
struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    @StateObject private var engine = PlayerEngine()

    @State private var showImporter = false
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var playingPlaylist: [VideoItem] = []
    @State private var playingIndex = 0
    @State private var showPlayer = false

    private var filteredItems: [VideoItem] {
        if searchText.isEmpty { return store.items }
        return store.items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            Button {
                                startPlayback(item: item)
                            } label: {
                                VideoRow(item: item, isPlaying: store.playingID == item.id)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            // 同步过滤后的索引到真实列表
                            let ids = offsets.compactMap { filteredItems[$0].id }
                            store.items.removeAll { ids.contains($0.id) }
                            store.saveItems()
                        }
                        .onMove { source, destination in
                            // 过滤状态下的排序回写到主列表
                            let moved = filteredItems
                            var target = moved
                            target.move(fromOffsets: source, toOffset: destination)
                            for (i, item) in target.enumerated() {
                                if let idx = store.items.firstIndex(where: { $0.id == item.id }) {
                                    store.items[idx] = item
                                }
                            }
                            store.saveItems()
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("本地播放器")
            .searchable(text: $searchText, prompt: "搜索视频")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        EditButton()
                        Button {
                            showImporter = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker { urls in
                    store.add(urls: urls)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(store: store)
            }
            .fullScreenCover(isPresented: $showPlayer) {
                PlayerView(
                    engine: engine,
                    store: store,
                    playlist: playingPlaylist,
                    startIndex: playingIndex
                )
                .onDisappear {
                    store.playingID = nil
                }
            }
            .onAppear {
                store.importFromDocumentsFolder()
            }
            // 从「分享菜单 → 用本地播放器打开」导入
            .onOpenURL { url in
                store.add(urls: [url])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
            Text("还没有视频")
                .font(.title3.weight(.semibold))
            Text("点右上角 + 从「文件」App 导入，\n或用数据线把视频拖进本 App 的文档目录")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("选择视频文件") { showImporter = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func startPlayback(item: VideoItem) {
        playingPlaylist = store.items
        playingIndex = playingPlaylist.firstIndex(where: { $0.id == item.id }) ?? 0
        showPlayer = true
    }
}

/// 列表行
private struct VideoRow: View {
    let item: VideoItem
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPlaying ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 52, height: 38)
                Image(systemName: isPlaying ? "play.fill" : "film")
                    .foregroundColor(isPlaying ? .accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 15))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if item.duration > 0 {
                        Text(formatTime(item.duration))
                    }
                    if item.lastPosition > 1 {
                        Text("续播 \(Int(item.lastPosition / max(item.duration, 1) * 100))%")
                            .foregroundColor(.accentColor)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            Spacer()
            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// 系统文件选择器（包装 UIDocumentPickerViewController）
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: ImportTypes.all, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
