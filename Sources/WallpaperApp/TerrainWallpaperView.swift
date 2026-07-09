//
//  TerrainWallpaperView.swift
//  The NSView that renders the Manifold terrain as a live wallpaper. It reuses
//  the screensaver's TerrainRenderer verbatim (shared source), driven by a
//  CADisplayLink for smooth, display-synced, power-friendly frame pacing.
//
//  Minimal by default: just the calm breathing terrain. An optional small
//  signature line can be drawn in the bottom-left corner. Theme switches
//  cross-fade via the renderer, and the footer fades in lockstep.
//

import AppKit
import QuartzCore

final class TerrainWallpaperView: NSView {

    private let renderer: TerrainRenderer
    private var displayLink: CADisplayLink?

    /// Optional signature line drawn bottom-left. nil / empty → nothing drawn.
    private var footer: String?

    // A monotonic timeline in ms. We accumulate only while running so a pause
    // doesn't cause the breathing/walkers to lurch forward on resume.
    private var elapsedMs: Double = 0
    private var lastTickHostTime: CFTimeInterval = 0

    /// Whether the animation loop is currently ticking. Derived from the link so
    /// the two can never disagree (a stale flag could otherwise wedge start()).
    var isRunning: Bool { displayLink != nil }

    /// Preferred max FPS. Lowered on battery / Low Power Mode by the governor.
    var maxFPS: Int = 30 {
        didSet { applyFrameRate() }
    }

    // The renderer draws Y-DOWN (HTML-canvas convention); this view is Y-up.
    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    init(frame: NSRect, palette: Palette, showWalkers: Bool) {
        self.renderer = TerrainRenderer(palette: palette, animateWalkers: showWalkers)
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    // MARK: Palette / options

    /// Switch theme with the renderer's built-in cross-fade. Calling with the same
    /// theme repeatedly is a no-op inside the renderer, so this is safe per-frame.
    func setPalette(_ p: Palette, animated: Bool) {
        if animated { renderer.setPalette(p) } else { renderer.setPaletteImmediately(p) }
        // A non-animated change (e.g. first show) still needs one redraw even if paused.
        if !isRunning { setNeedsDisplay(bounds) }
    }

    func setShowWalkers(_ on: Bool) { renderer.setAnimateWalkers(on) }

    /// Set the bottom-left signature line. Pass nil or "" to hide it.
    func setFooter(_ text: String?) {
        let trimmed = text?.isEmpty == true ? nil : text
        guard trimmed != footer else { return }
        footer = trimmed
        setNeedsDisplay(bounds) // reflect immediately, even while paused
    }

    // MARK: Animation loop

    func start() {
        guard !isRunning else { return }
        lastTickHostTime = 0
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        applyFrameRate(to: link)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        guard isRunning else { return }
        displayLink?.invalidate()
        displayLink = nil
    }

    private func applyFrameRate() { if let l = displayLink { applyFrameRate(to: l) } }

    private func applyFrameRate(to link: CADisplayLink) {
        let hi = Float(max(1, maxFPS))
        // Allow the system to coast down to ~half the target when idle/thermal.
        let lo = max(1, hi / 2)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: lo, maximum: hi, preferred: hi)
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Advance our own timeline by real elapsed wall-time between ticks, so the
        // animation speed is independent of the actual (variable) frame rate.
        let now = link.timestamp
        if lastTickHostTime > 0 {
            elapsedMs += (now - lastTickHostTime) * 1000.0
        }
        lastTickHostTime = now
        setNeedsDisplay(bounds)
    }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size

        ctx.saveGState()
        // Flip into the renderer's Y-down space.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        renderer.render(in: ctx, size: size, nowMs: elapsedMs, animate: isRunning)
        ctx.restoreGState()

        // Footer pass, in the view's native Y-up space (like the saver's clock).
        drawFooter(in: size)
    }

    /// A small, quiet italic signature line in the bottom-left. Uses the renderer's
    /// current ink so it cross-fades with the theme; sized as a fraction of the
    /// view so it scales to any resolution.
    private func drawFooter(in size: CGSize) {
        guard let text = footer, !text.isEmpty else { return }

        let base = min(size.width, size.height)
        let fontSize = base * 0.018
        let margin = base * 0.045

        let ink = renderer.currentClockInk
        var font = NSFont.systemFont(ofSize: fontSize, weight: .light)
        if let italic = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic),
                               size: fontSize) {
            font = italic
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: (NSColor(cgColor: ink.cgColor(alpha: 1)) ?? .labelColor)
                .withAlphaComponent(0.6),
            .kern: fontSize * 0.06,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        // Bottom-left, inset by the margin (native Y-up: y=margin is near the bottom).
        str.draw(at: CGPoint(x: margin, y: margin))
    }
}
