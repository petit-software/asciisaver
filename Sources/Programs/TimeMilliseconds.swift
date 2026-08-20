//
//  TimeMilliseconds.swift
//
//  Port of play.core's src/programs/basics/time_milliseconds.js
//  ("Time: milliseconds" by ertdfgcvb) — https://play.ertdfgcvb.xyz
//
//  The original, verbatim:
//
//      const pattern = 'ABCxyz01═|+:. '
//
//      export function main(coord, context, cursor, buffer) {
//          const t = context.time * 0.0001
//          const x = coord.x
//          const y = coord.y
//          const o = Math.sin(y * Math.sin(t) * 0.2 + x * 0.04 + t) * 20
//          const i = Math.round(Math.abs(x + y + o)) % pattern.length
//          return { char: pattern[i], fontWeight: '100' }
//      }
//

import AppKit

struct TimeMilliseconds: Program {

	private let pattern = Array("ABCxyz01═|+:. ".unicodeScalars)

	/// CSS `font-weight: 100` is the thinnest weight — AppKit's `.ultraLight`.
	private let weight = NSFont.Weight.ultraLight

	/// Draws the runtime overlay from the original's `post()`.
	var showInfo = false

	func main(_ coord: Coord, _ context: Context, _ buffer: Buffer, _ cell: inout Cell) {
		let t = context.time * 0.0001
		let x = Double(coord.x)
		let y = Double(coord.y)
		let o = sin(y * sin(t) * 0.2 + x * 0.04 + t) * 20
		// JS `Math.round` and Swift `rounded()` agree for non-negative values.
		let i = Int(abs(x + y + o).rounded()) % pattern.count

		cell.char = pattern[i]
		cell.fontWeight = weight
	}

	func post(_ context: Context, _ buffer: Buffer) {
		guard showInfo else { return }
		// The style overrides the original passes to drawInfo().
		var style = BoxStyle()
		style.color = .white
		style.backgroundColor = .royalBlue
		style.shadow = .gray
		style.fontWeight = .regular
		drawInfo(context, buffer, style: style)
	}
}
