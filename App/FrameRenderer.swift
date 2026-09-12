import AVFoundation
import UIKit

/// Renders actual current time directly into pooled pixel buffers, not a prerecorded video or a screen capture.
final class FrameRenderer {
    enum RenderError: Error { case pool, buffer, context, format, sample }
    private let width: Int
    private let height: Int
    private let pool: CVPixelBufferPool
    private var format: CMVideoFormatDescription?
    init(layout: ClockLayout) throws {
        width = layout.width; height = layout.height
        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary,
            attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else { throw RenderError.pool }
        self.pool = pool
    }
    func makeFrame(settings: ClockSettings, reading: ClockReading, paused: Bool) throws -> CMSampleBuffer? {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool,
            [kCVPixelBufferPoolAllocationThresholdKey as String: 6] as CFDictionary, &buffer)
        if result == kCVReturnWouldExceedAllocationThreshold { return nil } // Drop; never accumulate latency.
        guard result == kCVReturnSuccess, let buffer else { throw RenderError.buffer }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw RenderError.buffer }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
              bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            throw RenderError.context
        }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        paint(context, settings: settings, reading: reading, paused: paused)
        UIGraphicsPopContext()
        if format == nil {
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                              formatDescriptionOut: &format) == noErr else { throw RenderError.format }
        }
        guard let format else { throw RenderError.format }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(settings.framesPerSecond)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
              formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { throw RenderError.sample }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
    private func paint(_ context: CGContext, settings: ClockSettings, reading: ClockReading, paused: Bool) {
        let w = CGFloat(width), h = CGFloat(height)
        let foreground = UIColor(white: 0.96, alpha: 1)
        let secondary = UIColor(white: 0.57, alpha: 1)
        let accent = settings.theme.uiColor
        context.setFillColor(UIColor(red: 0.047, green: 0.059, blue: 0.071, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let source = reading.source + (settings.offsetMilliseconds == 0 ? "" : " · 手动偏移")
        text(settings.zoneLabel + "  /  " + source, rect: CGRect(x: 38, y: 26, width: w - 76, height: 36),
             size: 25, color: reading.network ? accent : secondary, alignment: .left)
        if paused {
            text("已暂停", rect: CGRect(x: 38, y: h * 0.30, width: w - 76, height: h * 0.35), size: 100, color: foreground)
            text("点画中画的播放按钮，恢复实时计时", rect: CGRect(x: 38, y: h * 0.74, width: w - 76, height: 52), size: 32, color: accent)
            return
        }
        let date = Date(timeIntervalSince1970: reading.epoch)
        let digits = ClockDigits(epoch: reading.epoch, secondsFromGMT: settings.timeZone.secondsFromGMT(for: date))
        clockText(main: digits.main, fraction: digits.fraction, centerY: h * 0.43,
                  available: w - 70, scale: settings.textScale, foreground: foreground, accent: accent)
        if settings.countdownEnabled {
            let remaining = settings.target.timeIntervalSince1970 - reading.epoch
            let reached = remaining <= 0
            let label: String
            if reached {
                label = remaining > -5 ? "时间到  ·  现在出发" : "已开始  +" + Countdown.text(milliseconds: Int64(-remaining * 1000))
            } else {
                label = "距开抢  " + Countdown.text(milliseconds: Countdown.milliseconds(target: settings.target.timeIntervalSince1970, now: reading.epoch))
            }
            let urgent = remaining <= 10 && remaining > -5
            let color = urgent ? UIColor(red: 1, green: 0.52, blue: 0.44, alpha: 1) : accent
            let rect = CGRect(x: 38, y: h * 0.72, width: w - 76, height: h * 0.17)
            context.setFillColor(color.withAlphaComponent(urgent ? 0.17 : 0.08).cgColor)
            context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 20).cgPath); context.fillPath()
            text(label, rect: rect.insetBy(dx: 12, dy: 10), size: settings.layout == .strip ? 39 : 47, color: color)
        } else {
            text("让每一刻，刚刚好。", rect: CGRect(x: 38, y: h * 0.74, width: w - 76, height: 50), size: 31, color: secondary)
        }
        let track = CGRect(x: 40, y: h - 17, width: w - 80, height: 5)
        context.setFillColor(accent.withAlphaComponent(0.10).cgColor); context.fill(track)
        context.setFillColor(accent.cgColor)
        context.fill(CGRect(x: track.minX, y: track.minY, width: track.width * CGFloat(digits.milliseconds) / 1000, height: track.height))
    }
    private func clockText(main: String, fraction: String, centerY: CGFloat, available: CGFloat,
                           scale: Double, foreground: UIColor, accent: UIColor) {
        var size = 124 * CGFloat(scale)
        func make(_ value: String, _ size: CGFloat, _ color: UIColor) -> NSAttributedString {
            NSAttributedString(string: value, attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold), .foregroundColor: color])
        }
        let natural = make(main, size, foreground).size().width + make(fraction, size * 0.68, accent).size().width + 5
        size *= min(1, available / natural)
        let a = make(main, size, foreground), b = make(fraction, size * 0.68, accent)
        let x = (CGFloat(width) - a.size().width - b.size().width - 5) / 2
        let top = centerY - a.size().height / 2
        a.draw(at: CGPoint(x: x, y: top))
        b.draw(at: CGPoint(x: x + a.size().width + 5, y: top + (a.size().height - b.size().height) * 0.78))
    }
    private func text(_ value: String, rect: CGRect, size: CGFloat, color: UIColor, alignment: NSTextAlignment = .center) {
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
        let natural = (value as NSString).size(withAttributes: [.font: font]).width
        let adjusted = UIFont.monospacedDigitSystemFont(ofSize: size * min(1, rect.width / max(1, natural)), weight: .medium)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment
        (value as NSString).draw(in: rect, withAttributes: [.font: adjusted, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}
