import CoreGraphics

// CGPath.h is nullability audited, so CGMutablePath() is not failable.
func use(_ path: CGMutablePath) {}

let mutablePath = CGMutablePath()
use(mutablePath)
let path: CGPath = mutablePath
_ = path
