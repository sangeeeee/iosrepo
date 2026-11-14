# sangeeeee iOS Repo

用于 Sileo、Zebra 等越狱包管理器的个人软件源，采用平面 APT 目录结构。

启用 GitHub Pages 后，软件源地址为：

```text
https://linghe-yang.github.io/iosrepo/
```

## 首次启用

在本仓库的 **Settings → Pages** 中，选择 **Deploy from a branch → main → /(root)**，然后保存。

等待部署完成，确认以下链接可访问，再在设备的包管理器中添加上面的源地址：

- [Release](https://linghe-yang.github.io/iosrepo/Release)
- [Packages](https://linghe-yang.github.io/iosrepo/Packages)

## 当前软件包

| 包标识 | 越狱环境 | 版本 |
| --- | --- | --- |
| `com.gamegod.igg` | 传统越狱，`iphoneos-arm` | `0.8.9.5+noads1` |
| `com.gamegod.igg.rootless` | Rootless，`iphoneos-arm64` | `0.8.9.5+noads1` |
| `com.gamegod.igg.roothide` | Roothide，`iphoneos-arm64e` | `0.8.9.5+noads1` |
| `com.vietanh.overlayiostool` | 传统越狱，`iphoneos-arm` | `5.8.12+lang1`；保留 `5.8.12` |
| `com.vietanh.overlayiostool` | Rootless，`iphoneos-arm64` | `5.8.12+lang1`；保留 `5.8.12` |
| [DEEMO Trainer](sources/DeemoTempo/README.md) | DEEMO 5.0.8 桌面设置、保调变速与区间练习，iOS / iPadOS 15+ Rootless | `0.9~beta4` |
| `com.linghe.shadebar` | Rootless，iOS 16，A12+；桌面 App + 原生 arm64e 组件 | `0.6.0~beta1` |
| `ai.akemi.appsyncunified` | 官方原版镜像，Rootless / `iphoneos-arm64` | `116.0` |
| `com.linghe.pianolab` | Piano Tuner / TuneLab iOS 16 Rootless 移植测试版 | `0.2.2~alpha1` |
| `com.linghe.pianolab.rootful` | Piano Tuner / TuneLab iOS 16 Rootful 移植测试版 | `0.2.2~alpha1` |

上述 iGameGod 包基于官方 0.8.9.5 制作，是本地去广告测试包，并非官方发布。原作者信息和软件包依赖保留在 DEB 中。

修改针对共享框架中的横幅、插屏、定时及闲置广告路径，保留完成回调以继续后续功能。已完成包结构、代码页哈希及局部 ARM64 控制流程模拟检查；尚未完成真实越狱设备运行验证，因此保留 **No Ads TEST** 标记。应按实际越狱环境选择包，不能只按 CPU 类型选择。

OverlayIOSTOOL 来自本地提供的两个 5.8.12 DEB，作者标注为 Viet Anh。对包内全部可执行文件、资源和通信路径做了静态检查，未发现广告组件，未做去广告补丁。原普通版将包架构误标为 `iphoneos-arm64`；本源将其改为传统越狱使用的 `iphoneos-arm`，使两种环境可以区分。保留的 `5.8.12` Rootless DEB 与提供的原文件逐字节一致。

`5.8.12+lang1` 是本地双语测试版：App 和悬浮菜单默认英文，系统首选语言为简体中文（`zh-Hans`，兼容旧标识 `zh-CN` / `zh-SG`）时显示简体中文；繁体中文及其他语言显示英文。覆盖 24 项界面文字，加入相册权限提示及应用显示名称的本地化资源。新增语言组件仅处理已知原版 App 和插件中的指定文字，原有可执行代码段、功能逻辑、通知标识、安装脚本及权限保持不变。组件源码、翻译表和校验记录位于 `sources/OverlayIOSTOOLLocalization/`。

本地校验包含 21 种语言标识、24 组带地址随机化和只读页面的 ARM64 模拟场景、代码页哈希及实际 `dpkg-deb` 读取和解包。模拟中的系统接口由测试替身提供，尚未真机验证 iOS 的实际加载、CoreFoundation 字符串显示和文字布局。原版仍保留，必要时可通过包管理器降级至 `5.8.12`。

对于 **iPad mini 6 / iPadOS 16.1 / Dopamine**，应选择 Rootless 版：ARM64、系统依赖范围和 `/var/jb` 加载路径符合该环境。App 仅声明 iPhone 设备族并限制竖屏，预计通过 iPhone 兼容模式运行；尚未真机验证，不能视为原生 iPad、横屏或分屏适配。

安装 Rootless 双语版 `5.8.12+lang1` 后，重新加载 SpringBoard 并打开 Overlay Tool（简体中文下为“图片浮层”），选择图片测试悬浮显示、拖动和缩放。切换系统首选语言后，需要退出 App 并重新加载 SpringBoard，使 App 和悬浮插件重新读取语言。只有在设备启用越狱及插件注入后，跨应用浮层才有相应运行环境。

## Piano Tuner / TuneLab 钢琴调律应用

本次 **0.2.2~alpha1（构建号 4）** 修复恢复已有偏好设置时的启动闪退，已由真实日志 UUID 和反汇编确认根因。[定位与安装说明](sources/TuneLab/STARTUP_FIX_0.2.2.txt)。可直接覆盖升级，保留用户数据，修复后的真机启动仍待复测。

`0.2.2~alpha1` 修复采音路由变化后未恢复、实际采样转换与停滞检测，新增可点击重试的麦克风电平状态。[修复与验证范围](sources/TuneLab/AUDIO_FIX_0.2.1.txt)。目标反馈设备为 iPad mini 6 / iOS 16.1，新修复仍待真机复测。

现已生成 **`0.2.2~alpha1`（系统版本 0.2.2，构建号 4）** 的真实安装包。使用原版 Piano Tuner 名称、原图标和按钮资源，直接链接原 ARM64 声音核心；保留包标识供 `0.1.0~beta1` 升级。旧版已移至 `retired/`，不再出现在有效索引中。

**这是可安装的开发测试版，完整精准移植仍未完成，也尚未经过 iOS 真机安装、声音和逐页画面对照验收。** PTG 考试、Dropbox 同步及完整校准流程等仍有缺口；各设置页面目前不能视为原 UI 的等价移植。不能把安装包存在或声音样本对照通过解释为全部功能完成。

下载 [Rootless / Dopamine DEB](debs/com.linghe.pianolab_0.2.2~alpha1_iphoneos-arm64.deb) 或 [Rootful DEB](debs/com.linghe.pianolab.rootful_0.2.2~alpha1_iphoneos-arm.deb)，选择符合越狱类型的一种。安装后打开 **Piano Tuner** 并允许使用麦克风。具体范围、限制和构建步骤见 [安装说明](sources/TuneLab/INSTALL_NOTES.txt)。

最终应用镜像已通过 11 段测量音频、704 次模型调用、168 个连续处理块和 12 项原生频谱位图对照；签名、隐私声明、安装路径、安装脚本与包索引检查通过。对照使用相同的外部数学/时钟替身，物理设备验收仍待进行。

[工程说明](sources/TuneLab/README.txt) · [安装包与签名检查](sources/TuneLab/verification/installable_candidate.json) · [完整移植验收状态](sources/TuneLab/verification/fidelity_status.json)。本地打包和索引更新不会自动推送 GitHub Pages；Sileo 线上版本取决于实际发布的索引和 DEB。

## ShadeBar 桌面 App 与遮挡条测试版

`0.6.0~beta1` 新增按应用保存的**遮挡条文字**。入口：桌面 ShadeBar → 应用列表 → 选择应用 → 配置遮挡条文字。开启文字后，每个列表项作为一行，可独立输入内容、选择颜色、字号和字体，支持添加、删除、排序与空行。

水平左/中/右对齐，垂直上/中/下对齐，默认上下左右居中；统一设置行距。字号为固定的 6–200 点，额外行距为 0–100 点。旋转或调整遮挡条宽高时不缩字、不自动换行，超出遮挡条或屏幕边缘的部分直接裁掉。文字随遮挡条一起移动，不吸附屏幕边缘。

字体使用设备字体选择器，默认系统字体；支持 Unicode 多语言文字，具体字形依赖设备字体及系统回退。文字设置仅在桌面 App 中提供，快捷浮窗保留简化选项。文字默认关闭，旧配置继续保留。文字颜色独立于矩形背景不透明度，关闭矩形显示会连同文字隐藏。

保留 32 点可拖动图标（可部分越过屏幕边缘）、跟随设备朝向的快捷面板、10–100% 不透明度与双指调节、1–120% 矩形尺寸，以及按应用保存位置和外观。多任务预览、锁屏和 ShadeBar 设置 App 内隐藏全部浮层。

安装后重载 SpringBoard，再打开 ShadeBar 手动启用总开关。目标环境为 iPad mini 6 / iPadOS 16.1 / Dopamine Rootless。编译、ABI/签名、包检查、九种文字对齐/裁剪、配置容量边界，以及既有触摸和几何测试已通过；新文字界面和多语言实际排版仍需真机确认。

[使用说明与验收步骤](sources/ShadeBar/README.txt) · [安装包](debs/com.linghe.shadebar_0.6.0~beta1_iphoneos-arm64.deb)。旧版 0.3.0 / 0.3.1 / 0.4.0 / 0.5.0 / 0.5.1 / 0.5.2 保留供回退。源码随源发布，工具、SDK 和用户原始日志不随源发布。

## AppSync Unified 官方原版镜像

本源收录作者 [GitHub Release 116.0](https://github.com/akemin-dayo/AppSync/releases/tag/116.0) 发布的 Rootless DEB，适用于普通版 Dopamine 等兼容的 Rootless 越狱环境。针对 iPad mini 6 / iPadOS 16.1，应使用此 `iphoneos-arm64` 版本。本次没有加入 Rootful 或 RootHide 专用包，不代表本包适用于这些环境。

安装包文件名、包标识、版本、作者、依赖、安装脚本和二进制均保留原样；没有重新打包、修改签名或替换载荷。下载后比对本地镜像，文件大小为 49,472 字节，SHA-256 为：

```text
2bdaac72a6d1b006309b7dd28f51b1e3d351d3d8758fc9f08ca670f1d71eb382
```

安装依赖为 `mobilesubstrate (>= 0.9.5100)` 和系统版本 `5.0` 至 `18.2`；这是原包声明的依赖范围，不代表 Rootless 环境支持所有这些旧系统。Rootless 环境还需要 **ElleKit 1.1 或更新版本**，原包通过 `Conflicts: ellekit (< 1.1)` 排除旧版本。依赖继续由设备已有的越狱基础源提供，本源没有镜像整个越狱环境。安装时不要忽略依赖或强制覆盖冲突。

上传本目录全部变更并完成 GitHub Pages 部署后，Sileo / Zebra 将从本源的 `debs/` 下载 AppSync，无需从已失效的 Karen 软件源取得 DEB。原包中的 `Homepage`、`Depiction` 仍指向 `cydia.akemi.ai`；软件详情页可能打不开，但不影响本源索引指定的本地 DEB 下载。

原项目以 **GPL-3.0-or-later** 授权。对应提交的完整源码归档、原始版权声明、GPLv3 全文、上游说明和来源校验记录随本源一同提供：

- [源码归档](sources/AppSyncUnified/AppSync-235aca6cddfbdc9fa87fcb5b2aec2df37ed6d65a.tar.gz)
- [镜像说明](sources/AppSyncUnified/README.txt)
- [原始版权与授权声明](sources/AppSyncUnified/LICENSE) · [GPLv3 全文](sources/AppSyncUnified/COPYING)
- [下载来源与 SHA-256 记录](sources/AppSyncUnified/provenance.json)

这是个人源对官方原版文件的镜像，不是作者官方源。发布时请同时上传 `sources/AppSyncUnified/`，让安装包和对应源码、许可副本一起可供下载。源码提交依据官方 DEB 文件名确定，未进行可复现构建验证。

本地已检查 DEB 结构、Rootless `/var/jb` 安装路径、实际控制信息、原文件一致性及索引校验；尚未在真实 iPad 上安装运行。AppSync 需要越狱和插件注入处于启用状态。若安装后未生效，可按作者说明进行用户空间重启；整机重启后需重新进入越狱。

## 更新软件源

当前 OverlayIOSTOOL DEB 使用 Zstandard 压缩，需要 Python 3.14 或更新版本来读取并更新索引，不依赖额外 Python 包。

1. 将新增或更新的 DEB 放入 `debs/`。
2. 更新包时递增 DEB 内部的 `Version`，例如从 `0.8.9.5+noads1` 更新到 `0.8.9.5+noads2`；只改文件名不会改变包版本。
3. 在仓库目录执行：

```powershell
python tools/update_repo.py
python tools/update_repo.py --check
git add .
git commit -m "Update packages and repository indexes"
git push origin HEAD:main
```

脚本扫描 `debs/` 下的全部 DEB，读取实际控制信息，重新生成 `Packages`、其压缩版本以及 `Release` 中的大小和哈希。不要只上传更新后的 DEB 而保留旧索引。

`--check` 只检查本地文件，不联网、不安装软件。新增 DEB 若使用 Zstandard 压缩控制文件，需要支持该格式的 Python 版本或系统工具。

## 目录说明

- `debs/`：实际安装包。
- `Packages` 及压缩版本：包管理器读取的软件包索引。
- `Release`：软件源名称、支持架构和索引校验信息。
- `.nojekyll`：让 Pages 按静态文件发布。
- `tools/update_repo.py`：索引生成和校验工具。

当前未配置 GPG 仓库签名。DEB 内二进制的本地 ad-hoc 签名与 APT 仓库的 GPG 签名是不同机制。若以后启用 GPG 签名，需要在每次更新 `Release` 后重新签名；本脚本遇到已有签名文件会停止，避免发布过期签名。

## Sileo 提示 Couldn't parse release

`Release` 必须包含 `Components: main`；Sileo 即使面对平面源也会检查该字段。平面源的 `Packages` 仍放在根目录，不需要移动到 `dists/`。更新脚本会生成并校验这个字段。

修复后推送仓库，等待 GitHub Pages 部署完成，再确认线上 `Release` 出现 `Components: main`，然后在 Sileo 中刷新源。若仍保留旧结果，可移除这个源后重新添加。

项目参考：[GitHub Pages 发布设置](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)、[Sileo 官方软件源结构](https://github.com/Sileo/repo)、[iGameGod 官网](https://igamegod.app/)。
