import Foundation
import QuartzCore

// CATransform3D crosses to Objective-C as an NSValue holding the struct, through the
// Swift overlay's _ObjectiveCBridgeable conformance (as/as? casts, animation values) and
// through the NSValue category (NSValue(caTransform3D:), caTransform3DValue).

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok {
        print("FAIL: \(what)")
        failures += 1
    }
}

var transform = CATransform3DMakeTranslation(1, 2, 3)
transform = CATransform3DScale(transform, 2, 4, 8)

// The category.
let value = NSValue(caTransform3D: transform)
check(String(cString: value.objCType) == "{CATransform3D=dddddddddddddddd}", "NSValue encoding")
check(CATransform3DEqualToTransform(value.caTransform3DValue, transform), "category round trip")
check(value.caTransform3DValue.m41 == 1 && value.caTransform3DValue.m42 == 2 && value.caTransform3DValue.m43 == 3
      && value.caTransform3DValue.m22 == 4, "fields survive the NSValue")

// Bridging casts.
let bridged = transform as NSValue
check(CATransform3DEqualToTransform(bridged.caTransform3DValue, transform), "as NSValue")
check((value as? CATransform3D).map { CATransform3DEqualToTransform($0, transform) } ?? false, "as? CATransform3D")
check(CATransform3DEqualToTransform(value as! CATransform3D, transform), "as! CATransform3D")

let point = NSValue(point: NSPoint(x: 1, y: 2))
check((point as? CATransform3D) == nil, "a point does not bridge to CATransform3D")

// Animation values hold the transform as an NSValue.
let animation = CABasicAnimation(keyPath: "transform")
animation.fromValue = CATransform3DIdentity
animation.toValue = transform
check(animation.fromValue is NSValue && animation.toValue is NSValue, "animation values are NSValues")
check(CATransform3DEqualToTransform((animation.toValue as! NSValue).caTransform3DValue, transform), "animation toValue")

if failures == 0 {
    print("PASS")
}
exit(Int32(failures))
