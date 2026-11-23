import Foundation
import SwiftUI

/// 播放列表中的一个视频条目
struct VideoItem: Identifiable, Codable, Hashable {
    let id: UUID
    /// 显示名称
    var name: String
    /// 安全作用域书签，App 重启后仍可访问「文件」App 里授权的目录
    var bookmark: Data
    /// 上次播放位置（秒），用于续播
    var lastPosition: TimeInterval = 0
    /// 视频总时长（秒）
    var duration: TimeInterval = 0
    /// 加入列表的时间
    var addedAt: Date = Date()

    init(id: UUID = UUID(), name: String, bookmark: Data) {
        self.id = id
        self.name = name
        self.bookmark = bookmark
    }

    /// 解析书签拿到可访问的 URL
    func resolveURL() -> URL? {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            return url
        }
        // 兼容普通书签（沙盒内文件）
        return try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// 从文件 URL 创建条目（生成书签，优先安全作用域，失败回退普通书签）
    static func make(from url: URL) -> VideoItem? {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        var bookmark = try? url.bookmarkData(
            options: [.withSecurityScope, .minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        if bookmark == nil {
            bookmark = try? url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        guard let bookmark else { return nil }
        return VideoItem(name: url.lastPathComponent, bookmark: bookmark)
    }
}

/// 播放设置（持久化）
struct PlaybackSettings: Codable {
    /// 默认倍速
    var defaultRate: Float = 1.0
    /// 默认宽高比原始值
    var aspectRatio: String = AspectRatio.auto.rawValue
    /// 循环模式
    var repeatMode: String = RepeatMode.sequential.rawValue
    /// 是否记忆播放位置
    var rememberPosition: Bool = true
    /// 音量 0...1
    var volume: Float = 1.0
}

enum RepeatMode: String, CaseIterable, Identifiable {
    case sequential = "顺序播放"      // 播完最后一个停止
    case loopAll = "列表循环"         // 播完最后一个回到第一个
    case repeatOne = "单集循环"       // 当前视频循环

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .sequential: return "arrow.right"
        case .loopAll: return "repeat"
        case .repeatOne: return "repeat.1"
        }
    }
}

/// 宽高比模式
enum AspectRatio: String, CaseIterable, Identifiable {
    case auto = "自动"
    case fit = "适应"
    case fill = "填充"
    case stretch = "拉伸"
    case r4_3 = "4:3"
    case r16_9 = "16:9"
    case r16_10 = "16:10"
    case r2_35 = "2.35:1"
    case r1_1 = "1:1"

    var id: String { rawValue }

    /// 传给 VLCKit 的 videoAspectRatio C 字符串；nil 表示恢复默认
    var vlcValue: String? {
        switch self {
        case .auto, .fit: return nil
        case .fill, .stretch: return nil   // 填充/拉伸用 scaleFactor 控制，见 PlayerEngine
        case .r4_3:   return "4:3"
        case .r16_9:  return "16:9"
        case .r16_10: return "16:10"
        case .r2_35:  return "2.35:1"
        case .r1_1:   return "1:1"
        }
    }
}
