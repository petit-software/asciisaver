//
//  Preferences.swift
//  Settings shown in the saver's Options sheet, persisted through
//  ScreenSaverDefaults so they survive the out-of-process saver host.
//

import ScreenSaver

enum ThemeOption: Int, CaseIterable {
	case light = 0
	case dark  = 1

	var theme: Theme {
		switch self {
		case .light: return .light
		case .dark:  return .dark
		}
	}

	var title: String {
		switch self {
		case .light: return "Light (as on play.ertdfgcvb.xyz)"
		case .dark:  return "Dark"
		}
	}
}

final class Preferences {

	static let shared = Preferences()

	private enum Key {
		static let fontSize = "fontSize"
		static let theme    = "theme"
		static let showInfo = "showInfo"
		static let fps      = "fps"
	}

	private let defaults: UserDefaults

	private init() {
		let bundleID = Bundle(for: ASCIISaverView.self).bundleIdentifier ?? "com.bartbak.ASCIISaver"
		defaults = ScreenSaverDefaults(forModuleWithName: bundleID) ?? .standard
		defaults.register(defaults: [
			Key.fontSize: 16.0,
			Key.theme: ThemeOption.light.rawValue,
			Key.showInfo: false,
			Key.fps: 30,
		])
	}

	/// Point size of the grid font. Smaller means more columns and more cells
	/// to draw, so this doubles as the quality/performance dial.
	var fontSize: Double {
		get { defaults.double(forKey: Key.fontSize).clamped(to: 6...48) }
		set { defaults.set(newValue.clamped(to: 6...48), forKey: Key.fontSize) }
	}

	var theme: ThemeOption {
		get { ThemeOption(rawValue: defaults.integer(forKey: Key.theme)) ?? .light }
		set { defaults.set(newValue.rawValue, forKey: Key.theme) }
	}

	/// Draws the demo's runtime readout (FPS, frame, time, grid size).
	var showInfo: Bool {
		get { defaults.bool(forKey: Key.showInfo) }
		set { defaults.set(newValue, forKey: Key.showInfo) }
	}

	var fps: Int {
		get { max(10, min(60, defaults.integer(forKey: Key.fps))) }
		set { defaults.set(max(10, min(60, newValue)), forKey: Key.fps) }
	}

	func synchronize() {
		defaults.synchronize()
	}
}

extension Double {
	func clamped(to range: ClosedRange<Double>) -> Double {
		Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
	}
}
