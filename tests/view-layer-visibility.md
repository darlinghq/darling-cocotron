Run `view-layer-visibility.m` against the rebuilt AppKit and QuartzCore, with
assertions enabled (`-UNDEBUG`). Link Foundation, AppKit and QuartzCore and use
the matching public headers.

The executable tests actual NSView methods. Controlled sinks observe visibility
propagation to a layer and its native context, including ancestor changes and
reparenting a non-layer-backed container. Real CALayer objects check hidden
backing-layer creation and explicit replacement. The sink references are
borrowed and removed before view teardown. This is not an OpenGL/X11 mapping
test; native-window integration also requires a GUI run.

Expected final output:
`PASS view and ancestor visibility reach layer and native context`
