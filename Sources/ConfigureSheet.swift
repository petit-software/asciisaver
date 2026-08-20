//
//  ConfigureSheet.swift
//  The Options sheet, built in code so the bundle needs no nib.
//

import AppKit

extension Notification.Name {
	/// Posted after the sheet commits, so running views pick up new settings.
	static let asciiSaverPreferencesChanged = Notification.Name("ASCIISaverPreferencesChanged")
}

final class ConfigureSheetController: NSObject {

	static let shared = ConfigureSheetController()

	private(set) var window: NSWindow!

	private var fontSizeSlider: NSSlider!
	private var fontSizeLabel: NSTextField!
	private var themePopUp: NSPopUpButton!
	private var infoCheckbox: NSButton!
	private var fpsPopUp: NSPopUpButton!

	private let frameRates = [24, 30, 60]

	private override init() {
		super.init()
		buildWindow()
	}

	/// Reloads the controls from stored preferences. Called each time the sheet
	/// is presented, since the window instance is reused.
	func reload() {
		let prefs = Preferences.shared
		fontSizeSlider.doubleValue = prefs.fontSize
		updateFontSizeLabel()
		themePopUp.selectItem(at: prefs.theme.rawValue)
		infoCheckbox.state = prefs.showInfo ? .on : .off
		fpsPopUp.selectItem(at: frameRates.firstIndex(of: prefs.fps) ?? 1)
	}

	// MARK: Layout

	private func buildWindow() {
		let width: CGFloat = 440
		let height: CGFloat = 316
		window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
		                  styleMask: [.titled],
		                  backing: .buffered,
		                  defer: false)
		window.title = "ASCII Saver"
		guard let content = window.contentView else { return }

		let title = label("Time: milliseconds", size: 15, weight: .semibold)
		title.frame = NSRect(x: 20, y: height - 44, width: width - 40, height: 20)
		content.addSubview(title)

		var y = height - 84

		// Font size
		content.addSubview(fieldLabel("Character size:", y: y))
		fontSizeSlider = NSSlider(value: 16, minValue: 6, maxValue: 48,
		                          target: self, action: #selector(fontSizeChanged))
		fontSizeSlider.frame = NSRect(x: 150, y: y - 2, width: 210, height: 20)
		content.addSubview(fontSizeSlider)

		fontSizeLabel = label("16 pt", size: 11, weight: .regular)
		fontSizeLabel.alignment = .right
		fontSizeLabel.frame = NSRect(x: 366, y: y, width: 54, height: 16)
		content.addSubview(fontSizeLabel)

		y -= 36

		// Theme
		content.addSubview(fieldLabel("Colors:", y: y))
		themePopUp = NSPopUpButton(frame: NSRect(x: 146, y: y - 4, width: 274, height: 25))
		themePopUp.addItems(withTitles: ThemeOption.allCases.map(\.title))
		content.addSubview(themePopUp)

		y -= 36

		// Frame rate
		content.addSubview(fieldLabel("Frame rate:", y: y))
		fpsPopUp = NSPopUpButton(frame: NSRect(x: 146, y: y - 4, width: 120, height: 25))
		fpsPopUp.addItems(withTitles: frameRates.map { "\($0) fps" })
		content.addSubview(fpsPopUp)

		y -= 32

		// Info overlay
		infoCheckbox = NSButton(checkboxWithTitle: "Show runtime info overlay",
		                        target: nil, action: nil)
		infoCheckbox.frame = NSRect(x: 148, y: y, width: 272, height: 20)
		content.addSubview(infoCheckbox)

		// Attribution — the credit from the demo's own [header] block:
		//   @author ertdfgcvb
		//   @title  Time: milliseconds
		let separator = NSBox(frame: NSRect(x: 20, y: 100, width: width - 40, height: 1))
		separator.boxType = .separator
		content.addSubview(separator)

		let credit = label("“Time: milliseconds” by ertdfgcvb, from play.core.",
		                   size: 11, weight: .regular)
		credit.textColor = .secondaryLabelColor
		credit.frame = NSRect(x: 20, y: 74, width: width - 40, height: 15)
		content.addSubview(credit)

		let link = NSButton(title: "play.ertdfgcvb.xyz", target: self, action: #selector(openHomepage))
		link.isBordered = false
		link.contentTintColor = .linkColor
		link.font = .systemFont(ofSize: 11)
		link.alignment = .left
		// Borderless buttons carry a small internal inset; nudge left to sit
		// flush with the label above.
		link.frame = NSRect(x: 17, y: 54, width: 200, height: 16)
		content.addSubview(link)

		// Buttons
		let ok = NSButton(title: "OK", target: self, action: #selector(commit))
		ok.bezelStyle = .rounded
		ok.keyEquivalent = "\r"
		ok.frame = NSRect(x: width - 100, y: 16, width: 80, height: 28)
		content.addSubview(ok)

		let cancel = NSButton(title: "Cancel", target: self, action: #selector(dismiss))
		cancel.bezelStyle = .rounded
		cancel.keyEquivalent = "\u{1b}"
		cancel.frame = NSRect(x: width - 188, y: 16, width: 80, height: 28)
		content.addSubview(cancel)

		reload()
	}

	private func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
		let field = NSTextField(labelWithString: text)
		field.font = .systemFont(ofSize: size, weight: weight)
		return field
	}

	private func fieldLabel(_ text: String, y: CGFloat) -> NSTextField {
		let field = label(text, size: 13, weight: .regular)
		field.alignment = .right
		field.frame = NSRect(x: 20, y: y, width: 120, height: 18)
		return field
	}

	// MARK: Actions

	@objc private func fontSizeChanged() {
		updateFontSizeLabel()
	}

	@objc private func openHomepage() {
		guard let url = URL(string: "https://play.ertdfgcvb.xyz") else { return }
		NSWorkspace.shared.open(url)
	}

	private func updateFontSizeLabel() {
		fontSizeLabel.stringValue = "\(Int(fontSizeSlider.doubleValue.rounded())) pt"
	}

	@objc private func commit() {
		let prefs = Preferences.shared
		prefs.fontSize = fontSizeSlider.doubleValue.rounded()
		prefs.theme = ThemeOption(rawValue: themePopUp.indexOfSelectedItem) ?? .light
		prefs.showInfo = infoCheckbox.state == .on
		prefs.fps = frameRates[min(fpsPopUp.indexOfSelectedItem, frameRates.count - 1)]
		prefs.synchronize()

		NotificationCenter.default.post(name: .asciiSaverPreferencesChanged, object: nil)
		close()
	}

	@objc private func dismiss() {
		close()
	}

	private func close() {
		if let parent = window.sheetParent {
			parent.endSheet(window)
		} else {
			window.orderOut(nil)
		}
	}
}
