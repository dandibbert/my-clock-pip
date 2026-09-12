import AVKit
import Combine
import SwiftUI

final class PiPClock: NSObject, ObservableObject {
    enum State: Equatable { case ready, starting, active, stopping, unsupported }
    @Published private(set) var state: State = .ready
    @Published private(set) var errorMessage: String?
    let displayLayer = AVSampleBufferDisplayLayer()
    let clock = PreciseClock()
    private var controller: AVPictureInPictureController?
    private var observation: NSKeyValueObservation?
    private var startTimeout: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var foreground = true
    private var issuedStart = false
    private var paused = false
    // These values are only read/written on the rendering queue.
    private let queue = DispatchQueue(label: "clock.frames", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var renderer: FrameRenderer?
    private var configuration = ClockSettings()
    private var renderPaused = false
    private var rendering = false
    private var failures = 0

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        var timebase: CMTimebase?
        if CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase) == noErr,
           let timebase {
            CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(timebase, rate: 1)
            displayLayer.controlTimebase = timebase
        }
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
            let controller = AVPictureInPictureController(contentSource: source)
            controller.delegate = self
            controller.requiresLinearPlayback = true
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            self.controller = controller
            observation = controller.observe(\.isPictureInPicturePossible, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.tryStart() }
            }
        } else { state = .unsupported }
        observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
            guard let self else { return }
            self.foreground = false
            self.setRendering(self.state == .active || self.state == .starting)
        }
        observe(UIApplication.willEnterForegroundNotification) { [weak self] _ in
            guard let self else { return }
            self.foreground = true; self.setRendering(true)
        }
        observe(UIApplication.significantTimeChangeNotification) { [weak self] _ in self?.clock.reset() }
        observe(AVAudioSession.interruptionNotification) { [weak self] notification in
            guard let self, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            self.errorMessage = "画中画被系统音频中断，请回到应用重新开启。"
            self.stop()
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            self?.errorMessage = "系统媒体服务已重置，请重新开启悬浮时钟。"
            self?.stop()
        }
    }
    private func observe(_ name: Notification.Name, using handler: @escaping (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: handler))
    }
    func configure(_ settings: ClockSettings) {
        queue.async { [weak self] in
            guard let self else { return }
            let layoutChanged = self.configuration.layout != settings.layout
            let fpsChanged = self.configuration.framesPerSecond != settings.framesPerSecond
            self.configuration = settings
            if layoutChanged { self.renderer = nil; self.displayLayer.flush() }
            if fpsChanged, self.rendering { self.startTimer() }
        }
    }
    func attachPreview() { setRendering(true) }
    func clearError() { errorMessage = nil }
    func start() {
        guard state == .ready, controller != nil else { return }
        errorMessage = nil; issuedStart = false; paused = false
        queue.async { [weak self] in self?.renderPaused = false; self?.failures = 0 }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            errorMessage = "无法启用画中画音频会话：\(error.localizedDescription)"; return
        }
        state = .starting
        setRendering(true)
        controller?.invalidatePlaybackState()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .starting else { return }
            self.fail("画中画未能启动。请确保时钟预览可见，关闭其他画中画视频，然后重试。")
        }
        startTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: timeout)
        tryStart()
    }
    private func tryStart() {
        guard state == .starting, !issuedStart, let controller, controller.isPictureInPicturePossible else { return }
        issuedStart = true
        controller.startPictureInPicture()
    }
    func stop() {
        startTimeout?.cancel(); startTimeout = nil
        if controller?.isPictureInPictureActive == true || issuedStart {
            state = .stopping; controller?.stopPictureInPicture()
        } else { finishStop() }
    }
    private func fail(_ message: String) {
        errorMessage = message
        controller?.stopPictureInPicture()
        finishStop()
    }
    private func finishStop() {
        startTimeout?.cancel(); startTimeout = nil
        state = controller == nil ? .unsupported : .ready
        issuedStart = false; paused = false
        queue.async { [weak self] in self?.renderPaused = false }
        setRendering(foreground)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
    private func setRendering(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.rendering = enabled
            if enabled { if self.timer == nil { self.startTimer() } }
            else { self.timer?.cancel(); self.timer = nil }
        }
    }
    private func startTimer() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / configuration.framesPerSecond), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            autoreleasepool { self?.render() }
        }
        self.timer = timer; timer.resume()
    }
    private func render() {
        if displayLayer.status == .failed { displayLayer.flush() }
        guard displayLayer.isReadyForMoreMediaData else { return }
        do {
            if renderer == nil { renderer = try FrameRenderer(layout: configuration.layout) }
            let reading = clock.reading(network: configuration.networkTime, offsetMilliseconds: configuration.offsetMilliseconds)
            if let sample = try renderer?.makeFrame(settings: configuration, reading: reading, paused: renderPaused) {
                displayLayer.enqueue(sample)
                failures = 0
            }
        } catch {
            failures += 1
            if failures >= 3 {
                timer?.cancel(); timer = nil; rendering = false
                DispatchQueue.main.async { [weak self] in
                    self?.fail("时钟画面渲染失败，请重新开启。\(error.localizedDescription)")
                    self?.setRendering(false)
                }
            }
        }
    }
    deinit {
        timer?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}

extension PiPClock: AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard state == .starting else { pictureInPictureController.stopPictureInPicture(); return }
        startTimeout?.cancel(); startTimeout = nil
        state = .active; setRendering(true)
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { finishStop() }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        fail("画中画启动失败：\(error.localizedDescription)")
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                   restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(displayLayer.superlayer != nil)
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // Never leave a frozen timestamp looking like a live clock.
        paused = !playing
        queue.async { [weak self] in self?.renderPaused = !playing }
        pictureInPictureController.invalidatePlaybackState()
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { paused }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // The OS owns the outer window. Fixed high-resolution content scales without changing its aspect ratio.
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                   completion completionHandler: @escaping () -> Void) { completionHandler() }
}

private final class ClockPreviewUIView: UIView {
    var videoLayer: AVSampleBufferDisplayLayer?
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer?.frame = bounds
        CATransaction.commit()
    }
}
struct ClockPreview: UIViewRepresentable {
    let pip: PiPClock
    func makeUIView(context: Context) -> UIView {
        let view = ClockPreviewUIView()
        view.backgroundColor = UIColor(red: 0.047, green: 0.059, blue: 0.071, alpha: 1)
        view.videoLayer = pip.displayLayer
        view.layer.addSublayer(pip.displayLayer)
        pip.attachPreview()
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { uiView.setNeedsLayout() }
}
