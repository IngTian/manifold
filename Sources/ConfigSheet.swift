//
//  ConfigSheet.swift
//  The "Screen Saver Options…" sheet, built programmatically (no nib).
//  Font design and the motto line are configured HERE only — deliberately not
//  adjustable live on the running screensaver.
//

import AppKit

final class ConfigSheetController: NSObject, NSTextFieldDelegate {
    private let settings: Settings
    private let onChange: () -> Void

    private(set) var window: NSWindow!

    private var use24Button: NSButton!
    private var secondsButton: NSButton!
    private var dateButton: NSButton!
    private var walkersButton: NSButton!
    private var lightingButton: NSButton!
    private var themePopup: NSPopUpButton!
    private var palettePopup: NSPopUpButton!
    private var fontPopup: NSPopUpButton!
    private var zoomSlider: NSSlider!
    private var zoomValueLabel: NSTextField!
    private var breathSlider: NSSlider!
    private var breathValueLabel: NSTextField!
    private var mottoField: NSTextField!

    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        super.init()
        buildWindow()
    }

    private func buildWindow() {
        let width: CGFloat = 420
        let height: CGFloat = 584
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        win.title = "Manifold"
        // Keep the window alive across close so it can be reopened. Without this,
        // a programmatic NSWindow is released on close and the retained reference
        // dangles → crash on the next open. (Reused by the preview's ',' shortcut.)
        win.isReleasedWhenClosed = false

        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let title = makeLabel("Manifold", size: 15, weight: .semibold)
        title.frame = NSRect(x: 24, y: height - 44, width: width - 48, height: 22)
        content.addSubview(title)

        let subtitle = makeLabel("A living pointillist-terrain clock, after ingtian.github.io.",
                                 size: 11, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: height - 64, width: width - 48, height: 16)
        content.addSubview(subtitle)

        var y = height - 104

        use24Button = makeCheckbox("Use 24-hour time", action: #selector(toggle24))
        use24Button.state = settings.use24Hour ? .on : .off
        use24Button.frame = NSRect(x: 24, y: y, width: width - 48, height: 20)
        content.addSubview(use24Button)
        y -= 30

        secondsButton = makeCheckbox("Show seconds", action: #selector(toggleSeconds))
        secondsButton.state = settings.showSeconds ? .on : .off
        secondsButton.frame = NSRect(x: 24, y: y, width: width - 48, height: 20)
        content.addSubview(secondsButton)
        y -= 30

        dateButton = makeCheckbox("Show date", action: #selector(toggleDate))
        dateButton.state = settings.showDate ? .on : .off
        dateButton.frame = NSRect(x: 24, y: y, width: width - 48, height: 20)
        content.addSubview(dateButton)
        y -= 30

        walkersButton = makeCheckbox("Show walker particles", action: #selector(toggleWalkers))
        walkersButton.state = settings.showWalkers ? .on : .off
        walkersButton.frame = NSRect(x: 24, y: y, width: width - 48, height: 20)
        content.addSubview(walkersButton)
        y -= 30

        lightingButton = makeCheckbox("Shape lighting (Eye-Dome)", action: #selector(toggleLighting))
        lightingButton.state = settings.lightingEnabled ? .on : .off
        lightingButton.toolTip = "Shades the dots by depth so the terrain reads as 3D."
        lightingButton.frame = NSRect(x: 24, y: y, width: width - 48, height: 20)
        content.addSubview(lightingButton)
        y -= 40

        let themeLabel = makeLabel("Theme", size: 12, weight: .regular)
        themeLabel.frame = NSRect(x: 24, y: y, width: 60, height: 20)
        content.addSubview(themeLabel)

        themePopup = NSPopUpButton(frame: NSRect(x: 90, y: y - 3, width: 220, height: 26))
        themePopup.addItems(withTitles: ["Auto (match system)", "Light", "Dark"])
        themePopup.selectItem(at: settings.theme.rawValue)
        themePopup.target = self
        themePopup.action = #selector(changeTheme)
        content.addSubview(themePopup)
        y -= 36

        let paletteLabel = makeLabel("Palette", size: 12, weight: .regular)
        paletteLabel.frame = NSRect(x: 24, y: y, width: 60, height: 20)
        content.addSubview(paletteLabel)

        palettePopup = NSPopUpButton(frame: NSRect(x: 90, y: y - 3, width: 220, height: 26))
        palettePopup.addItems(withTitles: PalettePreset.allCases.map { $0.label })
        palettePopup.selectItem(at: settings.palettePreset.rawValue)
        palettePopup.target = self
        palettePopup.action = #selector(changePalette)
        content.addSubview(palettePopup)
        y -= 36

        let fontLabel = makeLabel("Font", size: 12, weight: .regular)
        fontLabel.frame = NSRect(x: 24, y: y, width: 60, height: 20)
        content.addSubview(fontLabel)

        fontPopup = NSPopUpButton(frame: NSRect(x: 90, y: y - 3, width: 220, height: 26))
        fontPopup.addItems(withTitles: FontDesign.allCases.map { $0.label })
        fontPopup.selectItem(at: settings.fontDesign.rawValue)
        fontPopup.target = self
        fontPopup.action = #selector(changeFont)
        content.addSubview(fontPopup)
        y -= 40

        let zoomLabel = makeLabel("Zoom", size: 12, weight: .regular)
        zoomLabel.frame = NSRect(x: 24, y: y, width: 60, height: 20)
        content.addSubview(zoomLabel)

        // zoomLevel is the renderer's `zoomOut` world→screen scale: LARGER draws the
        // terrain bigger = zoomed IN (less footprint); SMALLER shows more footprint.
        // So the slider runs 0.6 (wide, left) … 1.15 (close, right); the readout label
        // (zoomText) names the bands to match.
        zoomSlider = NSSlider(value: settings.zoomLevel, minValue: 0.6, maxValue: 1.15,
                              target: self, action: #selector(changeZoom))
        zoomSlider.frame = NSRect(x: 90, y: y - 2, width: 180, height: 24)
        zoomSlider.isContinuous = true
        content.addSubview(zoomSlider)

        zoomValueLabel = makeLabel(zoomText(settings.zoomLevel), size: 11, weight: .regular)
        zoomValueLabel.textColor = .secondaryLabelColor
        zoomValueLabel.alignment = .right
        zoomValueLabel.frame = NSRect(x: 278, y: y, width: 118, height: 18)
        content.addSubview(zoomValueLabel)
        y -= 40

        let motionLabel = makeLabel("Motion", size: 12, weight: .regular)
        motionLabel.frame = NSRect(x: 24, y: y, width: 60, height: 20)
        content.addSubview(motionLabel)

        // breathStrength scales the field's breathing amplitude: 0 = still … 2 =
        // double. 1.0 is the tuned default; the readout (breathText) names the bands.
        breathSlider = NSSlider(value: settings.breathStrength, minValue: 0.0, maxValue: 2.0,
                                target: self, action: #selector(changeBreath))
        breathSlider.frame = NSRect(x: 90, y: y - 2, width: 180, height: 24)
        breathSlider.isContinuous = true
        content.addSubview(breathSlider)

        breathValueLabel = makeLabel(breathText(settings.breathStrength), size: 11, weight: .regular)
        breathValueLabel.textColor = .secondaryLabelColor
        breathValueLabel.alignment = .right
        breathValueLabel.frame = NSRect(x: 278, y: y, width: 118, height: 18)
        content.addSubview(breathValueLabel)
        y -= 44

        let mottoLabel = makeLabel("Motto", size: 12, weight: .regular)
        mottoLabel.frame = NSRect(x: 24, y: y, width: width - 48, height: 18)
        content.addSubview(mottoLabel)
        y -= 26
        mottoField = NSTextField(frame: NSRect(x: 24, y: y, width: width - 48, height: 24))
        mottoField.stringValue = settings.footerMessage
        mottoField.placeholderString = "Leave empty to hide"
        mottoField.delegate = self
        content.addSubview(mottoField)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.frame = NSRect(x: width - 108, y: 16, width: 84, height: 30)
        content.addSubview(doneButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: width - 200, y: 16, width: 84, height: 30)
        content.addSubview(cancelButton)

        win.contentView = content
        self.window = win
    }

    // MARK: Actions

    @objc private func toggle24() { settings.use24Hour = (use24Button.state == .on) }
    @objc private func toggleSeconds() { settings.showSeconds = (secondsButton.state == .on) }
    @objc private func toggleDate() { settings.showDate = (dateButton.state == .on) }
    @objc private func toggleWalkers() { settings.showWalkers = (walkersButton.state == .on) }
    @objc private func toggleLighting() {
        settings.lightingEnabled = (lightingButton.state == .on)
        live()
    }
    @objc private func changeTheme() {
        settings.theme = ThemePreference(rawValue: themePopup.indexOfSelectedItem) ?? .auto
        live()
    }
    @objc private func changePalette() {
        settings.palettePreset = PalettePreset(rawValue: palettePopup.indexOfSelectedItem) ?? .classic
        live()
    }
    @objc private func changeFont() {
        settings.fontDesign = FontDesign(rawValue: fontPopup.indexOfSelectedItem) ?? .system
        live()
    }
    @objc private func changeZoom() {
        settings.zoomLevel = zoomSlider.doubleValue
        zoomValueLabel.stringValue = zoomText(zoomSlider.doubleValue)
        live()
    }
    @objc private func changeBreath() {
        settings.breathStrength = breathSlider.doubleValue
        breathValueLabel.stringValue = breathText(breathSlider.doubleValue)
        live()
    }

    /// A friendly right-anchored readout for the zoom slider (e.g. "close · 1.00×").
    /// Smaller zoomOut shows more terrain (wide); larger zooms in (close).
    private func zoomText(_ v: Double) -> String {
        let name: String
        switch v {
        case ..<0.75: name = "wide"
        case ..<0.95: name = "default"
        case ..<1.08: name = "close"
        default: name = "closest"
        }
        return String(format: "%@ · %.2f×", name, v)
    }

    /// A friendly right-anchored readout for the motion slider (e.g. "default · 1.00×").
    /// 0 = still, 1 = the tuned default, higher = livelier.
    private func breathText(_ v: Double) -> String {
        let name: String
        switch v {
        case ..<0.05: name = "still"
        case ..<0.8:  name = "subtle"
        case ..<1.25: name = "default"
        default:      name = "lively"
        }
        return String(format: "%@ · %.2f×", name, v)
    }

    /// Live-update the hosting view as controls change.
    func controlTextDidChange(_ note: Notification) {
        settings.footerMessage = mottoField.stringValue
        live()
    }

    private func live() {
        settings.synchronize()
        onChange()
    }

    @objc private func done() {
        settings.footerMessage = mottoField.stringValue
        settings.synchronize()
        onChange()
        endSheet()
    }

    @objc private func cancel() {
        endSheet()
    }

    private func endSheet() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }

    // MARK: Builders

    private func makeCheckbox(_ title: String, action: Selector) -> NSButton {
        NSButton(checkboxWithTitle: title, target: self, action: action)
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        return label
    }
}
