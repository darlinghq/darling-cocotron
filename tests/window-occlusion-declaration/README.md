This change declares the public enum and readonly property only. It implements
no getter, compositor occlusion reporting, notification delivery or visibility
fallback. A runtime caller remains unsupported until a separate implementation.

Exact syntax regression from this repository root (`$BUILD` is a configured Darling AppKit build tree):

```sh
python3 tests/window-occlusion-declaration/build.py "$BUILD" --baseline
python3 tests/window-occlusion-declaration/build.py "$BUILD"
```

Donor header fails1 (property/enumerator missing); candidate compiles0. This
matches the published MIT Dodge source's occlusion delegate callback, without
claiming that callback is invoked during a real game run.

Apple's public documentation JSON specifies readonly NSWindowOcclusionState
and NSUInteger type. The Visible bit is independently published in MIT
[dotnet/macios API binding source](https://github.com/dotnet/macios/blob/354c2a645855dfdf774cc5e098cd214764f475b5/src/AppKit/Enums.cs#L4441).
No runtime algorithm, undocumented default or scraped SDK header is introduced.
