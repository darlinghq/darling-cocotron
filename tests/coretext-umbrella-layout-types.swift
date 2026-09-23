import CoreText

// The layout types must be reachable through `import CoreText`, as on macOS.
enum Layout {
    case line(CTLine)
    case run(CTRun)
    case frame(CTFrame)
    case framesetter(CTFramesetter)
    case typesetter(CTTypesetter)
}

func glyphs(_ line: CTLine) -> CFIndex { CTLineGetGlyphCount(line) }
let truncation: CTLineTruncationType = .end
let bounds: CTLineBoundsOptions = [.useOpticalBounds, .excludeTypographicLeading]

if truncation.rawValue == 1 && bounds.rawValue == (1 << 4 | 1 << 0) {
    print("ALL PASSED")
} else {
    print("FAIL: truncation \(truncation.rawValue), bounds \(bounds.rawValue)")
    exit(1)
}
