# View backing-layer lifecycle

Run `ruby tests/view-layer-lifecycle.rb GNUSTEP_ROOT`. The runner extracts the
six actual NSView methods changed or used by this port. GNUstep provides object
dispatch; layer/context/window adapters record parent relationships, context
creation, binding, invalidation and destruction. No display server is required.

Cases cover detached deferral, first attachment, repeated attachment, movement
between windows and layered parents, removal in NSView's superview-then-window
order, context failure followed by explicit retry, and promotion of a child
that still wants a layer after its parent's layer is removed. Allocation and
destruction counts balance. Unchanged upstream fails detached deferral.

The fake layer records a non-owning parent pointer; it is not CALayer's actual
retaining hierarchy. Context invalidation, rendering timers, native subwindows,
layer geometry and callback reentrancy are not validated. Failure retry uses
the attachment helper explicitly, not a claimed automatic retry scheduler.

Before merge, build/link AppKit and run real X11 and Wayland fixtures moving
layer-backed views between layered/unlayered parents and windows. Verify old
native surfaces disappear, new surfaces display in the correct location, z-order
and transforms are preserved, and repeated moves do not leak CGL contexts.
Exercise CGL failure and removal during callbacks. Root setLayer replacement
and broader layer rendering changes are outside this port.
