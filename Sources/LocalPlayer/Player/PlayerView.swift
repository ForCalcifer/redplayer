import SwiftUI
import UIKit

/// 全屏播放器界面：画面 + 手势 + 控制层
struct PlayerView: View {
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    /// 当前播放列表（进入播放器时固化，避免播放中列表变动导致错乱）
    private let playlist: [VideoItem]
    private let startIndex: Int

    @State private var currentIndex: Int
    @State private var controlsVisible = true
    @State private var showSettings = false
    @State private var volumeHint: String?
    @State private var seeking = false
    @State private var seekValue: Float = 0
    @State private var idleTimer: Timer?

    private let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0]

    init(engine: PlayerEngine, store: LibraryStore, playlist: [VideoItem], startIndex: Int) {
        self.engine = engine
        self.store = store
        self.playlist = playlist
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // VLC 画面
                VideoSurface(engine: engine)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        engine.togglePlayPause()
                        flashControls()
                    }
                    .onTapGesture(count: 1) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            controlsVisible.toggle()
                        }
                        if controlsVisible { scheduleHideControls() }
                    }
                    // 水平滑动 = 进度；垂直滑动 = 左侧亮度 / 右侧音量
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                handleDragChanged(value, in: geo.size)
                            }
                            .onEnded { value in
                                handleDragEnded(value, in: geo.size)
                            }
                    )

                // 缓冲指示
                if engine.isBuffering {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.6)
                }

                // 手势提示（音量/亮度/进度）
                if let hint = volumeHint {
                    Text(hint)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity)
                }

                // 控制层
                if controlsVisible || !engine.isPlaying {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            playCurrent()
            scheduleHideControls()
        }
        .onDisappear {
            // 画中画激活时保留播放，让用户退回列表后小窗仍继续播
            if !engine.isPiPActive {
                engine.stop()
            }
        }
        .onChange(of: engine.endedToken) { _ in
            handleEnded()
        }
        .sheet(isPresented: $showSettings) {
            PlayerSettingsSheet(engine: engine, store: store)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - 控制界面

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack(spacing: 14) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentItem.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("\(currentIndex + 1) / \(playlist.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()

                // 字幕
                if !engine.subtitleNames.isEmpty {
                    Button { engine.cycleSubtitle() } label: {
                        Image(systemName: "captions.bubble")
                    }
                }
                // 倍速
                Menu {
                    ForEach(speedOptions, id: \.self) { s in
                        Button {
                            engine.setRate(s)
                        } label: {
                            if abs(engine.rate - s) < 0.01 {
                                Label(String(format: "%.2gx", s), systemImage: "checkmark")
                            } else {
                                Text(String(format: "%.2gx", s))
                            }
                        }
                    }
                } label: {
                    Text(String(format: "%.2gx", engine.rate))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 44)
                }
                // 比例
                Menu {
                    ForEach(AspectRatio.allCases) { ratio in
                        Button {
                            engine.apply(aspect: ratio)
                            store.settings.aspectRatio = ratio.rawValue
                            store.saveSettings()
                        } label: {
                            if engine.aspect == ratio {
                                Label(ratio.rawValue, systemImage: "checkmark")
                            } else {
                                Text(ratio.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "rectangle")
                }
                // 画中画（设备支持时才显示）
                if engine.pipSupported {
                    Button { engine.togglePiP() } label: {
                        Image(systemName: engine.isPiPActive ? "rectangle.on.rectangle" : "rectangle.on.rectangle")
                            .foregroundColor(engine.isPiPActive ? .accentColor : .white)
                    }
                }
                // 更多设置
                Button { showSettings = true } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .background(
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
            )

            Spacer()

            // 中央播放控制
            HStack(spacing: 36) {
                Button { playPrevious() } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 26))
                }
                Button { engine.skip(seconds: -10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 30))
                }
                Button {
                    engine.togglePlayPause()
                    scheduleHideControls()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 40))
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.18))
                        .clipShape(Circle())
                }
                Button { engine.skip(seconds: 10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 30))
                }
                Button { playNext() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 26))
                }
            }
            .foregroundColor(.white)
            .padding(.bottom, 18)

            // 底部进度条
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { seeking ? seekValue : engine.position },
                        set: { newValue in
                            seeking = true
                            seekValue = newValue
                            engine.seek(to: newValue)
                            scheduleHideControls()
                        }
                    ),
                    in: 0...1
                )
                .tint(.white)
                .padding(.horizontal, 4)

                HStack {
                    Text(formatTime(engine.currentTime))
                    Spacer()
                    Text(formatTime(engine.duration))
                }
                .font(.system(size: 11, monospacedDigit: true))
                .foregroundColor(.white.opacity(0.75))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            )
        }
        .foregroundColor(.white)
        .buttonStyle(.plain)
    }

    // MARK: - 播放列表导航

    private var currentItem: VideoItem {
        playlist.indices.contains(currentIndex) ? playlist[currentIndex] :
            (playlist.first ?? VideoItem(name: "无视频", bookmark: Data()))
    }

    private func playCurrent() {
        guard playlist.indices.contains(currentIndex) else { return }
        let item = playlist[currentIndex]
        guard let url = item.resolveURL() else { return }
        store.playingID = item.id
        engine.play(
            url: url,
            itemID: item.id,
            startAt: store.settings.rememberPosition ? item.lastPosition : 0,
            settings: store.settings
        )
    }

    private func playNext() {
        let mode = RepeatMode(rawValue: store.settings.repeatMode) ?? .sequential
        if currentIndex + 1 < playlist.count {
            currentIndex += 1
            playCurrent()
        } else if mode == .loopAll {
            currentIndex = 0
            playCurrent()
        } else {
            engine.stop()
            dismiss()
        }
    }

    private func playPrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            currentIndex = playlist.count - 1
        }
        playCurrent()
    }

    private func handleEnded() {
        let mode = RepeatMode(rawValue: store.settings.repeatMode) ?? .sequential
        switch mode {
        case .repeatOne:
            playCurrent()
        case .loopAll, .sequential:
            playNext()
        }
    }

    // MARK: - 手势

    private enum DragAxis { case none, horizontal, volume, brightness }

    @State private var dragAxis: DragAxis = .none
    @State private var dragStartVolume: Float = 0
    @State private var dragStartBrightness: CGFloat = 0
    @State private var dragStartPosition: Float = 0

    private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
        let start = value.startLocation
        let trans = value.translation

        if dragAxis == .none {
            if abs(trans.width) > abs(trans.height) && abs(trans.width) > 12 {
                dragAxis = .horizontal
                dragStartPosition = engine.position
            } else if abs(trans.height) > 12 {
                dragAxis = start.x < size.width / 2 ? .brightness : .volume
                dragStartVolume = engine.volume
                dragStartBrightness = UIScreen.main.brightness
            }
        }

        switch dragAxis {
        case .horizontal:
            let delta = Float(trans.width / size.width)
            seeking = true
            seekValue = min(max(dragStartPosition + delta, 0), 1)
            volumeHint = "⏩ \(formatTime(TimeInterval(seekValue) * engine.duration))"
        case .volume:
            let delta = Float(-trans.height / size.height)
            let v = min(max(dragStartVolume + delta, 0), 1)
            engine.setVolume(v)
            volumeHint = "🔊 \(Int(v * 100))%"
        case .brightness:
            let delta = -trans.height / size.height
            let b = min(max(dragStartBrightness + delta, 0.05), 1)
            UIScreen.main.brightness = b
            volumeHint = "☀️ \(Int(b * 100))%"
        case .none:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, in size: CGSize) {
        if dragAxis == .horizontal {
            engine.seek(to: seekValue)
            seeking = false
        }
        dragAxis = .none
        withAnimation { volumeHint = nil }
        scheduleHideControls()
    }

    // MARK: - 辅助

    private func flashControls() {
        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if self.engine.isPlaying { self.controlsVisible = false }
                }
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite && t >= 0 else { return "00:00" }
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

/// 播放器内呼出的设置面板
struct PlayerSettingsSheet: View {
    @ObservedObject var engine: PlayerEngine
    @ObservedObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("循环模式") {
                    Picker("播放完以后", selection: Binding(
                        get: { store.settings.repeatMode },
                        set: { store.settings.repeatMode = $0; store.saveSettings() }
                    )) {
                        ForEach(RepeatMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.symbol).tag(mode.rawValue)
                        }
                    }
                }

                Section("宽高比") {
                    Picker("画面比例", selection: Binding(
                        get: { engine.aspect },
                        set: { engine.apply(aspect: $0); store.settings.aspectRatio = $0.rawValue; store.saveSettings() }
                    )) {
                        ForEach(AspectRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }
                }

                Section("字幕") {
                    if engine.subtitleNames.isEmpty {
                        Text("当前视频未检测到内嵌字幕，同名字幕文件（.srt/.ass）会被自动加载")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("字幕轨道", selection: Binding(
                            get: { engine.currentSubtitle },
                            set: { engine.selectSubtitle(index: $0) }
                        )) {
                            Text("关闭").tag(-1)
                            ForEach(Array(engine.subtitleNames.enumerated()), id: \.offset) { idx, name in
                                Text(name).tag(idx)
                            }
                        }
                    }
                }

                Section("音轨") {
                    if engine.audioTrackNames.isEmpty {
                        Text("无多音轨")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("音频轨道", selection: Binding(
                            get: { 0 },
                            set: { engine.selectAudioTrack(index: $0) }
                        )) {
                            ForEach(Array(engine.audioTrackNames.enumerated()), id: \.offset) { idx, name in
                                Text(name).tag(idx)
                            }
                        }
                    }
                }

                Section("播放速度") {
                    Picker("默认倍速", selection: Binding(
                        get: { store.settings.defaultRate },
                        set: { engine.setRate($0); store.settings.defaultRate = $0; store.saveSettings() }
                    )) {
                        ForEach([Float]([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]), id: \.self) { s in
                            Text(String(format: "%.2fx", s)).tag(s)
                        }
                    }
                }
            }
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
