//
//  ASCIISaverView.swift
//  The screen saver entry point: owns the clock, the runner and the renderer.
//

import ScreenSaver

@objc(ASCIISaverView)
final class ASCIISaverView: ScreenSaverView {

	private var program = TimeMilliseconds()
	private lazy var runner = Runner(program: program)
	private let renderer = GridRenderer()

	private var theme: Theme = .light
	private var baseFontSize: CGFloat = 16
	private var metrics: Metrics?

	/// Wall-clock timestamp of the previous frame, used to advance the
	/// program's clock by real elapsed time rather than a nominal frame length.
	private var lastFrameTime: CFTimeInterval = 0
	private var measuredFPS: Double = 0

	// MARK: Lifecycle

	override init?(frame: NSRect, isPreview: Bool) {
		super.init(frame: frame, isPreview: isPreview)
		wantsLayer = true
		loadPreferences()
		NotificationCenter.default.addObserver(self,
		                                       selector: #selector(preferencesChanged),
		                                       name: .asciiSaverPreferencesChanged,
		                                       object: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not used — the saver is instantiated by frame.")
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	private func loadPreferences() {
		let prefs = Preferences.shared
		theme = prefs.theme.theme
		animationTimeInterval = 1.0 / Double(prefs.fps)

		// TimeMilliseconds is a struct, so the runner holds a copy — push the
		// reconfigured program across or the change never reaches the frame loop.
		program.showInfo = prefs.showInfo
		runner.program = program

		// The preview thumbnail is a few hundred points wide; at the full size
		// it would show a handful of huge characters, so scale down to keep a
		// representative grid.
		let size = CGFloat(prefs.fontSize)
		baseFontSize = isPreview ? max(4, (size * 0.4).rounded()) : size
		metrics = nil
	}

	@objc private func preferencesChanged() {
		loadPreferences()
		// The host reads animationTimeInterval when the timer starts, so a new
		// frame rate only takes hold after a restart.
		if isAnimating {
			super.stopAnimation()
			super.startAnimation()
		}
		setNeedsDisplay(bounds)
	}

	// MARK: Animation

	override func startAnimation() {
		loadPreferences()
		lastFrameTime = 0
		super.startAnimation()
	}

	override func stopAnimation() {
		super.stopAnimation()
	}

	override func animateOneFrame() {
		super.animateOneFrame()

		let now = CACurrentMediaTime()
		let delta: CFTimeInterval
		if lastFrameTime == 0 {
			delta = animationTimeInterval
		} else {
			// Clamp so a paused or stalled saver doesn't jump the animation.
			delta = min(now - lastFrameTime, 0.25)
		}
		lastFrameTime = now

		if delta > 0 {
			let instantFPS = 1.0 / delta
			measuredFPS = measuredFPS == 0 ? instantFPS
			                               : measuredFPS * 0.9 + instantFPS * 0.1
		}

		let metrics = currentMetrics()
		let cols = max(1, Int(bounds.width / metrics.cellWidth))
		let rows = max(1, Int(bounds.height / metrics.lineHeight))

		runner.step(deltaMS: delta * 1000,
		            cols: cols,
		            rows: rows,
		            metrics: metrics,
		            size: bounds.size,
		            fps: measuredFPS)

		setNeedsDisplay(bounds)
	}

	private func currentMetrics() -> Metrics {
		if let metrics, metrics.fontSize == baseFontSize { return metrics }
		let metrics = renderer.metrics(forFontSize: baseFontSize)
		self.metrics = metrics
		return metrics
	}

	// MARK: Drawing

	override func draw(_ rect: NSRect) {
		guard let ctx = NSGraphicsContext.current?.cgContext else { return }
		renderer.render(buffer: runner.buffer,
		                metrics: currentMetrics(),
		                theme: theme,
		                defaultWeight: .ultraLight,
		                size: bounds.size,
		                in: ctx)
	}

	// MARK: Options sheet

	override var hasConfigureSheet: Bool { true }

	override var configureSheet: NSWindow? {
		let controller = ConfigureSheetController.shared
		controller.reload()
		return controller.window
	}
}
