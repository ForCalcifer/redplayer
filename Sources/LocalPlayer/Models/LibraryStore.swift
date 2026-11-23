import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 播放列表 + 设置的持久化管理
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published var items: [VideoItem] = []
    @Published var settings = PlaybackSettings()

    /// 当前正在播放的条目 id（由播放器视图写入，供 UI 高亮）
    @Published var playingID: UUID?

    private let itemsKey = "localplayer.items.v1"
    private let settingsKey = "localplayer.settings.v1"
    private let defaults = UserDefaults.standard

    private init() {
        load()
    }

    // MARK: - 持久化

    private func load() {
        if let data = defaults.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([VideoItem].self, from: data) {
            items = decoded
        }
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(PlaybackSettings.self, from: data) {
            settings = decoded
        }
    }

    func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: itemsKey)
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    // MARK: - 播放列表操作

    func add(urls: [URL]) {
        for url in urls {
            if let item = VideoItem.make(from: url), !items.contains(where: { $0.name == item.name }) {
                items.append(item)
            }
        }
        saveItems()
    }

    /// 导入 App 文档目录里的所有视频（通过「文件」App 拖进来的）
    func importFromDocumentsFolder() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let files = (try? fm.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let videoExts: Set<String> = [
            "mp4", "mov", "m4v", "mkv", "avi", "flv", "wmv", "webm",
            "ts", "m2ts", "rmvb", "rm", "mpg", "mpeg", "3gp", "vob"
        ]
        let candidates = files.filter { videoExts.contains($0.pathExtension.lowercased()) }
        if !candidates.isEmpty {
            add(urls: candidates)
        }
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveItems()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        saveItems()
    }

    func rename(item: VideoItem, to newName: String) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].name = newName
        saveItems()
    }

    /// 记录播放进度（约每 5 秒调用一次）
    func updateProgress(id: UUID, position: TimeInterval, duration: TimeInterval) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].lastPosition = position
        if duration > 0 { items[idx].duration = duration }
        saveItems()
    }

    func clearProgress(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].lastPosition = 0
        saveItems()
    }
}

/// 导入视频用的文档选择器支持类型
enum ImportTypes {
    static let all: [UTType] = {
        var types: [UTType] = [.movie, .video, .audio]
        // 补充系统未声明的自定义格式
        for identifier in ["org.matroska.mkv", "org.webmproject.webm", "com.realnetworks.rmvb"] {
            if let t = UTType(identifier) { types.append(t) }
        }
        // 兜底：允许选择任意文件（MKV/TS 等在某些 iOS 版本上没有 UTI）
        types.append(.data)
        return types
    }()
}
