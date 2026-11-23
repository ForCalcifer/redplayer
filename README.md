# 本地播放器（iOS · 自己用）

一个纯本地 iOS 视频播放器，基于 **VideoLAN 官方 VLCKit 内核**。不上 App Store，用免费 Apple ID 侧载到自己手机上。

## 功能

| 需求 | 实现 |
|---|---|
| 横屏竖屏都能播放 | App + 播放器全支持自动旋转，画面随方向自适应 |
| 什么格式都能播 | VLCKit 全解码：MKV / AVI / MP4 / MOV / FLV / TS / WebM / RMVB / WMV / MPG / 3GP 等 |
| 播放倍数 | 0.5x ~ 3.0x，播放中随时切换，也可设默认值 |
| 高宽比 | 自动 / 适应 / 填充 / 拉伸 / 4:3 / 16:9 / 16:10 / 2.35:1 / 1:1 |
| 播放列表 | 多选导入、搜索、排序、重命名、删除、续播进度记忆 |
| 自动连续播放 | 顺序 / 列表循环 / 单集循环 |
| 画中画 | 播放器顶部 `矩形叠放` 按钮开启，所有格式（含 MKV/RMVB）都能小窗播放，支持小窗内播放/暂停/快进 |
| 声音混音 | 画中画/后台播放时，视频声音与音乐等其他 App 媒体声音**叠加同时响、互不打断** |
| 常规播放器功能 | 播放暂停、 ±10 秒、拖动进度、音量、亮度、字幕/音轨切换、后台播放、锁屏控制中心、同名字幕自动加载 |
| 手势 | 双击播放暂停、单击显隐控制、左右滑调进度、右半屏上下滑调音量、左半屏上下滑调亮度 |

### 关于画中画的实现说明

iOS 的系统画中画只接受系统播放器（AVPlayer）的画面，而 VLCKit 3.7 是全格式解码内核、走自己的渲染。这里用**截图桥接**方式：定时把 VLC 当前画面抓成一帧，喂给系统画中画窗口。

- **优点**：全格式都能画中画，且只用苹果公开 API，稳定、不需特殊权限。
- **代价**：小窗画面是 15 帧/秒抓帧模拟的，对比原生画中画有约 1 帧延迟，且会多耗一点电（自用完全可接受）。
- 开启画中画后可以直接退回视频列表，小窗会继续播放；点小窗可回到 App。

---

## 从零到装上手机（全程不需要 Mac）

整体链路：

```
把本目录传到 GitHub
  → GitHub Actions 云编译出未签名 IPA
  → 下载 IPA
  → 用 AltStore / SideStore 以免费 Apple ID 签名装到手机
```

### 第 1 步：建 GitHub 仓库并把代码传上去

> 本地的 `git init` 和首次 `commit` **已经帮你做好了**（15 个文件 / 2140 行已入库），你只需建仓库 + 推送，两步：

1. 打开 https://github.com/new 新建一个**私有仓库**（Private 即可，Actions 免费额度对私有仓库也够用）。名字随意，比如 `localplayer`。**不要勾选** README / license / .gitignore，保持空仓库。

2. 双击本目录里的 **`一键推送到GitHub.cmd`**，按提示粘贴第 1 步建好的仓库 HTTPS 地址（形如 `https://github.com/你的用户名/localplayer.git`），回车。脚本会自动设置远程并推送。首次推送会弹出浏览器让你登录 GitHub，登录一次以后就不用了。

   > 想手动敲命令也可以（本目录已 init + commit 好，不用再做）：
   > ```powershell
   > cd D:\你的路径\LocalPlayer
   > git remote add origin https://github.com/你的用户名/localplayer.git
   > git branch -M main
   > git push -u origin main
   > ```

   > 注意：`.github` 是隐藏目录，首次提交时已经包含进去了，不用管。

### 第 2 步：等 GitHub Actions 编译

1. 打开仓库网页 → 顶部 **Actions** 标签。
2. 会看到正在运行的 **「编译本地播放器 IPA」**。推送代码会自动触发；也可点 `Run workflow` 手动触发。
3. 等 10~20 分钟（首次要下载约 100MB 的 VLCKit）。全部变绿 ✅ 后，点进这次运行。
4. 页面底部 **Artifacts** 里找到 `LocalPlayer-IPA`，点下载，解压得到 `LocalPlayer.ipa`。

   > 若编译失败：点进去看红色步骤的日志，把报错发给我即可。

### 第 3 步：用免费 Apple ID 装到手机（二选一）

免费 Apple ID 签名**7 天过期**，需要定期刷新。两种方式：

#### 方式 A：AltStore（需要一台 Windows 电脑，最稳）

1. 电脑上安装 AltServer（windows 版）：https://altstore.io/
2. 手机上安装 **AltStore** App（按官网指引，用电脑上的 AltServer + WiFi 安装）。
3. 打开 AltStore → 设置里登录你的 **Apple ID**（建议专门注册一个，开启两步验证，用到 App 专用密码）。
4. 把下载好的 `LocalPlayer.ipa` 用数据线/隔空投送/AirDrop 传到手机「文件」App。
5. 在 AltStore 的 **My Apps** 页 → 左上角 `+` → 选择 `LocalPlayer.ipa` → 它会自动用你的免费账号签名并安装。
6. 以后每 7 天：保持电脑 AltServer 运行 + 手机同 WiFi，AltStore 里点 **Refresh All** 即可续签。

#### 方式 B：SideStore（纯手机侧载，不依赖电脑，适合懒得开电脑）

SideStore 可以完全在手机上签名和续签（需配合 StikDebug/Jitterless 等方案做首次激活，按最新教程走）。

1. 用手机 Safari 打开 SideStore 官网获取安装方式：https://sidestore.io/
2. 按指引用你的免费 Apple ID 安装 SideStore。
3. 打开 SideStore → 登录 Apple ID → 选择 `LocalPlayer.ipa` 安装。
4. SideStore 支持定时自动续签，配置好后基本不用管。

> 免费签名的硬性限制：同一个免费 Apple ID 最多注册 3 个 App、每个 App 最多 3 台设备。装之前确认名额，必要时注销旧设备（Settings → 你的 Apple ID → 设备）。

### 第 4 步：把视频放进 App

三种方式任选：

1. **文件 App 导入**：打开播放器点 `+` → 从「文件」App 选视频（可多选）。
2. **共享菜单**：在「文件」App 里长按视频 → 共享 → 选择「本地播放器」。
3. **数据线（最快传大量视频）**：用 Finder/iTunes 的「文件共享」把视频拖进本 App 的文档目录；App 启动时会**自动扫描并加入列表**。

> 视频只存在你手机本地，不上传任何服务器。

---

## 常见问题

**Q：提示"未受信任的企业级开发者" / 打不开？**
设置 → 通用 → VPN 与设备管理 → 选你的 Apple ID → 信任。

**Q：7 天后打不开？**
免费证书到期了，按上面第 3 步刷新签名（AltStore 的 Refresh All / SideStore 自动续签）。

**Q：某些 MKV 没声音 / 字幕不显示？**
VLCKit 支持绝大多数编码；极少数特殊编码（如某些 DTS-HD、TrueHD）会降级。字幕请把 `.srt` / `.ass` 和视频放同目录、改成**同名**，会自动加载。也可在播放器里手动选字幕轨道。

**Q：GitHub Actions 编译要钱吗？**
公开仓库免费；私有仓库每月有 2000 分钟免费额度，这个项目编译一次约 10~20 分钟，个人用完全够。

**Q：能上架吗？**
能，但你的定位是自己用。上架需要付费开发者账号 + 审核，且 VLCKit 是 LGPL 协议要遵守开源义务，自用无所谓。

---

## 工程结构

```
LocalPlayer/
├── project.yml                    # XcodeGen 工程描述
├── Podfile                        # MobileVLCKit 依赖
├── .github/workflows/build.yml    # 云编译脚本
└── Sources/LocalPlayer/
    ├── App/LocalPlayerApp.swift   # 入口
    ├── Models/
    │   ├── VideoItem.swift        # 视频条目 / 书签 / 设置模型
    │   └── LibraryStore.swift     # 播放列表持久化
    ├── Player/
    │   ├── PlayerEngine.swift     # VLC 播放内核（倍速/比例/锁屏/连续播放/混音）
    │   ├── PiPController.swift    # 画中画桥接（抓帧 → 系统 PiP 窗口）
    │   ├── VideoSurface.swift     # VLC 画面承载视图
    │   └── PlayerView.swift       # 播放器 UI + 全套手势 + PiP 按钮
    ├── Library/
    │   ├── LibraryView.swift      # 播放列表首页
    │   └── SettingsView.swift     # 设置
    └── Supporting/Info.plist      # 方向/文件共享/后台播放声明
```

技术栈：SwiftUI + UIKit + MobileVLCKit 3.7（VideoLAN 官方）. iOS 16.0+。
