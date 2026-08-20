//
//  GridRenderer.swift
//  Draws a Buffer with Core Text.
//
//  A full-screen grid is tens of thousands of cells, and every one of them
//  changes every frame, so drawing cell by cell is not an option. Instead the
//  grid is flattened into one glyph array per distinct style and handed to
//  CTFontDrawGlyphs in a single call. The time_milliseconds program uses one
//  weight and one color, so the whole screen is a single draw.
//

import AppKit
import CoreText

/// The cell aspect ratio of the original playground: LL Simple Console has a
/// 0.528em advance and the page sets `line-height: 1.2`. Deriving the row
/// height from this keeps a program's proportions identical under any font.
let playCoreCellAspect: CGFloat = 0.528 / 1.2

/// Foreground/background defaults for cells that set no color of their own.
struct Theme {
	var foreground: RGBA
	var background: RGBA

	static let light = Theme(foreground: .black, background: .white)
	static let dark  = Theme(foreground: .white, background: .black)
}

final class GridRenderer {

	/// Glyphs batched by style; reused across frames so a steady state stops
	/// allocating entirely.
	private struct Batch {
		var color: RGBA
		var weight: NSFont.Weight
		var glyphs: [CGGlyph] = []
		var positions: [CGPoint] = []
	}

	private var batches: [Batch] = []
	private var fonts: [CGFloat: CTFont] = [:]
	private var glyphCaches: [CGFloat: [UInt16: CGGlyph]] = [:]
	private var fontSize: CGFloat = 0

	/// Font metrics for a size, with the row height stretched so that a cell
	/// keeps the playground's 0.44 width-to-height ratio.
	func metrics(forFontSize size: CGFloat) -> Metrics {
		let font = font(size: size, weight: .regular)
		var glyph = CGGlyph()
		var character: UniChar = 0x58 // "X"
		let advance: CGFloat
		if CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) {
			advance = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, nil, 1)
		} else {
			advance = size * 0.6
		}

		let cellWidth = advance
		let lineHeight = cellWidth / playCoreCellAspect
		let ascent = CTFontGetAscent(font)
		let descent = CTFontGetDescent(font)
		// CSS half-leading: split the slack above and below the text box.
		let baselineOffset = (lineHeight - (ascent + descent)) / 2 + ascent

		return Metrics(cellWidth: cellWidth,
		               lineHeight: lineHeight,
		               fontSize: size,
		               baselineOffset: baselineOffset)
	}

	// MARK: Drawing

	/// Renders `buffer` into `ctx`. `viewHeight` flips row 0 to the top, since
	/// an unflipped AppKit view draws from the bottom-left.
	func render(buffer: Buffer,
	            metrics: Metrics,
	            theme: Theme,
	            defaultWeight: NSFont.Weight,
	            size: CGSize,
	            in ctx: CGContext) {

		if fontSize != metrics.fontSize {
			fontSize = metrics.fontSize
			fonts.removeAll()
			glyphCaches.removeAll()
		}

		// 1. Clear.
		ctx.setFillColor(theme.background.cgColor)
		ctx.fill(CGRect(origin: .zero, size: size))

		guard buffer.cols > 0, buffer.rows > 0 else { return }

		let cellWidth = metrics.cellWidth
		let lineHeight = metrics.lineHeight
		let viewHeight = size.height

		// 2. Cell backgrounds, coalesced into horizontal runs.
		drawBackgrounds(buffer: buffer,
		                cellWidth: cellWidth,
		                lineHeight: lineHeight,
		                viewHeight: viewHeight,
		                theme: theme,
		                in: ctx)

		// 3. Glyphs, grouped by (color, weight).
		for i in batches.indices {
			batches[i].glyphs.removeAll(keepingCapacity: true)
			batches[i].positions.removeAll(keepingCapacity: true)
		}

		for y in 0..<buffer.rows {
			let baselineY = viewHeight - (CGFloat(y) * lineHeight + metrics.baselineOffset)
			let rowOffset = y * buffer.cols
			for x in 0..<buffer.cols {
				let cell = buffer.cells[rowOffset + x]
				let scalar = cell.char.value
				// Spaces carry no ink; their background was already painted.
				if scalar == 0x20 || scalar == 0 { continue }

				let color = cell.color ?? theme.foreground
				let weight = cell.fontWeight ?? defaultWeight
				guard let glyph = glyph(for: scalar, weight: weight) else { continue }

				let index = batchIndex(color: color, weight: weight)
				batches[index].glyphs.append(glyph)
				batches[index].positions.append(CGPoint(x: CGFloat(x) * cellWidth,
				                                        y: baselineY))
			}
		}

		ctx.saveGState()
		ctx.textMatrix = .identity
		for batch in batches where !batch.glyphs.isEmpty {
			ctx.setFillColor(batch.color.cgColor)
			let ctFont = font(size: metrics.fontSize, weight: batch.weight)
			CTFontDrawGlyphs(ctFont, batch.glyphs, batch.positions, batch.glyphs.count, ctx)
		}
		ctx.restoreGState()
	}

	private func drawBackgrounds(buffer: Buffer,
	                             cellWidth: CGFloat,
	                             lineHeight: CGFloat,
	                             viewHeight: CGFloat,
	                             theme: Theme,
	                             in ctx: CGContext) {
		for y in 0..<buffer.rows {
			let rowOffset = y * buffer.cols
			let top = viewHeight - CGFloat(y + 1) * lineHeight
			var runStart = 0
			var runColor: RGBA? = nil

			func flush(end: Int) {
				guard let color = runColor, color != theme.background, end > runStart else { return }
				ctx.setFillColor(color.cgColor)
				ctx.fill(CGRect(x: CGFloat(runStart) * cellWidth,
				                y: top,
				                width: CGFloat(end - runStart) * cellWidth,
				                height: lineHeight))
			}

			for x in 0..<buffer.cols {
				let color = buffer.cells[rowOffset + x].backgroundColor
				if color != runColor {
					flush(end: x)
					runStart = x
					runColor = color
				}
			}
			flush(end: buffer.cols)
		}
	}

	// MARK: Font & glyph caches

	private func batchIndex(color: RGBA, weight: NSFont.Weight) -> Int {
		for (i, batch) in batches.enumerated() where batch.color == color && batch.weight == weight {
			return i
		}
		batches.append(Batch(color: color, weight: weight))
		return batches.count - 1
	}

	private func font(size: CGFloat, weight: NSFont.Weight) -> CTFont {
		if let cached = fonts[weight.rawValue] { return cached }
		let font = NSFont.monospacedSystemFont(ofSize: size, weight: weight) as CTFont
		fonts[weight.rawValue] = font
		return font
	}

	private func glyph(for scalar: UInt32, weight: NSFont.Weight) -> CGGlyph? {
		// Everything the ported programs draw lives in the BMP.
		guard scalar <= 0xFFFF else { return nil }
		let unit = UInt16(scalar)

		if let cached = glyphCaches[weight.rawValue]?[unit] {
			return cached == 0 ? nil : cached
		}

		var character = unit
		var glyph = CGGlyph()
		let ok = CTFontGetGlyphsForCharacters(font(size: fontSize, weight: weight),
		                                      &character, &glyph, 1)
		let resolved = ok ? glyph : 0
		glyphCaches[weight.rawValue, default: [:]][unit] = resolved
		return resolved == 0 ? nil : resolved
	}
}
