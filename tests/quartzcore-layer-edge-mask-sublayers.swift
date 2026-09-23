import QuartzCore

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        failures += 1
    }
}

let layer = CALayer()
let all: CAEdgeAntialiasingMask = [.layerLeftEdge, .layerRightEdge, .layerBottomEdge, .layerTopEdge]
check(layer.edgeAntialiasingMask == all, "default mask is every edge (\(layer.edgeAntialiasingMask.rawValue))")
layer.edgeAntialiasingMask = [.layerTopEdge, .layerLeftEdge]
check(layer.edgeAntialiasingMask.rawValue == (1 << 3 | 1 << 0), "mask round trip")

let child = CALayer()
layer.addSublayer(child)
let sublayers: [CALayer] = layer.sublayers ?? []
check(sublayers.count == 1 && sublayers[0] === child, "typed sublayers")

if failures == 0 {
    print("ALL PASSED")
} else {
    exit(1)
}
