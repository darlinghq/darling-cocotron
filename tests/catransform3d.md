# CATransform3D function family

Build catransform3d.m against QuartzCore and run it. Every check prints PASS or FAIL and the program exits nonzero if any failed. No display, compositor or Apple app is needed: the transforms are pure functions over a struct.

The expected values come from Core Animation's documented semantics in the row-vector convention the struct uses, where a point is transformed as `v' = v * M` and the translation sits in m41..m43. Rotation is checked against `CGAffineTransformMakeRotation`'s sign convention, so a positive angle about +z sends (1,0,0) to (0,1,0); concatenation is checked with two orders that give different answers, which is what catches a transposed multiply; inversion is checked by round trip and against a singular matrix, which must come back unchanged rather than filled with infinities.

The pre-fix library declares only CATransform3DIdentity, so this probe fails to compile.
