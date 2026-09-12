import SwiftUI

@main
struct MyClockPiPApp: App {
    @StateObject private var model = ClockModel()
    var body: some Scene {
        WindowGroup { ClockHome(model: model).preferredColorScheme(.dark) }
    }
}

@MainActor
final class ClockModel: ObservableObject {
    @Published var settings: ClockSettings { didSet { settings.save(); pip.configure(settings); updateAwake() } }
    @Published var syncing = false
    @Published var syncMessage: String?
    @Published var nextSync = Date.distantPast
    let pip = PiPClock()
    private var active = true
    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") { UserDefaults.standard.removeObject(forKey: ClockSettings.storageKey) }
        settings = ClockSettings.load()
        pip.configure(settings)
        updateAwake()
    }
    func sceneChanged(_ phase: ScenePhase) { active = phase == .active; updateAwake() }
    private func updateAwake() { UIApplication.shared.isIdleTimerDisabled = active && settings.keepAwake }
    func synchronize() {
        guard !syncing, Date() >= nextSync else { return }
        syncing = true; syncMessage = nil
        Task {
            do {
                let sample = try await NetworkTime.synchronize()
                pip.clock.calibrate(sample)
                settings.networkTime = true
                syncMessage = String(format: "%@ · 往返 %.0f ms · 偏移 %+.1f ms", sample.host, sample.delay * 1000, sample.offset * 1000)
                nextSync = Date().addingTimeInterval(60)
            } catch {
                syncMessage = "未完成校时：\(error.localizedDescription)。没有有效校时记录时使用设备时间；可换网络重试。"
                nextSync = Date().addingTimeInterval(10)
            }
            syncing = false
        }
    }
}

private let canvas = Color(red: 0.035, green: 0.047, blue: 0.060)
private let surface = Color(red: 0.075, green: 0.090, blue: 0.106)

struct ClockHome: View {
    @ObservedObject var model: ClockModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHelp = false
    @State private var showTarget = false
    @State private var showAdvanced = false
    var accent: Color { model.settings.theme.color }
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 22) {
                        header
                        preview.id("preview")
                        syncCard
                        targetCard
                        appearanceCard
                        Button { showAdvanced = true } label: {
                            HStack {
                                Label("时间与精度设置", systemImage: "slider.horizontal.3")
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold())
                            }.padding(20).background(surface, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain).accessibilityIdentifier("advanced")
                        Text("只做时钟，不代替点击。开抢时间以平台服务器为准。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.bottom, 12)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                    .frame(maxWidth: 650).frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PiPButton(pip: model.pip, accent: accent) {
                        // Start only after the real sample-buffer source is visible on screen.
                        scroll.scrollTo("preview", anchor: .top)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { model.pip.start() }
                    }
                }
            }
        }
        .background(canvas.ignoresSafeArea())
        .tint(accent)
        .sheet(isPresented: $showHelp) { HelpSheet() }
        .sheet(isPresented: $showTarget) { TargetSheet(settings: $model.settings) }
        .sheet(isPresented: $showAdvanced) { AdvancedSheet(settings: $model.settings) }
        .onChange(of: scenePhase) { model.sceneChanged($0) }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("悬刻").font(.system(size: 32, weight: .bold, design: .rounded)).tracking(3)
                Text("EVERY MOMENT MATTERS").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2.3).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showHelp = true } label: {
                Image(systemName: "questionmark").font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40).background(surface, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("使用说明")
        }
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) { Circle().fill(accent).frame(width: 5, height: 5); Text("实时预览") }
                Spacer()
                Text("HH:MM:SS.mmm").font(.system(.caption, design: .monospaced))
            }.font(.caption).foregroundStyle(.secondary)
            ClockPreview(pip: model.pip)
                .aspectRatio(model.settings.layout.aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(0.20), lineWidth: 1))
                .accessibilityLabel("毫秒时钟实时预览")
            Label("悬浮后双指捏合缩放，拖动到屏幕角落", systemImage: "hand.pinch")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var syncCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let reading = model.pip.clock.reading(network: model.settings.networkTime)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: reading.network ? "checkmark.shield" : "clock")
                        .font(.title3).foregroundStyle(reading.network ? accent : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reading.source).font(.subheadline.weight(.semibold))
                        Text(reading.uncertainty.map { String(format: "估计网络不确定度 ±%.0f ms", $0 * 1000) } ?? "尚未验证与网络标准时间的偏差")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button { model.synchronize() } label: {
                        if model.syncing { ProgressView().frame(width: 68) }
                        else { Text(context.date < model.nextSync ? "\(Int(ceil(model.nextSync.timeIntervalSince(context.date))))s" : "立即校时").font(.caption.weight(.semibold)) }
                    }
                    .buttonStyle(.bordered).disabled(model.syncing || context.date < model.nextSync)
                    .accessibilityIdentifier("sync")
                }
                if let message = model.syncMessage { Text(message).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.padding(17).background(surface, in: RoundedRectangle(cornerRadius: 22))
        }
    }
    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("开抢倒计时", systemImage: "flag.checkered").font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("开抢倒计时", isOn: $model.settings.countdownEnabled).labelsHidden().accessibilityIdentifier("countdownToggle")
            }
            Button { showTarget = true } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(targetDescription).font(.system(size: 23, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.65)
                        Text(model.settings.zoneLabel + " · 点此修改日期、时分秒和毫秒").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "pencil").foregroundStyle(accent)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("editTarget")
            HStack(spacing: 10) {
                quickTarget("下一分钟", interval: 60)
                quickTarget("下个整点", interval: 3600)
                Spacer()
                Text("最后 10 秒高亮").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(20).background(surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private var targetDescription: String {
        let formatter = DateFormatter(); formatter.timeZone = model.settings.timeZone
        formatter.dateFormat = "MM/dd  HH:mm:ss.SSS"
        return formatter.string(from: model.settings.target)
    }
    private func quickTarget(_ label: String, interval: Double) -> some View {
        Button(label) {
            let now = model.pip.clock.reading(network: model.settings.networkTime, offsetMilliseconds: model.settings.offsetMilliseconds).epoch
            if interval == 3600 {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = model.settings.timeZone
                model.settings.target = calendar.dateInterval(of: .hour, for: Date(timeIntervalSince1970: now))!.end
            } else { model.settings.target = Date(timeIntervalSince1970: (floor(now / interval) + 1) * interval) }
            model.settings.countdownEnabled = true
        }.font(.caption).buttonStyle(.bordered)
    }
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("你的悬浮样式").font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                ForEach(ClockTheme.allCases) { theme in
                    Button { model.settings.theme = theme } label: {
                        VStack(spacing: 8) {
                            Circle().fill(theme.color).frame(width: 25, height: 25)
                                .padding(7).overlay(Circle().strokeBorder(model.settings.theme == theme ? theme.color : .clear, lineWidth: 1.5))
                            Text(theme.title).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel(theme.title + "配色")
                        .accessibilityAddTraits(model.settings.theme == theme ? .isSelected : [])
                }
            }
            Picker("画面比例", selection: $model.settings.layout) {
                ForEach(ClockLayout.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            VStack(spacing: 9) {
                HStack {
                    Text("数字大小").font(.caption)
                    Spacer()
                    Text("\(Int(model.settings.textScale * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $model.settings.textScale, in: 0.75...1.12, step: 0.01).accessibilityLabel("数字大小")
                Text("此处调整内容字号。悬浮窗本身的大小在画中画中双指缩放。")
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(20).background(surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct PiPButton: View {
    @ObservedObject var pip: PiPClock
    let accent: Color
    let start: () -> Void
    private var busy: Bool { pip.state == .starting || pip.state == .stopping }
    var body: some View {
        VStack(spacing: 8) {
            if let error = pip.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if pip.state == .active { pip.stop() } else { start() }
            } label: {
                HStack(spacing: 10) {
                    if busy { ProgressView().tint(canvas) }
                    else { Image(systemName: pip.state == .active ? "pip.exit" : "pip.enter").font(.title3) }
                    Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
                }.frame(maxWidth: .infinity).frame(height: 56)
                    .foregroundStyle(canvas).background(accent, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).disabled(busy || pip.state == .unsupported).opacity(pip.state == .unsupported ? 0.45 : 1)
                .accessibilityIdentifier("pipButton")
            Text(pip.state == .active ? "现在可以切换到购物 App" : "显示三位毫秒 · 实际刷新受设备与系统限制")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: 650).frame(maxWidth: .infinity).background(.ultraThinMaterial)
    }
    private var title: String {
        switch pip.state {
        case .ready: return "开启悬浮时钟"
        case .starting: return "正在准备画中画…"
        case .active: return "关闭悬浮时钟"
        case .stopping: return "正在关闭…"
        case .unsupported: return "此设备不支持画中画"
        }
    }
}

struct TargetSheet: View {
    @Binding var settings: ClockSettings
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var seconds = 0
    @State private var milliseconds = 0
    var body: some View {
        NavigationStack {
            Form {
                Section("目标时间 · " + settings.zoneLabel) {
                    DatePicker("日期与时间", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, settings.timeZone)
                    Stepper("秒：\(seconds)", value: $seconds, in: 0...59)
                    Stepper("毫秒：\(milliseconds)", value: $milliseconds, in: 0...999)
                    HStack {
                        Text("毫秒输入")
                        TextField("0–999", value: $milliseconds, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Text("保存后自动启用倒计时。到点后显示“时间到”，不会自动跳到明天。过去的时间会显示已开始。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("开抢时间").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save(); dismiss() }.accessibilityIdentifier("saveTarget") }
            }
        }.onAppear {
            date = settings.target
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = settings.timeZone
            seconds = calendar.component(.second, from: date)
            milliseconds = ClockDigits(epoch: date.timeIntervalSince1970, secondsFromGMT: 0).milliseconds
        }
    }
    private func save() {
        let minute = floor(date.timeIntervalSince1970 / 60) * 60
        settings.target = Date(timeIntervalSince1970: minute + Double(seconds) + Double(min(999, max(0, milliseconds))) / 1000)
        settings.countdownEnabled = true
    }
}

struct AdvancedSheet: View {
    @Binding var settings: ClockSettings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("时间来源") {
                    Toggle("使用北京时间", isOn: $settings.beijingTime)
                    Toggle("使用有效的网络校时结果", isOn: $settings.networkTime)
                    Text("关闭北京时间后跟随设备时区。网络校时需在主页手动发起，有效期 15 分钟；过期会明确标注并回退到设备时间。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Text("显示偏移（ms）")
                        TextField("0", value: $settings.offsetMilliseconds, format: .number)
                            .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("offsetInput")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach([-100, -10, -1, 1, 10, 100], id: \.self) { value in
                            Button(value > 0 ? "+\(value)" : "\(value)") {
                                settings.offsetMilliseconds = min(5000, max(-5000, settings.offsetMilliseconds + value))
                            }.font(.caption.monospacedDigit()).buttonStyle(.bordered).frame(maxWidth: .infinity)
                        }
                    }
                    Button("重置偏移为 0") { settings.offsetMilliseconds = 0 }
                } header: { Text("手动微调 · ±5000 ms") } footer: {
                    Text("正数让显示时间提前，负数让显示时间落后。此设置也作用于倒计时；它不能消除购物平台的网络延迟。")
                }
                Section("显示与能耗") {
                    Picker("目标刷新率", selection: $settings.framesPerSecond) {
                        Text("30 FPS · 节能").tag(30)
                        Text("60 FPS · 流畅").tag(60)
                    }
                    Toggle("应用前台保持屏幕常亮", isOn: $settings.keepAwake)
                    Text("60 FPS 每帧约 16.7 ms，30 FPS 每帧约 33.3 ms。三位毫秒代表时间显示精度，不代表 ±1 ms 的对时或端到端响应保证。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("时间与精度").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onChange(of: settings.offsetMilliseconds) { value in
                if !(-5000...5000).contains(value) { settings.offsetMilliseconds = min(5000, max(-5000, value)) }
            }
        }
    }
}

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("三步开始") {
                    Label("按需点“立即校时”，设定开抢时间。", systemImage: "1.circle")
                    Label("点“开启悬浮时钟”，等待小窗出现。", systemImage: "2.circle")
                    Label("切换到购物 App，双指捏合小窗缩放。", systemImage: "3.circle")
                }
                Section("大小与位置") {
                    Text("双指张开放大、捏合缩小；拖动到其他角落，拖向屏幕边缘可暂时隐藏。最小/最大尺寸与位置由 iOS 决定，不能像桌面窗口一样任意拉伸。")
                    Text("主页“数字大小”只改变字号；“横条/卡片”改变画面比例。系统播放控制按钮会在轻点小窗时显示，不能通过公开 API 全部移除。")
                }
                Section("关于精度") {
                    Text("应用每帧重新计算当前时间，不依靠累加定时器计数。支持三位毫秒、30/60 FPS，但系统合成、显示刷新、网络延迟仍会产生误差。")
                    Text("校时使用 SNTP，多源交叉检查。估计不确定度不含屏幕/画中画延迟，也不保证购物平台服务器与标准时间一致。SNTP 未加密认证，不适用于安全敏感的对时。")
                }
                Section("后台与暂停") {
                    Text("悬浮期间不要强制退出本应用。来电、锁屏、系统资源限制或其他视频开启画中画可能中断时钟。暂停时显示“已暂停”，不会让旧时间冒充实时读数。")
                    Text("本应用不录屏、不使用相机或麦克风。只有手动校时时访问三个公共时间服务器；设置保存在本机，不包含广告、统计或购买自动化。")
                }
            }.navigationTitle("使用说明").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
