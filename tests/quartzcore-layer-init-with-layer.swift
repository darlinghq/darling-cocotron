import QuartzCore

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        failures += 1
    }
}

final class TaggedLayer: CALayer {
    var tag = 0
    override init() { super.init() }
    override init(layer: Any) {
        tag = (layer as! TaggedLayer).tag
        super.init(layer: layer)
    }
}

let original = TaggedLayer()
original.tag = 7
original.bounds = CGRect(x: 0, y: 0, width: 30, height: 20)
original.position = CGPoint(x: 5, y: 6)
original.opacity = 0.25
original.backgroundColor = CGColorCreateGenericGray(0.5, 1)
original.addSublayer(CALayer())

// The layer's own state is copied by the subclass; the copy of the layer's
// properties is left at the defaults, as on macOS (QUIRK in CALayer.m).
let copy = TaggedLayer(layer: original)
check(copy.tag == 7, "subclass state")
check(copy.bounds == .zero && copy.position == .zero, "geometry is default")
check(copy.opacity == 1 && copy.backgroundColor == nil, "appearance is default")
check((copy.sublayers ?? []).isEmpty && copy.superlayer == nil, "no tree position")
check(original.opacity == 0.25 && (original.sublayers ?? []).count == 1, "the original is untouched")

// Any object is accepted as the argument.
let fromOther = CALayer(layer: "not a layer")
check(fromOther.opacity == 1, "non-layer argument")

final class ShapeSubclass: CAShapeLayer {
    override init() { super.init() }
    override init(layer: Any) { super.init(layer: layer) }
}
let shape = ShapeSubclass()
shape.path = CGPath(rect: CGRect(x: 0, y: 0, width: 3, height: 3), transform: nil)
shape.lineWidth = 5
shape.miterLimit = 4
shape.fillColor = nil
let shapeCopy = ShapeSubclass(layer: shape)
check(shapeCopy.lineWidth == 1 && shapeCopy.miterLimit == 10 && shapeCopy.fillColor != nil && shapeCopy.path == nil,
      "shape layer copy has the shape defaults")

let basic = CABasicAnimation(keyPath: "opacity")
let spring = CASpringAnimation(keyPath: "position")
check(basic.keyPath == "opacity" && type(of: basic) == CABasicAnimation.self, "CABasicAnimation(keyPath:)")
check(spring.keyPath == "position" && type(of: spring) == CASpringAnimation.self, "CASpringAnimation(keyPath:)")

if failures == 0 {
    print("ALL PASSED")
} else {
    exit(1)
}
