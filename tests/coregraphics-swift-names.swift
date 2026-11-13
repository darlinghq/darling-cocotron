import CoreGraphics

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        failures += 1
    }
}

let rect = CGRect(x: 1, y: 2, width: 4, height: 6)
let ellipse: CGPath = CGPath(ellipseIn: rect, transform: nil)
check(ellipse.boundingBox == rect, "ellipse bounding box \(ellipse.boundingBox)")
let rounded: CGPath = CGPath(roundedRect: rect, cornerWidth: 1, cornerHeight: 1, transform: nil)
check(rounded.boundingBox == rect, "rounded rect bounding box \(rounded.boundingBox)")

let mode: CGBlendMode = .xor
check(mode.rawValue == 25 && mode == CGBlendMode(rawValue: 25), "xor raw value")

if failures == 0 {
    print("ALL PASSED")
} else {
    exit(1)
}
