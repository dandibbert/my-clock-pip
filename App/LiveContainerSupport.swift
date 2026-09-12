import SwiftUI

/// Runtime hints injected by LiveContainer before the guest app starts.
/// LiveProcess sets LP_HOME_PATH and LiveContainer bootstrap sets LC_HOME_PATH.
enum LiveContainerRuntime {
    static func detect(environment: [String: String], arguments: [String]) -> Bool {
        if arguments.contains("--disable-livecontainer") { return false }
        if arguments.contains("--force-livecontainer") { return true }
        return environment["LC_HOME_PATH"] != nil || environment["LP_HOME_PATH"] != nil
    }

    static var isDetected: Bool {
        detect(environment: ProcessInfo.processInfo.environment,
               arguments: ProcessInfo.processInfo.arguments)
    }

    static var isForcedForTesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--force-livecontainer")
    }
}

private let lcCanvas = Color(red: 0.035, green: 0.047, blue: 0.060)
private let lcSurface = Color(red: 0.075, green: 0.090, blue: 0.106)

/// Selects the correct PiP strategy without changing the normal standalone experience.
struct ClockRoot: View {
    @ObservedObject var model: ClockModel
    @AppStorage("liveContainer.preferNativePiP") private var preferNativePiP = false

    private var shouldUseLiveContainerMode: Bool {
        LiveContainerRuntime.isDetected && (!preferNativePiP || LiveContainerRuntime.isForcedForTesting)
    }

    var body: some View {
        Group {
            if shouldUseLiveContainerMode {
                LiveContainerHome(model: model) {
                    preferNativePiP = true
                }
            } else {
                ClockHome(model: model)
                    .overlay(alignment: .topLeading) {
                        if LiveContainerRuntime.isDetected {
                            Button {
                                preferNativePiP = false
                            } label: {
                                Label("LC 模式", systemImage: "rectangle.on.rectangle")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11).padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 12).padding(.top, 8)
                            .accessibilityIdentifier("restoreLCMode")
                        }
                    }
            }
        }
    }
}

private struct LiveContainerHome: View {
    @ObservedObject var model: ClockModel
    @Environment(\.scenePhase) private var scenePhase
    let useNativePiP: () -> Void

    @State private var stageMode = false
    @State private var showTarget = false
    @State private var showAdvanced = false
    @State private var showHelp = false

    private var accent: Color { model.settings.theme.color }

    var body: some View {
        Group {
            if stageMode {
                LiveContainerClockStage(model: model) { stageMode = false }
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 18) {
                            header
                            preview
                            syncCard
                            settingsCard
                            launchCard
                            Button("改用 App 自带原生 PiP") { useNativePiP() }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
                        .frame(maxWidth: 650).frame(maxWidth: .infinity)
                    }
                    .background(lcCanvas.ignoresSafeArea())
                    .tint(accent)
                }
            }
        }
        .sheet(isPresented: $showTarget) { TargetSheet(settings: $model.settings) }
        .sheet(isPresented: $showAdvanced) { AdvancedSheet(settings: $model.settings) }
        .sheet(isPresented: $showHelp) { LiveContainerHelp() }
        .onChange(of: scenePhase) { model.sceneChanged($0) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("悬刻").font(.system(size: 31, weight: .bold, design: .rounded)).tracking(3)
                HStack(spacing: 7) {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text("LiveContainer 兼容模式")
                        .font(.caption.weight(.semibold)).foregroundStyle(accent)
                        .accessibilityIdentifier("lcDetectedLabel")
                }
            }
            Spacer()
            Button { showHelp = true } label: {
                Image(systemName: "questionmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40).background(lcSurface, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("LiveContainer 使用说明")
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ClockPreview(pip: model.pip)
                .aspectRatio(model.settings.layout.aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(0.20), lineWidth: 1))
                .accessibilityLabel("LiveContainer 毫秒时钟预览")
            Text("这里不再调用 guest App 自己的 PiP。进入纯时钟画面后，用 LiveContainer 的 Multitask / PiP 把整个窗口悬浮出去。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var syncCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let reading = model.pip.clock.reading(network: model.settings.networkTime)
            HStack(spacing: 12) {
                Image(systemName: reading.network ? "checkmark.shield.fill" : "clock")
                    .foregroundStyle(reading.network ? accent : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reading.source).font(.subheadline.weight(.semibold))
                    Text(reading.uncertainty.map { String(format: "估计网络不确定度 ±%.0f ms", $0 * 1000) } ?? "尚未完成网络校时")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    model.synchronize()
                } label: {
                    if model.syncing { ProgressView().frame(width: 64) }
                    else { Text(context.date < model.nextSync ? "\(Int(ceil(model.nextSync.timeIntervalSince(context.date))))s" : "立即校时") }
                }
                .font(.caption.weight(.semibold)).buttonStyle(.bordered)
                .disabled(model.syncing || context.date < model.nextSync)
            }
            .padding(17).background(lcSurface, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            Button { showTarget = true } label: {
                row(icon: "flag.checkered", title: "开抢时间与倒计时", subtitle: model.settings.countdownEnabled ? "已启用" : "未启用")
            }
            Divider().padding(.leading, 48)
            Button { showAdvanced = true } label: {
                row(icon: "slider.horizontal.3", title: "时间、偏移与刷新率", subtitle: "\(model.settings.framesPerSecond) FPS")
            }
            Divider().padding(.leading, 48)
            HStack(spacing: 11) {
                Image(systemName: "paintpalette").frame(width: 25).foregroundStyle(accent)
                Text("配色").font(.subheadline.weight(.medium))
                Spacer()
                ForEach(ClockTheme.allCases) { theme in
                    Button { model.settings.theme = theme } label: {
                        Circle().fill(theme.color).frame(width: 21, height: 21)
                            .padding(4)
                            .overlay(Circle().strokeBorder(model.settings.theme == theme ? theme.color : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain).accessibilityLabel(theme.title + "配色")
                }
            }.padding(16)
        }
        .buttonStyle(.plain)
        .background(lcSurface, in: RoundedRectangle(cornerRadius: 22))
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).frame(width: 25).foregroundStyle(accent)
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }.padding(16)
    }

    private var launchCard: some View {
        VStack(spacing: 10) {
            Button {
                stageMode = true
            } label: {
                Label("进入 LiveContainer 悬浮画面", systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(lcCanvas)
                    .background(accent, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain).accessibilityIdentifier("lcDisplayButton")
            Text("进入后等待顶部提示自动消失，再从 LiveContainer 的 Multitask 窗口启动 PiP。悬浮窗大小仍由系统双指缩放。")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(16).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(accent.opacity(0.16), lineWidth: 1))
    }
}

private struct LiveContainerClockStage: View {
    @ObservedObject var model: ClockModel
    let close: () -> Void
    @State private var showChrome = true
    @State private var chromeGeneration = 0

    private var accent: Color { model.settings.theme.color }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                lcCanvas.ignoresSafeArea()
                ClockPreview(pip: model.pip)
                    .aspectRatio(model.settings.layout.aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(model.settings.layout == .strip ? 4 : 10)

                if showChrome {
                    VStack {
                        HStack(spacing: 10) {
                            Label("LC 悬浮画面", systemImage: "rectangle.on.rectangle")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button(action: close) {
                                Label("返回设置", systemImage: "xmark")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11).padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }.buttonStyle(.plain).accessibilityIdentifier("lcStageClose")
                        }
                        .padding(.horizontal, 16).padding(.top, 12)
                        Spacer()
                        Text("现在使用 LiveContainer 外层 PiP · 轻点画面可重新显示控制")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 12)
                    }
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.16)) { showChrome.toggle() }
                if showChrome { scheduleChromeHide() }
            }
            .onAppear { scheduleChromeHide() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("lcDisplayStage")
        }
        .background(lcCanvas.ignoresSafeArea())
        .tint(accent)
        .statusBarHidden(!showChrome)
    }

    private func scheduleChromeHide() {
        chromeGeneration += 1
        let generation = chromeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard generation == chromeGeneration else { return }
            withAnimation(.easeOut(duration: 0.22)) { showChrome = false }
        }
    }
}

private struct LiveContainerHelp: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("为什么要这个模式") {
                    Text("LiveContainer 中的 guest App 不是独立安装进程。悬刻不再从 guest 内部启动第二个系统 PiP，而是把实时钟面留在 guest 窗口里，交给 LiveContainer 自己的 Multitask PiP 悬浮。")
                }
                Section("推荐步骤") {
                    Label("在 LiveContainer 中用 Multitask 打开悬刻。", systemImage: "1.circle")
                    Label("在悬刻里校时、设好倒计时，点“进入 LiveContainer 悬浮画面”。", systemImage: "2.circle")
                    Label("等控制提示自动隐藏，再使用 LiveContainer 窗口的 PiP。", systemImage: "3.circle")
                    Label("进入购物 App 后，用 iOS 双指手势调节悬浮窗大小。", systemImage: "4.circle")
                }
                Section("提示") {
                    Text("如果你当前版本的 LiveContainer 没有 Multitask/PiP 控件，请先升级 LiveContainer。不同版本的按钮位置可能不同。")
                    Text("如果想验证 guest 内原生 PiP 是否恢复，可在兼容模式主页底部切换到 App 自带 PiP；左上角会保留“LC 模式”返回入口。")
                }
            }
            .navigationTitle("LiveContainer 模式").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
