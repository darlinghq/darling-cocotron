import QuartzCore

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        failures += 1
    }
}

let layer = CALayer()
check(layer.minificationFilter == .linear, "default minificationFilter")
layer.magnificationFilter = .nearest
check(layer.magnificationFilter == .nearest, "magnificationFilter round trip")
check(CALayerContentsFilter.trilinear.rawValue == "trilinear", "trilinear raw value")
check(layer.contentsGravity == .resize, "default contentsGravity")
layer.contentsGravity = .bottomRight
check(layer.contentsGravity == .bottomRight, "contentsGravity round trip")
check(CALayerContentsFormat.gray8Uint != .RGBA8Uint, "gray8Uint")

let shape = CAShapeLayer()
check(shape.fillRule == .nonZero, "default fillRule")
shape.fillRule = .evenOdd
check(shape.fillRule == .evenOdd && shape.fillRule.rawValue == "even-odd", "fillRule round trip")
check(shape.lineCap == .butt && shape.lineJoin == .miter, "default lineCap/lineJoin")
shape.lineCap = .round
shape.lineJoin = .bevel
check(shape.lineCap == .round && shape.lineJoin == .bevel, "lineCap/lineJoin round trip")
check(CAShapeLayerLineCap.square.rawValue == "square", "square raw value")

let animation = CABasicAnimation()
animation.fillMode = .backwards
check(animation.fillMode == .backwards, "fillMode round trip")
check(CAMediaTimingFillMode.forwards.rawValue == "forwards", "forwards raw value")

let linear: CAMediaTimingFunction = CAMediaTimingFunction(name: .linear)
var point: [CGFloat] = [0, 0]
linear.getControlPoint(at: 2, values: &point)
check(point == [1, 1], "linear timing function control point")

if failures == 0 {
    print("ALL PASSED")
} else {
    exit(1)
}
