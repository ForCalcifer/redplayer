import SwiftUI
import UIKit

/// 承载 VLC 画面的 UIView（VLCKit 需要一个 UIView 作为 drawable）
struct VideoSurface: UIViewRepresentable {
    let engine: PlayerEngine

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.contentMode = .redraw
        // VLC 在播放时自动把视频渲染到这个 view 上，方向随系统旋转自动适配
        engine.attach(drawable: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 方向变化时确保 drawable frame 正确
        uiView.setNeedsLayout()
    }
}
