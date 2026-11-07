# CALayerContext failed-initialization regression

Build layer-context-failure.m against Foundation and QuartzCore using the internal QuartzCore headers. Run without registering a native EGL display. Context creation fails; the initializer must return nil, not an object containing a NULL GL context. The pre-fix library returns a nonnil object and this probe fails.

No compositor or Apple app is launched. This tests failure handling only; successful layer rendering and native Wayland subwindows require separate tests.
