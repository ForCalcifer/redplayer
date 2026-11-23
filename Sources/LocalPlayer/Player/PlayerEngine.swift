import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer
import MobileVLCKit

/// 播放引擎：封装 VLCMediaPlayer，处理状态、进度、倍速、比例、锁屏控制、连续播放
/// 说明：VLCKit 是 Objective-C，回调可能来自任意线程；所有 UI 状态更新均显式切回主线程。
final class PlayerEngine: NSObject, ObservableObject {

    // MARK: - 对外状态
    @Published var isPlaying = false
    @Published var position: Float = 0          // 0...1
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isBuffering = false
    @Published var rate: Float = 1.0
    @Published var aspect: AspectRatio = .auto
    @Published var volume: Float = 1.0
    @Published var videoSize: CGSize = .zero
    @Published var subtitleNames: [String] = []
    @Published var audioTrackNames: [String] = []
    @Published var currentSubtitle: Int = -1   // -1 表示关闭
    /// 播放结束计数（自增触发 UI 侧连续播放，避免闭包持有视图导致循环引用）
    @Published var endedToken: Int = 0
    /// 画中画是否激活
    @Published var isPiPActive = false
    /// 设备是否支持画中画
    let pipSupported = PiPController.isSupported

    private let player: VLCMediaPlayer
    private var timeUpdateTimer: Timer?
    private var lastSavedPosition: TimeInterval = 0
    /// 防止手动 stop/切集时误触发下一集
    private var suppressEndedCallback = false
    private var currentItemID: UUID?
    /// 画中画桥接器（懒加载，避免不支持的设备上初始化 AVKit）
    private lazy var pipController: PiPController? = {
        guard PiPController.isSupported else { return nil }
        let pip = PiPController(engine: self)
        pip.onActiveChanged = { [weak self] active in
            DispatchQueue.main.async { self?.isPiPActive = active }
        }
        return pip
    }()

    // MARK: - 初始化

    override init() {
        player = VLCMediaPlayer()
        super.init()
        player.delegate = self
        configureAudioSession()
        setupRemoteCommands()
    }

    deinit {
        timeUpdateTimer?.invalidate()
        player.stop()
    }

    // MARK: - 渲染视图

    /// 绑定 VLC 的视频输出视图
    func attach(drawable: UIView) {
        player.drawable = drawable
    }

    // MARK: - 播放控制

    /// 加载并播放一个视频
    func play(url: URL, itemID: UUID?, startAt: TimeInterval = 0, settings: PlaybackSettings) {
        suppressEndedCallback = true
        player.stop()

        let media = VLCMedia(url: url)
        player.media = media

        rate = settings.defaultRate
        player.rate = rate

        apply(aspect: AspectRatio(rawValue: settings.aspectRatio) ?? .auto)

        volume = settings.volume
        player.audio?.volume = Int32(max(0, min(1, volume)) * 100)

        currentItemID = itemID
        lastSavedPosition = 0
        _ = player.play()
        suppressEndedCallback = false
        startTimer()
    }

    func togglePlayPause() {
        if player.state == .playing {
            player.pause()
            isPlaying = false
        } else {
            _ = player.play()
            isPlaying = true
        }
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        _ = player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func stop(notifyNext: Bool = false) {
        suppressEndedCallback = !notifyNext
        player.stop()
        isPlaying = false
        position = 0
        currentTime = 0
        stopTimer()
    }

    /// seek 到 0...1
    func seek(to value: Float) {
        guard player.seekable else { return }
        player.position = min(max(value, 0), 1)
        syncPiPTime()
        updateNowPlaying()
    }

    /// 快进/快退 N 秒（正数前进，负数后退）
    func skip(seconds: Int) {
        guard player.seekable, duration > 0 else { return }
        let target = currentTime + TimeInterval(seconds)
        player.position = Float(min(max(target / duration, 0), 1))
        syncPiPTime()
        updateNowPlaying()
    }

    // MARK: - 画中画

    /// 启动/停止画中画
    func togglePiP() {
        guard pipSupported else { return }
        if isPiPActive {
            pipController?.stop()
        } else {
            pipController?.start()
        }
    }

    /// 供 PiP 桥接器抓帧：把当前画面存成图片到指定路径
    func captureSnapshot(to url: URL) {
        // VLCKit 的 snapshot 尺寸参数传 0 表示保持原始尺寸
        player.saveVideoSnapshot(at: url.path, withWidth: 0, andHeight: 0)
    }

    private func syncPiPTime() {
        pipController?.syncTime(to: currentTime)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        player.rate = newRate
        updateNowPlaying()
    }

    /// 设置宽高比
    func apply(aspect newAspect: AspectRatio) {
        aspect = newAspect

        switch newAspect {
        case .auto, .fit:
            player.videoAspectRatio = nil
            player.scaleFactor = 0        // 按视频原始比例适配
        case .fill:
            player.videoAspectRatio = nil
            player.scaleFactor = 1        // 填满屏幕（可能裁切）
        case .stretch:
            // 用当前屏幕比例强制拉伸
            let screen = UIScreen.main.bounds
            let ratio = screen.width / max(screen.height, 1)
            let str = String(format: "%.3f", ratio)
            str.withCString { cString in
                player.videoAspectRatio = UnsafeMutablePointer(mutating: cString)
            }
            player.scaleFactor = 0
        default:
            // 固定比例：withCString 内设置即可，VLC 内部会复制该字符串
            newAspect.vlcValue?.withCString { cString in
                player.videoAspectRatio = UnsafeMutablePointer(mutating: cString)
            }
            player.scaleFactor = 0
        }
    }

    func setVolume(_ value: Float) {
        volume = min(max(value, 0), 1)
        player.audio?.volume = Int32(volume * 100)
    }

    func selectSubtitle(index: Int) {
        currentSubtitle = index
        player.currentVideoSubTitleIndex = Int32(index)
    }

    func cycleSubtitle() {
        guard !subtitleNames.isEmpty else { return }
        let next = currentSubtitle + 1
        selectSubtitle(index: next >= subtitleNames.count ? -1 : next)
    }

    func selectAudioTrack(index: Int) {
        player.currentAudioTrackIndex = Int32(index)
    }

    func refreshTracks() {
        subtitleNames = (player.videoSubTitlesNames as? [String]) ?? []
        audioTrackNames = (player.audioTrackNames as? [String]) ?? []
        videoSize = player.videoSize
    }

    // MARK: - 进度同步

    private func startTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.syncProgress()
        }
    }

    private func stopTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    private func syncProgress() {
        guard player.state == .playing else { return }
        let currentMs = player.time?.value?.doubleValue ?? 0
        let lengthMs = player.media?.length?.value?.doubleValue ?? 0

        currentTime = currentMs / 1000.0
        duration = lengthMs / 1000.0
        if duration > 0 {
            position = Float(currentTime / duration)
        }

        // 首次拿到时长后处理续播
        if duration > 0, let id = currentItemID,
           let item = LibraryStore.shared.items.first(where: { $0.id == id }),
           item.lastPosition > 1, currentTime < 2, lastSavedPosition == 0 {
            let resumeAt = min(max(item.lastPosition, 0), duration)
            player.position = Float(resumeAt / duration)
            lastSavedPosition = resumeAt
        }

        if abs(currentTime - lastSavedPosition) >= 5, let id = currentItemID {
            lastSavedPosition = currentTime
            LibraryStore.shared.updateProgress(id: id, position: currentTime, duration: duration)
        }

        updateNowPlaying()
    }

    // MARK: - 锁屏 / 控制中心

    private func configureAudioSession() {
        // mixWithOthers：视频声音与其他 App 的媒体声音混音叠加、互不打断
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .moviePlayback,
            options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            DispatchQueue.main.async { self.endedToken += 1 }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.skip(seconds: -15)
            return .success
        }
    }

    private func updateNowPlaying() {
        let title = LibraryStore.shared.items.first(where: { $0.id == currentItemID })?.name ?? "本地播放器"
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - VLCMediaPlayerDelegate

extension PlayerEngine: VLCMediaPlayerDelegate {

    func mediaPlayerStateChanged(_ notification: Notification!) {
        let state = player.state
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch state {
            case .playing:
                self.isPlaying = true
                self.isBuffering = false
                self.refreshTracks()
            case .paused:
                self.isPlaying = false
            case .buffering, .opening:
                self.isBuffering = true
            case .ended, .stopped:
                self.isPlaying = false
                self.isBuffering = false
                if !self.suppressEndedCallback {
                    self.handleEnded()
                }
            case .error:
                self.isPlaying = false
                self.isBuffering = false
            default:
                break
            }
            self.updateNowPlaying()
        }
    }

    func mediaPlayerTimeChanged(_ notification: Notification!) {
        // 进度由定时器统一同步，这里不做处理
    }

    private func handleEnded() {
        if let id = currentItemID {
            LibraryStore.shared.clearProgress(id: id)
        }
        endedToken += 1
    }
}
