import AppKit
import CoreText

/// Deterministic, allocation-free Matrix rain.
///
/// Each column is a falling head with a fading trail. The glyph in a cell is a hash of
/// (column salt, row, slow frame counter), so nothing is stored per cell and the glyphs
/// flicker on their own. One CTLine per glyph is built once and drawn with the context's
/// fill color, so a frame is only `setFillColor` + `CTLineDraw` per visible cell.
final class MatrixRain {
    private struct Column {
        var head: CGFloat
        var speed: CGFloat
        var trail: Int
        var salt: UInt32
    }

    let columnWidth: CGFloat
    let rowHeight: CGFloat

    private var columns: [Column] = []
    private var rows = 1
    private var size = CGSize.zero
    private var frame: UInt32 = 0
    private var rng: UInt32

    init(columnWidth: CGFloat = 7, rowHeight: CGFloat = 8.5, seed: UInt32 = 0x9E37_79B9) {
        self.columnWidth = columnWidth
        self.rowHeight = rowHeight
        self.rng = seed == 0 ? 1 : seed
    }

    /// Half-width katakana U+FF66...U+FF9D and the digits 0-9, 7.5pt monospaced.
    /// The text color comes from the context fill color (kCTForegroundColorFromContextAttributeName).
    /// SF Mono has no katakana; CTLine falls back to a system Japanese font automatically.
    private static let glyphLines: [CTLine] = {
        var scalars: [Unicode.Scalar] = []
        for value in UInt32(0xFF66)...UInt32(0xFF9D) {
            if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
        }
        for value in UInt32(0x30)...UInt32(0x39) {
            if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 7.5, weight: .regular),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        return scalars.map { scalar in
            let string = NSAttributedString(string: String(Character(scalar)), attributes: attributes)
            return CTLineCreateWithAttributedString(string as CFAttributedString)
        }
    }()

    /// Call with the drawing rect size; cheap no-op when unchanged.
    func layout(size newSize: CGSize) {
        guard newSize != size, newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        rows = max(1, Int((newSize.height / rowHeight).rounded(.up)))
        let count = max(1, Int((newSize.width / columnWidth).rounded(.up)))
        if columns.count > count { columns.removeLast(columns.count - count) }
        while columns.count < count { columns.append(spawn(initial: true)) }
    }

    /// Advance one frame (5 fps).
    func step() {
        frame &+= 1
        let limit = CGFloat(rows)
        for i in columns.indices {
            columns[i].head += columns[i].speed
            if columns[i].head - CGFloat(columns[i].trail) > limit {
                columns[i] = spawn(initial: false)
            }
        }
    }

    /// Draws the current frame into `rect` (unflipped coordinates). Caller clips.
    func draw(in ctx: CGContext, rect: CGRect, intensity: CGFloat) {
        let lines = MatrixRain.glyphLines
        let glyphCount = UInt32(lines.count)
        ctx.textMatrix = .identity
        let top = rect.maxY
        let baselineOffset = (rowHeight - 7.5) / 2 + 1
        for c in columns.indices {
            let col = columns[c]
            let x = rect.minX + CGFloat(c) * columnWidth + 0.5
            let headRow = Int(col.head.rounded(.down))
            var k = 0
            while k <= col.trail {
                let row = headRow - k
                if row >= 0 && row < rows {
                    var h = col.salt &+ UInt32(truncatingIfNeeded: row) &* 2_654_435_761 &+ ((frame &+ col.salt) / 4)
                    h ^= h >> 15
                    h = h &* 2_246_822_519
                    h ^= h >> 13
                    if k == 0 {
                        // Head: #C8FFD4 at 70%.
                        ctx.setFillColor(red: 0.784, green: 1, blue: 0.831, alpha: 0.7 * intensity)
                    } else {
                        // Tail: #00FF41 from 35% fading towards 0.
                        let fade = 1 - CGFloat(k - 1) / CGFloat(col.trail)
                        ctx.setFillColor(red: 0, green: 1, blue: 0.255, alpha: 0.35 * fade * intensity)
                    }
                    ctx.textPosition = CGPoint(x: x, y: top - CGFloat(row + 1) * rowHeight + baselineOffset)
                    CTLineDraw(lines[Int(h % glyphCount)], ctx)
                }
                k += 1
            }
        }
    }

    // MARK: - Private

    private func nextRandom() -> UInt32 {
        // xorshift32
        rng ^= rng << 13
        rng ^= rng >> 17
        rng ^= rng << 5
        return rng
    }

    private func unit() -> CGFloat {
        CGFloat(nextRandom() % 10_000) / 10_000
    }

    private func spawn(initial: Bool) -> Column {
        let trail = 2 + Int(nextRandom() % 5)
        // 0.8 to 2.5 rows per second at 5 fps.
        let speed = 0.16 + unit() * 0.34
        let head: CGFloat = initial
            ? unit() * CGFloat(rows + trail)
            : -unit() * CGFloat(rows) * 1.5 // a gap before the column falls again
        return Column(head: head, speed: speed, trail: trail, salt: nextRandom())
    }
}
