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

### 第 3 步：用免费 Apple ID 装到手机（本机 iOS 27.0）

**结论先说**：iOS 27 上 **TrollStore 用不了**（CoreTrust 漏洞在 17.0.1 就被 Apple 修补），只能用证书签名。
推荐 **SideStore**——iOS 27 新增了「无线信任开发者账号」能力，SideStore 能**全程在手机上签名和续签，不用电脑一直开着**。

> ⚠️ **重要前提**：侧载工具更新很快，尤其 iOS 27 很新。安装**务必用官网/官方 GitHub 的最新版**（稳定版不支持就上 nightly），并按工具当前界面操作，别照搬旧教程的菜单名。

#### 推荐：SideStore（手机端签名 + 自动续签）

**准备**
- 一个**备用 Apple ID**（不要用主力号，侧载 App 会绑定签名账号）。
- 把 `LocalPlayer.ipa` 传进手机「文件」App（AirDrop / 网盘 / 数据线都行）。
- 手机先完整备份一次，侧载出错可回滚。

**安装 SideStore（两条路，任选）**

- **路线 1 · 纯手机（iOS 27 无线信任， preferred）**：手机 Safari 打开官网 https://sidestore.io/ ，按当前指引用 SideInstaller / 网页方式安装 SideStore。iOS 27 支持无线信任开发者账号，理论上不用电脑。
- **路线 2 · 电脑首装（更稳，推荐先走这条）**：如果路线 1 装不上，用这台 Windows 电脑 + iLoader（https://github.com/nab138/iloader/releases ）或 SideStore 官方安装器，数据线连手机装一次 SideStore。**只需电脑这一次**，之后续签全在手机。

**首次配置（三条都要做，漏了会闪退）**
1. 设置 → 通用 → **VPN 与设备管理** → 找到签名用的开发者证书 → **信任**。
2. 设置 → 隐私与安全性 → **开发者模式** → 打开 → 按提示重启 → 重启后再确认一次弹窗。
3. 打开 SideStore → 按提示安装它的 **VPN 描述文件**（只在本机工作，不走流量）→ 登录备用 Apple ID → 手动刷新一次 SideStore 自己，确认签名链路通。
   - 若 SideStore 需要配对文件（pairing file）：在电脑上用 **Jitterbugpair** 生成后导入 SideStore，之后即可脱离电脑自签。

**装我们的播放器**
1. 在「文件」App 里找到 `LocalPlayer.ipa` → 共享 → 用 SideStore 打开（或在 SideStore 里点 `+` 选这个 IPA）。
2. SideStore 用你的免费账号签名并安装 → 主屏出现「本地播放器」。
3. 打开就能用。

**续签（7 天一次）**
- 免费证书 7 天到期。到期前：连 Wi-Fi、解锁屏幕，回 SideStore 点 **Refresh** 刷新。
- 保持 SideStore 和播放器都刷新一次；连着 Wi-Fi 且解锁状态成功率最高。
- 配置好后基本就是每周点一下，不用碰电脑。

#### 备选：AltStore Classic（电脑常开才划算，不推荐给你）

AltStore 每次续签都要电脑上的 AltServer 开着且手机同 WiFi。你有 SideStore 就没必要走这条。

> **免费签名硬性限制**：同一个免费 Apple ID 最多注册 3 个 App、每个 App 最多 3 台设备。装之前确认名额，必要时在 设置 → Apple ID → 设备 里注销旧设备。

> **iOS 27 特别提醒**：搜索结果显示 SideStore 稳定版未必明确声明支持 iOS 27，nightly 构建已切到 iOS 27 SDK。若稳定版装不上或登录报错，直接换 nightly / 最新版；登录 503 多为 Apple 服务器临时问题，稍后重试或换网络。

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
