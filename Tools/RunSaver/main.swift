//
//  RunSaver
//  Hosts a built .saver bundle in a window so it can be previewed without
//  selecting it in System Settings. Loads the bundle the same way the real
//  screen saver host does: NSPrincipalClass -> ScreenSaverView.
//
//  Usage: RunSaver <path-to-.saver> [--window] [--timeout <seconds>]
//
//  Quit with Esc, any key, or a click.
//

import AppKit
import ScreenSaver

// MARK: Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
let windowed = arguments.contains("--window")
arguments.removeAll { $0 == "--window" }

var timeout: TimeInterval = 300
if let i = arguments.firstIndex(of: "--timeout"), i + 1 < arguments.count {
	timeout = TimeInterval(arguments[i + 1]) ?? timeout
	arguments.removeSubrange(i...(i + 1))
}

let saverPath = arguments.first
	?? NSString(string: "~/Library/Screen Savers/ASCIISaver.saver").expandingTildeInPath

// MARK: Load the saver

guard let bundle = Bundle(path: saverPath) else {
	FileHandle.standardError.write("No bundle at \(saverPath)\n".data(using: .utf8)!)
	exit(1)
}
guard bundle.load(), let saverClass = bundle.principalClass as? ScreenSaverView.Type else {
	FileHandle.standardError.write("\(saverPath) has no ScreenSaverView principal class\n".data(using: .utf8)!)
	exit(1)
}

// MARK: Window

/// Borderless windows refuse key status by default, which would swallow the
/// keystroke used to quit.
final class SaverWindow: NSWindow {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { true }
}

final class Delegate: NSObject, NSApplicationDelegate {
	// Passed in rather than captured: a type declared at top level cannot close
	// over top-level bindings.
	let saverClass: ScreenSaverView.Type
	let windowed: Bool
	let timeout: TimeInterval

	var window: NSWindow!
	var saverView: ScreenSaverView!

	init(saverClass: ScreenSaverView.Type, windowed: Bool, timeout: TimeInterval) {
		self.saverClass = saverClass
		self.windowed = windowed
		self.timeout = timeout
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		let screen = NSScreen.main ?? NSScreen.screens[0]
		let frame = windowed
			? NSRect(x: 0, y: 0, width: 1280, height: 800)
			: screen.frame

		window = SaverWindow(contentRect: frame,
		                     styleMask: windowed ? [.titled, .closable] : [.borderless],
		                     backing: .buffered,
		                     defer: false)
		window.title = "ASCIISaver preview"
		if !windowed {
			// Above normal windows but below the real screen saver, so
			// Cmd-Tab and Mission Control still work if anything goes wrong.
			window.level = .floating
			window.setFrame(screen.frame, display: true)
		} else {
			window.center()
		}

		guard let view = saverClass.init(frame: NSRect(origin: .zero, size: frame.size),
		                                 isPreview: false) else {
			FileHandle.standardError.write("saver view init failed\n".data(using: .utf8)!)
			exit(1)
		}
		saverView = view
		view.autoresizingMask = [.width, .height]
		window.contentView = view

		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		view.startAnimation()

		// Escape hatches: any key, any click, or a timeout.
		NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { _ in
			NSApp.terminate(nil)
			return nil
		}
		if timeout > 0 {
			Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
				NSApp.terminate(nil)
			}
		}
		if !windowed {
			NSCursor.hide()
		}
	}

	func applicationWillTerminate(_ notification: Notification) {
		if saverView?.isAnimating == true { saverView.stopAnimation() }
		NSCursor.unhide()
	}
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate(saverClass: saverClass, windowed: windowed, timeout: timeout)
app.delegate = delegate
app.run()
