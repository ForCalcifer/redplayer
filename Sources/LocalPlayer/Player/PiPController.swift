import Foundation
import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import UIKit

/// 画中画桥接器
///
/// VLCKit 3.x 本身不支持系统画中画（PiP），而 iOS 的 PiP 只接受
/// AVPlayerLayer 或 AVSampleBufferDisplayLayer。这里用公开 API 做桥接：
/// 定时从 VLCMediaPlayer 抓一帧 → 转成 CVPixelBuffer/CMSampleBuffer →
/// 塞进 AVSampleBufferDisplayLayer → 交给系统 PiP 显示。
/// 好处是所有 VLC 能播的格式（MKV/RMVB/FLV...）都能用画中画。
final class PiPController: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {

    private weak var engine: PlayerEngine?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var captureTimer: DispatchSourceTimer?
    private var possibleObservation: NSKeyValueObservation?
    private var timebase: CMTimebase?
    private var frameCount: Int64 = 0
    private var wantsStart = false
    /// 缓存最近一帧，VLC 截图异步导致读不到新帧时复用，避免 PiP 闪断
    private var lastImage: UIImage?

    /// 抓帧用的临时文件（覆盖写入）
    private let snapshotURL: URL = {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("localplayer_pip_frame.jpg")
    }()
    /// 画中画小窗足够，限制最大边以降低转换开销
    private let maxSide: CGFloat = 960
    private let fps: Int32 = 15

    private(set) var isActive = false
    /// 画中画激活状态变化回调（0=停止 1=开始）
    var onActiveChanged: ((Bool) -> Void)?

    static var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    init(engine: PlayerEngine) {
        self.engine = engine
        super.init()
        displayLayer.videoGravity = .resizeAspect
        setupController()
        setupTimebase()
    }

    deinit {
        captureTimer?.cancel()
        possibleObservation?.invalidate()
    }

    private func setupController() {
        guard PiPController.isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        pipController = controller

        // layer 有内容后 isPictureInPicturePossible 才会变 true，届时再启动
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) {
            [weak self] pc, _ in
            guard let self else { return }
            if pc.isPictureInPicturePossible && self.wantsStart {
                self.wantsStart = false
                DispatchQueue.main.async { pc.startPictureInPicture() }
            }
        }
    }

    private func setupTimebase() {
        var tb: CMTimebase?
        let status = CMTimebaseCreateWithSourceClock(
            allocator: nil,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &tb
        )
        if status == noErr, let tb {
            timebase = tb
            CMTimebaseSetRate(tb, rate: 0)
        }
    }

    /// 安全设置时间轴速率（timebase 为可选）
    private func setTimebaseRate(_ rate: Float64) {
        guard let tb = timebase else { return }
        CMTimebaseSetRate(tb, rate: rate)
    }

    // MARK: - 对外控制

    func start() {
        guard PiPController.isSupported, let pc = pipController else { return }
        if pc.isPictureInPictureActive { return }
        wantsStart = true
        startCapture()
        // 若系统已判定可用，直接启动；否则等首帧喂入后由 KVO 回调启动
        if pc.isPictureInPicturePossible {
            wantsStart = false
            pc.startPictureInPicture()
        } else {
            // 兜底：1 秒后再试（防止 KVO 未触发）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.wantsStart, let pc = self.pipController,
                      pc.isPictureInPicturePossible else { return }
                self.wantsStart = false
                pc.startPictureInPicture()
            }
        }
    }

    func stop() {
        guard let pc = pipController, pc.isPictureInPictureActive else { return }
        pc.stopPictureInPicture()
    }

    /// seek 后同步 PiP 时间轴，保证小窗进度正确
    func syncTime(to seconds: TimeInterval) {
        guard let tb = timebase else { return }
        CMTimebaseSetTime(tb, time: CMTime(seconds: seconds, preferredTimescale: 600))
        frameCount = Int64(seconds * Double(fps))
    }

    private func startCapture() {
        guard captureTimer == nil else { return }
        // 先立刻抓一帧，让 PiP 窗口一出现就有画面
        captureFrame()
        // GCD 定时器在 App 切后台后仍能触发（配合后台音频权限）
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(fps))
        timer.setEventHandler { [weak self] in
            guard let self, self.engine?.isPlaying == true else { return }
            self.captureFrame()
        }
        timer.resume()
        captureTimer = timer
    }

    private func stopCapture() {
        captureTimer?.cancel()
        captureTimer = nil
    }

    // MARK: - 抓帧 → SampleBuffer

    @objc private func captureFrame() {
        guard let engine, engine.isPlaying else { return }
        // 先删除旧帧：VLC 遇到同名文件可能另起名字，保证读到的是本次新帧
        try? FileManager.default.removeItem(at: snapshotURL)
        engine.captureSnapshot(to: snapshotURL)
        // VLC 截图是异步的，读不到新帧时复用上一帧，防止 PiP 画面闪断
        let image = UIImage(contentsOfFile: snapshotURL.path) ?? lastImage
        guard let image, let pixelBuffer = makePixelBuffer(from: image) else { return }
        lastImage = image

        let pts: CMTime
        if let tb = timebase {
            pts = CMTimebaseGetTime(tb)
        } else {
            pts = CMTime(value: frameCount, timescale: fps)
        }
        frameCount += 1

        guard let buffer = makeSampleBuffer(pixelBuffer: pixelBuffer, pts: pts) else { return }
        if displayLayer.isReadyForMoreMediaData {
            displayLayer.enqueue(buffer)
        }
    }

    private func makePixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let width = max(2, Int(image.size.width * scale))
        let height = max(2, Int(image.size.height * scale))

        var pixelBuffer: CVPixelBuffer?
        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pb),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    private func makeSampleBuffer(pixelBuffer: CVPixelBuffer, pts: CMTime) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        let fdStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard fdStatus == noErr, let fd = formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: fps),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sbStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: fd,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sbStatus == noErr ? sampleBuffer : nil
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        let duration = engine?.duration ?? 0
        return CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        !(engine?.isPlaying ?? false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        guard let engine else { return }
        if playing {
            engine.resume()
            setTimebaseRate(1.0)
        } else {
            engine.pause()
            setTimebaseRate(0)
        }
        pictureInPictureController.invalidatePlaybackState()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        engine?.skip(seconds: Int(CMTimeGetSeconds(skipInterval)))
        if let seconds = engine?.currentTime {
            syncTime(to: seconds)
        }
        completionHandler()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // 小窗尺寸变化无需特殊处理：我们始终以固定尺寸喂帧，系统负责缩放
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        onActiveChanged?(true)
        setTimebaseRate(engine?.isPlaying ?? false ? 1.0 : 0)
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        onActiveChanged?(false)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        stopCapture()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // 播放器界面本来就在（只是切到后台），无需额外恢复
        completionHandler(true)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        onActiveChanged?(false)
        stopCapture()
        print("[LocalPlayer] 画中画启动失败: \(error.localizedDescription)")
    }
}
