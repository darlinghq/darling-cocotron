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
original.cornerRadius = 4
original.transform = CATransform3DMakeScale(2, 2, 1)
original.contentsGravity = CALayerContentsGravity(rawValue: "center")
original.backgroundColor = CGColorCreateGenericGray(0.5, 1)
original.shadowOffset = CGSize(width: 1, height: -1)
let mask = CALayer()
original.mask = mask
original.addSublayer(CALayer())

let copy = TaggedLayer(layer: original)
check(copy.tag == 7, "subclass state")
check(copy.bounds == original.bounds && copy.position == original.position, "geometry")
check(copy.opacity == 0.25 && copy.cornerRadius == 4, "appearance")
check(CATransform3DEqualToTransform(copy.transform, original.transform), "transform")
check(copy.contentsGravity == original.contentsGravity && copy.backgroundColor === original.backgroundColor, "gravity and color")
check(copy.shadowOffset == CGSize(width: 1, height: -1), "shadow offset")
check(copy.mask === mask && original.mask === mask, "mask is shared, not moved")
check((copy.sublayers ?? []).isEmpty && copy.superlayer == nil, "no tree position")

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
check(shapeCopy.lineWidth == 5 && shapeCopy.miterLimit == 4 && shapeCopy.fillColor == nil, "shape state")
check(shapeCopy.path != nil && CGPathGetBoundingBox(shapeCopy.path!) == CGRect(x: 0, y: 0, width: 3, height: 3), "shape path")
let plainAsShape = ShapeSubclass(layer: CALayer())
check(plainAsShape.lineWidth == 1 && plainAsShape.miterLimit == 10, "shape defaults when copying a plain layer")

let basic = CABasicAnimation(keyPath: "opacity")
let spring = CASpringAnimation(keyPath: "position")
check(basic.keyPath == "opacity" && type(of: basic) == CABasicAnimation.self, "CABasicAnimation(keyPath:)")
check(spring.keyPath == "position" && type(of: spring) == CASpringAnimation.self, "CASpringAnimation(keyPath:)")

if failures == 0 {
    print("ALL PASSED")
} else {
    exit(1)
}
