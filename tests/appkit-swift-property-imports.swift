import AppKit

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        failures += 1
    }
}

// These import as properties with Apple's optionality, so the spellings below typecheck as they do on macOS.
let parent: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
let appearance = parent.effectiveAppearance
check(appearance.isKind(of: NSAppearance.self), "effectiveAppearance")

let controller = NSViewController()
controller.view = parent
let view = controller.view
check(view.superview == nil && view === parent, "NSViewController.view")

let control: NSControl = NSControl(frame: .zero)
control.target = controller
check(control.target === controller, "NSControl.target")
control.target = nil
check(control.target == nil, "NSControl.target cleared")

let image: NSImage = NSImage(size: NSSize(width: 1, height: 1))
check(image.accessibilityDescription == nil, "no accessibility description")
image.accessibilityDescription = "dot"
if let description = image.accessibilityDescription, !description.isEmpty {
    check(description == "dot", "accessibilityDescription \(description)")
} else {
    check(false, "accessibilityDescription not stored")
}

if failures == 0 {
    print("ALL PASSED")
} else {
    exit(1)
}
