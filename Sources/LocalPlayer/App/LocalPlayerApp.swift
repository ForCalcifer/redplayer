import SwiftUI

@main
struct LocalPlayerApp: App {
    @StateObject private var store = LibraryStore.shared

    var body: some Scene {
        WindowGroup {
            LibraryView(store: store)
                // 支持 iPad 分屏，同时保持横竖屏自由旋转（Info.plist 已声明）
        }
    }
}
