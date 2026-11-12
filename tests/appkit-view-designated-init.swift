import AppKit

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        failures += 1
    }
}

// Overriding both designated initializers inherits init(), as on macOS; it reaches the override through -initWithFrame:.
class FrameView: NSView {
    var initializedWithFrame = false
    override init(frame frameRect: NSRect) {
        initializedWithFrame = true
        super.init(frame: frameRect)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

class SubFrameView: FrameView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

let view = FrameView()
check(view.initializedWithFrame, "FrameView() goes through init(frame:)")
let sub = SubFrameView()
check(sub.initializedWithFrame && sub.subviews.isEmpty, "SubFrameView() goes through init(frame:)")
let framed = FrameView(frame: NSRect(x: 0, y: 0, width: 30, height: 20))
check(framed.frame.width == 30 && framed.frame.height == 20, "init(frame:) \(framed.frame)")

if failures == 0 {
    print("ALL PASSED")
} else {
    exit(1)
}
