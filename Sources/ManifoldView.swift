//
//  ManifoldView.swift
//  Principal class of the .saver bundle. Draws the ingtian.github.io terrain as a
//  living backdrop with a minimal digital clock floating over it.
//
//  "Manifold" — the terrain is literally a 2-manifold surface; also a nod to
//  manifold optimization and to many-folded mountain ranges (山水).
//

import AppKit
import ScreenSaver

@objc(ManifoldView)
final class ManifoldView: ScreenSaverView {

    /// Horizontal placement of the clock's center, as a fraction of view width.
    /// The terrain's bright ridge sits left-of-center, so we anchor the clock on
    /// the RIGHT golden section (1/φ ≈ 0.618) to counterbalance it — a principled,
    /// naturally pleasing asymmetry rather than an arbitrary offset. 0.5 = dead
    /// center; 0.618 = golden ratio.
    static let clockCenterFraction: CGFloat = 0.6180339887498949 // 1/φ = φ − 1

    private let settings: Settings
    private let renderer: TerrainRenderer
    private var startTime: Date
    private var configController: ConfigSheetController?

    private let timeFormatter = DateFormatter()
    private let secondsFormatter = DateFormatter()
    private let ampmFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()

    // MARK: Init

    override init?(frame: NSRect, isPreview: Bool) {
        let moduleName = Bundle(for: ManifoldView.self).bundleIdentifier
            ?? "com.ingtian.manifold"
        let settings = Settings(moduleName: moduleName)
        self.settings = settings
        self.renderer = TerrainRenderer(palette: .dark, animateWalkers: settings.showWalkers)
        renderer.lightingEnabled = settings.lightingEnabled   // Eye-Dome Lighting shape cue
        renderer.zoomOut = settings.zoomLevel
        renderer.breathStrength = settings.breathStrength
        self.startTime = Date()
        super.init(frame: frame, isPreview: isPreview)

        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        configureFormatters()
        renderer.setPaletteImmediately(currentPalette()) // no fade on first build
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Lifecycle

    override func startAnimation() {
        startTime = Date()
        renderer.lightingEnabled = settings.lightingEnabled
        renderer.zoomOut = settings.zoomLevel
        renderer.breathStrength = settings.breathStrength
        renderer.setPaletteImmediately(currentPalette()) // no fade when (re)starting
        renderer.setAnimateWalkers(settings.showWalkers)
        configureFormatters()
        super.startAnimation()
    }

    override func stopAnimation() {
        super.stopAnimation()
    }

    override func animateOneFrame() {
        setNeedsDisplay(bounds)
    }

    // MARK: Drawing

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        let nowMs = Date().timeIntervalSince(startTime) * 1000.0

        // Keep the terrain palette in lockstep with the clock's. Cheap (stores a
        // struct) and lets `auto` mode follow a live system light/dark switch.
        renderer.setPalette(currentPalette())

        // --- Terrain pass (Y-down) ---
        ctx.saveGState()
        if !isFlipped {
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        renderer.render(in: ctx, size: size, nowMs: nowMs, animate: true)
        ctx.restoreGState()

        // --- Clock pass (native Y-up) ---
        drawClock(in: size, now: Date(), nowMs: nowMs)
    }

    // MARK: Clock

    private func drawClock(in size: CGSize, now: Date, nowMs: Double) {
        // Pull the clock colors from the renderer so they cross-fade in lockstep
        // with the terrain during a theme switch (rather than snapping).
        let ink = renderer.currentClockInk.cgColor(alpha: 1.0)
        let shadowColor = renderer.currentClockShadow.cgColor(alpha: 0.55)

        let base = min(size.width, size.height)
        let timeSize = base * 0.17
        let secSize = timeSize * 0.42
        let dateSize = base * 0.032
        let mottoSize = base * 0.022 // smaller than the date

        let timeString = attributedTime(now, timeSize: timeSize, secSize: secSize, ink: ink)
        let timeBounds = timeString.size()

        var dateString: NSAttributedString?
        var dateBounds = CGSize.zero
        if settings.showDate {
            dateString = attributedDate(now, size: dateSize, ink: ink)
            dateBounds = dateString!.size()
        }

        // Motto: a small italic signature line directly below the clock.
        let motto = settings.footerMessage
        var mottoString: NSAttributedString?
        var mottoBounds = CGSize.zero
        if !motto.isEmpty {
            mottoString = attributedMotto(motto, size: mottoSize, ink: ink)
            mottoBounds = mottoString!.size()
        }

        let dateGap: CGFloat = settings.showDate ? base * 0.02 : 0
        let mottoGap: CGFloat = mottoString != nil ? base * 0.022 : 0
        let blockHeight = timeBounds.height + dateGap + dateBounds.height
            + mottoGap + mottoBounds.height

        // Fixed placement on the right golden section (see clockCenterFraction).
        // The terrain's bright ridge occupies the left, so anchoring the clock's
        // center at 1/φ of the width balances the composition. Vertically it stays
        // centered — the look that was dialed in.
        let centerX = size.width * ManifoldView.clockCenterFraction
        let blockTop = size.height / 2 + blockHeight / 2

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(cgColor: shadowColor)
        shadow.shadowBlurRadius = timeSize * 0.06
        shadow.shadowOffset = NSSize(width: 0, height: -timeSize * 0.02)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()

        // Track the running baseline as we stack time → date → motto downward.
        var cursorY = blockTop - timeBounds.height
        let timeOrigin = CGPoint(x: centerX - timeBounds.width / 2, y: cursorY)
        timeString.draw(at: timeOrigin)

        // Nudge the date + motto right of the time for a stair-step cascade.
        let subOffset = base * 0.06
        let subCenterX = centerX + subOffset

        if let dateString {
            cursorY -= dateGap + dateBounds.height
            dateString.draw(at: CGPoint(x: subCenterX - dateBounds.width / 2, y: cursorY))
        }

        if let mottoString {
            cursorY -= mottoGap + mottoBounds.height
            // Right-align the motto to the date's right edge (or the time's, if the
            // date is hidden). The staggered right edge breaks the all-centered
            // monotony and reads as a deliberate signature.
            let refWidth = settings.showDate ? dateBounds.width : timeBounds.width
            let refCenterX = settings.showDate ? subCenterX : centerX
            let rightEdge = refCenterX + refWidth / 2
            mottoString.draw(at: CGPoint(x: rightEdge - mottoBounds.width, y: cursorY))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A themed font in the user's chosen design, optionally with monospaced digits
    /// (used for the time so its width doesn't jitter as digits change).
    private func themedFont(size: CGFloat, weight: NSFont.Weight, monoDigits: Bool) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var desc = base.fontDescriptor
        if let d = desc.withDesign(settings.fontDesign.systemDesign) { desc = d }
        if monoDigits {
            // kNumberSpacingType (6) / kMonospacedNumbersSelector (0)
            let feature: [NSFontDescriptor.FeatureKey: Any] = [
                .typeIdentifier: 6, .selectorIdentifier: 0,
            ]
            desc = desc.addingAttributes([.featureSettings: [feature]])
        }
        return NSFont(descriptor: desc, size: size) ?? base
    }

    private func attributedTime(_ now: Date, timeSize: CGFloat, secSize: CGFloat,
                                ink: CGColor) -> NSAttributedString {
        let mainFont = themedFont(size: timeSize, weight: .thin, monoDigits: true)
        let smallFont = themedFont(size: secSize, weight: .regular, monoDigits: true)
        let inkColor = NSColor(cgColor: ink) ?? .white

        let result = NSMutableAttributedString(
            string: timeFormatter.string(from: now),
            attributes: [.font: mainFont, .foregroundColor: inkColor,
                         .kern: timeSize * 0.01])

        if settings.showSeconds {
            let sec = NSAttributedString(
                string: " " + secondsFormatter.string(from: now),
                attributes: [.font: smallFont,
                             .foregroundColor: inkColor.withAlphaComponent(0.62),
                             .baselineOffset: timeSize * 0.06])
            result.append(sec)
        }

        if !settings.use24Hour {
            let ap = NSAttributedString(
                string: " " + ampmFormatter.string(from: now).lowercased(),
                attributes: [.font: smallFont,
                             .foregroundColor: inkColor.withAlphaComponent(0.62),
                             .baselineOffset: timeSize * 0.06])
            result.append(ap)
        }
        return result
    }

    private func attributedDate(_ now: Date, size: CGFloat, ink: CGColor) -> NSAttributedString {
        let font = themedFont(size: size, weight: .regular, monoDigits: false)
        let inkColor = (NSColor(cgColor: ink) ?? .white).withAlphaComponent(0.82)
        return NSAttributedString(
            string: dateFormatter.string(from: now).uppercased(),
            attributes: [.font: font, .foregroundColor: inkColor, .kern: size * 0.18])
    }

    private func attributedMotto(_ text: String, size: CGFloat, ink: CGColor) -> NSAttributedString {
        // Small, italic, low-opacity — reads as a quiet signature under the clock.
        var font = themedFont(size: size, weight: .light, monoDigits: false)
        let italicDesc = font.fontDescriptor.withSymbolicTraits(.italic)
        if let it = NSFont(descriptor: italicDesc, size: size) { font = it }
        let inkColor = (NSColor(cgColor: ink) ?? .white).withAlphaComponent(0.6)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: inkColor,
                         .kern: size * 0.06, .paragraphStyle: paragraph])
    }

    private func configureFormatters() {
        let loc = Locale.autoupdatingCurrent
        timeFormatter.locale = loc
        secondsFormatter.locale = loc
        ampmFormatter.locale = loc
        dateFormatter.locale = loc

        if settings.use24Hour {
            timeFormatter.dateFormat = "HH:mm"
        } else {
            timeFormatter.dateFormat = "h:mm"
        }
        secondsFormatter.dateFormat = "ss"
        ampmFormatter.dateFormat = "a"
        dateFormatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
    }

    // MARK: Theme

    /// Palette for the current theme preference. `auto` follows the system
    /// appearance (like the site's prefers-color-scheme); light/dark force it.
    private func currentPalette() -> Palette {
        let preset = settings.palettePreset
        switch settings.theme {
        case .light: return preset.palette(dark: false)
        case .dark: return preset.palette(dark: true)
        case .auto: return preset.palette(dark: isSystemDark())
        }
    }

    private func isSystemDark() -> Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Re-read settings into formatters/renderer and redraw. Called when the
    /// options change (from the config sheet).
    func refreshFromSettings() {
        configureFormatters()
        renderer.lightingEnabled = settings.lightingEnabled
        renderer.zoomOut = settings.zoomLevel
        renderer.breathStrength = settings.breathStrength
        renderer.setPalette(currentPalette())
        renderer.setAnimateWalkers(settings.showWalkers)
        setNeedsDisplay(bounds)
    }

    // MARK: Config sheet

    override var hasConfigureSheet: Bool { true }

    /// Build a config controller wired to refresh this live view. Used both by the
    /// System Settings sheet and by the preview app's ',' Settings shortcut.
    func makeConfigController() -> ConfigSheetController {
        ConfigSheetController(settings: settings) { [weak self] in
            self?.refreshFromSettings()
        }
    }

    override var configureSheet: NSWindow? {
        if configController == nil {
            configController = makeConfigController()
        }
        return configController?.window
    }
}
