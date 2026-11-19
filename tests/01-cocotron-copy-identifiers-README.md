# AppKit: preserve identifier ownership when copying cells and menus

NSCell and NSMenu copy their extra ivars as raw pointers, but both copies release the identifier. Destroying one copy can leave the other with a dangling identifier. Copy the identifier into each destination.

Historical D4rling i386/x86_64 tracked-object tests cover nil, no-copy controls, both release orders and multiple copies. The complete current AppKit has not been rebuilt here. The current source is byte-identical to the previously examined upstream source. The fixture prints T3_RESULT: require zero double_release, retain_after_dealloc and dangling_seen, and final_rc=0 for tracked values. The fixture exit status alone is not a verdict; its deliberate selftest must report one double release.

Sources: 086d75fb and a7ff43c2 in fr4nck/darling-cocotron. These are D4rling-authored fixtures under GPL-3.0-or-later; existing production notices remain unchanged.
Build Objective-C fixtures with manual reference counting for i386 and x86_64 against the installed frameworks. Run one scenario per isolated guest process, with bounded timeout and stdin closed.
Arguments: cell|menu tracked|string|nil 0|1|3 cf|of; use selftest to qualify the detector.
