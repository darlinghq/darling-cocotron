# QuartzCore: preserve atomic property semantics with legacy extra ivars

The fragile-ABI extra-ivar property macros replace atomic properties with unprotected accessors. Concurrent setters and getters can release an object while a reader uses it. Serialize the matching accessors and retain/autorelease object reads while holding the same object lock. Keep nonatomic declarations unchanged.

The previously executed Foundation workload fails with upstream i386 accessors (RC134) and passes after patching (RC0): 8,800 objects created/destroyed, zero bad reads. x86_64 control RC0. The current upstream header is byte-identical. This does not qualify concurrent container copy/deallocation or all of AppKit.

Sources: cfa659db in fr4nck/darling-cocotron. These are D4rling-authored fixtures under GPL-3.0-or-later; existing production notices remain unchanged.
Build Objective-C fixtures with manual reference counting for i386 and x86_64 against the installed frameworks. Run one scenario per isolated guest process, with bounded timeout and stdin closed.
No arguments. Expect ABI26_GUEST_RETAIN_COPY_STRESS=PASS and RC0.
