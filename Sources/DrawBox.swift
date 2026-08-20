//
//  DrawBox.swift
//  Port of play.core's modules/drawbox.js — text boxes drawn into the cell
//  buffer, plus the runtime info overlay used by the time_milliseconds demo.
//

import AppKit

struct BorderStyle {
	var topLeft: UnicodeScalar
	var topRight: UnicodeScalar
	var bottomRight: UnicodeScalar
	var bottomLeft: UnicodeScalar
	var top: UnicodeScalar
	var bottom: UnicodeScalar
	var left: UnicodeScalar
	var right: UnicodeScalar
	var background: UnicodeScalar = " "

	static let round = BorderStyle(topLeft: "╭", topRight: "╮",
	                               bottomRight: "╯", bottomLeft: "╰",
	                               top: "─", bottom: "─",
	                               left: "│", right: "│")

	static let double = BorderStyle(topLeft: "╔", topRight: "╗",
	                                bottomRight: "╝", bottomLeft: "╚",
	                                top: "═", bottom: "═",
	                                left: "║", right: "║")

	static let single = BorderStyle(topLeft: "┌", topRight: "┐",
	                                bottomRight: "┘", bottomLeft: "╰",
	                                top: "─", bottom: "─",
	                                left: "│", right: "│")

	static let none = BorderStyle(topLeft: " ", topRight: " ",
	                              bottomRight: " ", bottomLeft: " ",
	                              top: " ", bottom: " ",
	                              left: " ", right: " ")
}

/// A shadow is either a fill character or a recolor of whatever is underneath.
struct ShadowStyle {
	var char: UnicodeScalar?
	var color: RGBA?
	var backgroundColor: RGBA?

	static let none    = ShadowStyle()
	static let light   = ShadowStyle(char: "░")
	static let medium  = ShadowStyle(char: "▒")
	static let dark    = ShadowStyle(char: "▓")
	static let solid   = ShadowStyle(char: "█")
	static let gray    = ShadowStyle(color: .dimGray, backgroundColor: .lightGray)

	var isVisible: Bool { char != nil || color != nil || backgroundColor != nil }
}

struct BoxStyle {
	var x = 2
	var y = 1
	/// 0 means "size to the text".
	var width = 0
	var height = 0
	var paddingX = 2
	var paddingY = 1
	var backgroundColor: RGBA = .white
	var color: RGBA = .black
	var fontWeight: NSFont.Weight = .regular
	var shadow: ShadowStyle = .none
	var border: BorderStyle = .round
	var shadowX = 2
	var shadowY = 1
}

func drawBox(_ text: String, style: BoxStyle, buffer: Buffer) {
	var boxWidth = style.width
	var boxHeight = style.height

	if boxWidth == 0 || boxHeight == 0 {
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
		let maxWidth = lines.map(\.count).max() ?? 0
		if boxWidth == 0 { boxWidth = maxWidth + style.paddingX * 2 }
		if boxHeight == 0 { boxHeight = lines.count + style.paddingY * 2 }
	}
	guard boxWidth > 1, boxHeight > 1 else { return }

	let x1 = style.x
	let y1 = style.y
	let x2 = x1 + boxWidth - 1
	let y2 = y1 + boxHeight - 1
	let border = style.border

	// Background
	buffer.setRect(Cell(char: border.background,
	                    color: style.color,
	                    backgroundColor: style.backgroundColor,
	                    fontWeight: style.fontWeight),
	               x: x1, y: y1, width: boxWidth, height: boxHeight)

	// Corners
	buffer.merge(x: x1, y: y1, char: border.topLeft)
	buffer.merge(x: x2, y: y1, char: border.topRight)
	buffer.merge(x: x2, y: y2, char: border.bottomRight)
	buffer.merge(x: x1, y: y2, char: border.bottomLeft)

	// Edges
	buffer.mergeRect(x: x1 + 1, y: y1, width: boxWidth - 2, height: 1, char: border.top)
	buffer.mergeRect(x: x1 + 1, y: y2, width: boxWidth - 2, height: 1, char: border.bottom)
	buffer.mergeRect(x: x1, y: y1 + 1, width: 1, height: boxHeight - 2, char: border.left)
	buffer.mergeRect(x: x2, y: y1 + 1, width: 1, height: boxHeight - 2, char: border.right)

	// Shadow, offset down-right of the box
	if style.shadow.isVisible {
		let ox = style.shadowX
		let oy = style.shadowY
		let shadow = style.shadow
		buffer.mergeRect(x: x1 + ox, y: y2 + 1, width: boxWidth, height: oy,
		                 char: shadow.char, color: shadow.color,
		                 backgroundColor: shadow.backgroundColor)
		buffer.mergeRect(x: x2 + 1, y: y1 + oy, width: ox, height: boxHeight - oy,
		                 char: shadow.char, color: shadow.color,
		                 backgroundColor: shadow.backgroundColor)
	}

	// Text
	buffer.mergeText(text,
	                 x: x1 + style.paddingX,
	                 y: y1 + style.paddingY,
	                 color: style.color,
	                 backgroundColor: style.backgroundColor,
	                 fontWeight: style.fontWeight)
}

/// The runtime readout from drawbox.js. The playground's `cursor` row is
/// dropped — a screen saver has no pointer, and any mouse movement dismisses it.
func drawInfo(_ context: Context, _ buffer: Buffer, style: BoxStyle) {
	var info = ""
	info += "FPS         \(Int(context.fps.rounded()))\n"
	info += "frame       \(context.frame)\n"
	info += "time        \(Int(context.time.rounded(.down)))\n"
	info += "size        \(context.cols)×\(context.rows)\n"
	info += "font aspect \(String(format: "%.2f", context.metrics.aspect))"

	var boxStyle = style
	boxStyle.width = 24
	drawBox(info, style: boxStyle, buffer: buffer)
}
