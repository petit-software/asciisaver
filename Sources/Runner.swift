//
//  Runner.swift
//  A Swift port of the play.core runtime (github.com/ertdfgcvb/play.core).
//
//  The original is a browser runtime: every frame it walks a grid of character
//  cells, asks the program for the character at each coordinate, and hands the
//  resulting buffer to a renderer. This file mirrors that model — Cell, Buffer,
//  Context, Program, Runner — so programs written for play.core translate
//  almost line for line.
//

import AppKit

// MARK: - Color

/// An sRGB color. A plain value type so the renderer can compare cell styles
/// cheaply and batch every cell that shares one into a single draw call.
struct RGBA: Equatable {
	var r: CGFloat
	var g: CGFloat
	var b: CGFloat
	var a: CGFloat

	init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) {
		self.r = r; self.g = g; self.b = b; self.a = a
	}

	var cgColor: CGColor {
		CGColor(srgbRed: r, green: g, blue: b, alpha: a)
	}
}

extension RGBA {
	/// The CSS named colors the ported programs actually reference.
	static let black     = RGBA(0, 0, 0)
	static let white     = RGBA(1, 1, 1)
	static let royalBlue = RGBA( 65/255, 105/255, 225/255)
	static let dimGray   = RGBA(105/255, 105/255, 105/255)
	static let lightGray = RGBA(211/255, 211/255, 211/255)
}

// MARK: - Cell

/// One character cell. `nil` style fields fall back to the theme, which is how
/// play.core treats a style the program never set.
struct Cell {
	var char: UnicodeScalar = " "
	var color: RGBA?
	var backgroundColor: RGBA?
	var fontWeight: NSFont.Weight?

	init(char: UnicodeScalar = " ",
	     color: RGBA? = nil,
	     backgroundColor: RGBA? = nil,
	     fontWeight: NSFont.Weight? = nil) {
		self.char = char
		self.color = color
		self.backgroundColor = backgroundColor
		self.fontWeight = fontWeight
	}
}

// MARK: - Geometry & context

struct Coord {
	let x: Int
	let y: Int
	let index: Int
}

/// Cell geometry, derived from the font once per size change.
struct Metrics {
	/// Horizontal advance of one monospaced character.
	let cellWidth: CGFloat
	/// Height of one row — the CSS `line-height` equivalent.
	let lineHeight: CGFloat
	let fontSize: CGFloat
	/// Distance from the top of the line box down to the text baseline.
	let baselineOffset: CGFloat

	/// Width-to-height ratio of a cell. This is what gives an ASCII program its
	/// proportions: the same formula on a wider cell draws a wider pattern.
	var aspect: CGFloat { cellWidth / lineHeight }
}

/// Per-frame snapshot handed to the program. Mirrors play.core's `context`.
struct Context {
	let frame: Int
	/// Milliseconds since the program started, matching play.core's `context.time`.
	let time: Double
	let cols: Int
	let rows: Int
	let metrics: Metrics
	let width: CGFloat
	let height: CGFloat
	let fps: Double
}

// MARK: - Buffer

/// The grid of cells. Writes outside the grid are clipped rather than trapping,
/// which is what the drawing helpers rely on when a box runs past an edge.
final class Buffer {
	private(set) var cols = 0
	private(set) var rows = 0
	private(set) var cells: [Cell] = []

	/// Resizes and clears the grid. Returns `true` if the size actually changed.
	@discardableResult
	func resize(cols newCols: Int, rows newRows: Int) -> Bool {
		guard newCols != cols || newRows != rows else { return false }
		cols = max(0, newCols)
		rows = max(0, newRows)
		cells = Array(repeating: Cell(), count: cols * rows)
		return true
	}

	func contains(_ x: Int, _ y: Int) -> Bool {
		x >= 0 && x < cols && y >= 0 && y < rows
	}

	subscript(x: Int, y: Int) -> Cell {
		get { contains(x, y) ? cells[y * cols + x] : Cell() }
		set { if contains(x, y) { cells[y * cols + x] = newValue } }
	}

	/// Overwrites a cell wholesale.
	func set(_ cell: Cell, x: Int, y: Int) {
		guard contains(x, y) else { return }
		cells[y * cols + x] = cell
	}

	/// Applies only the non-nil fields, leaving the rest of the cell intact —
	/// play.core's `merge()`.
	func merge(x: Int, y: Int,
	           char: UnicodeScalar? = nil,
	           color: RGBA? = nil,
	           backgroundColor: RGBA? = nil,
	           fontWeight: NSFont.Weight? = nil) {
		guard contains(x, y) else { return }
		let i = y * cols + x
		if let char { cells[i].char = char }
		if let color { cells[i].color = color }
		if let backgroundColor { cells[i].backgroundColor = backgroundColor }
		if let fontWeight { cells[i].fontWeight = fontWeight }
	}

	/// `merge()` over a rectangle.
	func mergeRect(x: Int, y: Int, width: Int, height: Int,
	               char: UnicodeScalar? = nil,
	               color: RGBA? = nil,
	               backgroundColor: RGBA? = nil,
	               fontWeight: NSFont.Weight? = nil) {
		guard width > 0, height > 0 else { return }
		for j in y..<(y + height) {
			for i in x..<(x + width) {
				merge(x: i, y: j, char: char, color: color,
				      backgroundColor: backgroundColor, fontWeight: fontWeight)
			}
		}
	}

	/// Fills a rectangle, replacing whatever was there — play.core's `setRect()`.
	func setRect(_ cell: Cell, x: Int, y: Int, width: Int, height: Int) {
		guard width > 0, height > 0 else { return }
		for j in y..<(y + height) {
			for i in x..<(x + width) {
				set(cell, x: i, y: j)
			}
		}
	}

	/// Writes multi-line text with its top-left corner at (x, y).
	func mergeText(_ text: String, x: Int, y: Int,
	               color: RGBA? = nil,
	               backgroundColor: RGBA? = nil,
	               fontWeight: NSFont.Weight? = nil) {
		var row = y
		for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
			var col = x
			for scalar in line.unicodeScalars {
				merge(x: col, y: row, char: scalar, color: color,
				      backgroundColor: backgroundColor, fontWeight: fontWeight)
				col += 1
			}
			row += 1
		}
	}
}

// MARK: - Program

/// A play.core program. `main()` is called once per cell per frame; `post()`
/// runs afterwards and can overlay anything onto the finished buffer.
protocol Program {
	/// Mutate `cell` to set the character and its style. Fields left untouched
	/// keep last frame's value — the merge semantics of play.core's `main()`.
	func main(_ coord: Coord, _ context: Context, _ buffer: Buffer, _ cell: inout Cell)
	func post(_ context: Context, _ buffer: Buffer)
}

extension Program {
	func post(_ context: Context, _ buffer: Buffer) {}
}

// MARK: - Runner

/// Drives a program: owns the clock and the buffer, and fills the buffer one
/// frame at a time.
final class Runner {
	/// Settable so a program reconfigured from the Options sheet replaces the
	/// running one without restarting the clock.
	var program: Program
	let buffer = Buffer()

	private(set) var frame = 0
	/// Milliseconds of animation elapsed, paused along with the saver.
	private(set) var time: Double = 0

	init(program: Program) {
		self.program = program
	}

	/// Advances the clock by `deltaMS` and repaints the buffer.
	@discardableResult
	func step(deltaMS: Double,
	          cols: Int,
	          rows: Int,
	          metrics: Metrics,
	          size: CGSize,
	          fps: Double) -> Context {

		time += deltaMS
		frame += 1
		buffer.resize(cols: cols, rows: rows)

		let context = Context(frame: frame,
		                      time: time,
		                      cols: buffer.cols,
		                      rows: buffer.rows,
		                      metrics: metrics,
		                      width: size.width,
		                      height: size.height,
		                      fps: fps)

		// The cell is copied out and back rather than passed as an `inout` into
		// `buffer.cells`: a program is free to read the buffer inside main(),
		// and an outstanding write access to the same array would trap.
		for y in 0..<context.rows {
			for x in 0..<context.cols {
				let index = y * context.cols + x
				var cell = buffer[x, y]
				program.main(Coord(x: x, y: y, index: index), context, buffer, &cell)
				buffer.set(cell, x: x, y: y)
			}
		}

		program.post(context, buffer)
		return context
	}
}
