# 悬刻 · My Clock PiP

简洁的原生 iOS **毫秒画中画时钟**。SwiftUI + AVKit，没有第三方运行时依赖，没有广告、账户、录屏或自动点击。

## 功能

- 一键画中画，在其他 App 上方显示 `HH:mm:ss.SSS`；数字采用等宽排版，毫秒独立强调。
- 使用 iOS 原生双指手势缩放、拖动移位；横条/卡片两种画面比例、75%–112% 内容字号。
- 薄荷、冰蓝、琥珀、纯白配色；30/60 FPS 目标刷新率。
- 默认北京时间，也可跟随设备时区。目标时间按绝对日期保存，支持秒和毫秒、下一分钟/下个整点快捷设置。
- 开抢倒计时，最后 10 秒高亮，到点明确显示「时间到」，之后显示已开始时长，不会跳到明天。
- 手动 SNTP 校时：三个公共服务器并发取样，至少两个来源相符才采纳；显示 RTT、偏移与估计不确定度。
- ±5000 ms 手动显示偏移，1/10/100 ms 步进；明确区分时间来源和手动调整。
- 真正的实时帧渲染，而不是预录视频。后台渲染不依赖 SwiftUI TimelineView 或前台 CADisplayLink。

## 下载与安装

仓库 **Actions → iOS Build → 成功的运行 → Artifacts → MyClockPiP-unsigned**。

压缩包包含已编译的 `MyClockPiP-unsigned.ipa`、SHA-256 和安装说明。**未签名 IPA 需要有效签名后才能在普通 iOS 设备安装**；没有 Apple 证书时 CI 仍能构建，不会把未签名包冒充可直接安装包。详细说明见 [INSTALL.md](INSTALL.md)。

最低系统：**iOS/iPadOS 16.0**。构建完全可以由 GitHub Actions 完成，使用者不必下载代码在本地编译。

## 真实边界

**毫秒显示 ≠ 每毫秒刷新 ≠ ±1 ms 对时。** 60 FPS 每帧约 16.7 ms；PiP 合成、设备刷新和负载可能增加延迟。网络不确定度只是估算，不含屏幕显示链路延迟。购物平台时间也可能不同；本应用不保证抢购结果。

**窗口外框由 iOS 管理。** 本项目没有假装能通过滑块指定系统 PiP 的任意宽高。双指缩放改变外框；字号滑块只改变内容；画面比例影响窗口形状，最终尺寸限制由系统决定。不使用 `controlsStyle` KVC、私有 API 或伪造视频通话权限。

**校时是可选且有限期的。** 默认不开网络请求，只有点击「立即校时」才访问 `time.apple.com`、`time.cloudflare.com` 和 `ntp.aliyun.com` 的 UDP/123。成功后冷却 60 秒，失败后 10 秒；校时有效期 15 分钟，过期明确回退设备时间。开抢前重新校时，不建议在临界几秒切换来源。SNTP 未使用 NTS 认证，不适合安全敏感场景。

**后台不是无限保活。** 活跃的画中画负责后台视频播放；退出画中画且应用进入后台后立即停掉渲染。强制退出、锁屏、来电或其他画中画可能中断。暂停时隐藏数字，改为「已暂停」，避免冻结读数误导操作。不通过循环静音音频偷偷延长保活。

## 结构

| 路径 | 作用 |
| --- | --- |
| `Sources/ClockCore` | 纯 Foundation 时间运算、SNTP 编解码、校时选择与线程安全时间锚点 |
| `App/TimeSync.swift` | 有超时、取消与单次完成保护的 UDP 查询 |
| `App/FrameRenderer.swift` | 有界 CVPixelBufferPool、实时时间绘制与 CMSampleBuffer |
| `App/PiPClock.swift` | PiP 状态机、音频会话、前后台生命周期与独立渲染队列 |
| `App/ClockApp.swift` | SwiftUI 中文界面、设置、倒计时与使用说明 |
| `Tests/ClockCoreTests` | 可在 Linux/macOS 执行的计时/协议单元测试 |
| `AppTests` / `UITests` | 苹果平台帧渲染和 UI 冒烟测试 |
| `.github/workflows/ios.yml` | macOS 云端测试、模拟器截图、真机架构编译与 IPA 打包 |

每帧采样当前时间，不累加定时器间隔。校时后以 `mach_continuous_time` 锚定时间，包含休眠经过时间。四时间戳计算使用单调耗时重建接收时刻，避免请求过程中设备校时破坏 RTT。校验报文长度、版本/模式、stratum、leap、请求回显、时间戳、往返时延和源间差异；处理 2036 年 NTP era 回绕。

渲染使用最多 6 个池化缓冲区；系统消费不及时就丢帧，不排队播放过期时间。帧标记立即展示、直播时间范围无限，禁止跳转。目标刷新率不等于保证实际帧率。

## 开发与验证

可选的开发者本机构建（终端位于仓库目录）：

```sh
swift test
brew install xcodegen
swift scripts/GenerateIcon.swift
xcodegen generate
open MyClockPiP.xcodeproj
```

工程文件和完整图标集可重复生成；没有外部 Swift Package 依赖。Xcode 需要 iOS 16 或更新 SDK。签名团队由使用者自己的开发环境配置，勿提交证书/私钥。

CI 包括纯逻辑测试、图像像素变化测试、暂停不显示旧时间、有界缓冲池、样式/倒计时分支渲染和 UI 导航测试。模拟器成功不等于实机 PiP 验收通过。

### 实机验收清单

- 开启 PiP，切换购物 App 持续运行 10 分钟，确认毫秒仍更新。
- 双指缩放、拖动四角、收起/恢复、横竖屏与 iPad 分屏；检查字号与内容是否裁切。
- 暂停/播放、关闭/重开、返回主 App、来电/音频打断后重新开启。
- 断网、UDP 被阻止、时间源切换、校时过期、手动 ±1/10/100 ms。
- 午夜、跨天目标、最后 10 秒、临界归零、已开始状态。
- 低电量、热降频、同时播放音乐、其他 App 开启 PiP；观察电量/温度和系统限制。

## 参考

- [Apple：iPhone 画中画手势](https://support.apple.com/guide/iphone/iphcc3587b5d/ios)
- [Apple WWDC21：Sample Buffer Picture in Picture](https://developer.apple.com/videos/play/wwdc2021/10290/)
- [RFC 5905：NTP v4 / SNTP](https://www.rfc-editor.org/rfc/rfc5905.html)
