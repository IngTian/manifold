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
    private var themePopup: NSPopUpButton!
    private var fontPopup: NSPopUpButton!
    private var mottoField: NSTextField!

    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        super.init()
        buildWindow()
    }

    private func buildWindow() {
        let width: CGFloat = 420
        let height: CGFloat = 420
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

        let fontLabel = makeLabel("Font", size: 12, weight: .regular)
        fontLabel.frame = NSRect(x: 24, y: y, width: 60, height: 20)
        content.addSubview(fontLabel)

        fontPopup = NSPopUpButton(frame: NSRect(x: 90, y: y - 3, width: 220, height: 26))
        fontPopup.addItems(withTitles: FontDesign.allCases.map { $0.label })
        fontPopup.selectItem(at: settings.fontDesign.rawValue)
        fontPopup.target = self
        fontPopup.action = #selector(changeFont)
        content.addSubview(fontPopup)
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
    @objc private func changeTheme() {
        settings.theme = ThemePreference(rawValue: themePopup.indexOfSelectedItem) ?? .auto
        live()
    }
    @objc private func changeFont() {
        settings.fontDesign = FontDesign(rawValue: fontPopup.indexOfSelectedItem) ?? .system
        live()
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
