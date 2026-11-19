# AppKit: copy NSTextFieldCell placeholder and locale ownership

NSTextFieldCell copies raw extra-ivar pointers for placeholder and allowedInputSourceLocales. Both instances later release the same ownership. Copy both properties when making the cell copy.

Reuse the historical 24-case D4rling ownership qualification, including both release orders and real values. The supplied tracked-value fixture checks live survivor values, exactly-once destruction and absence of zombie operations. No current full upstream AppKit runtime qualification is claimed.

Sources: 7721976389ad8481b8cf64a44283b231e0092b8d in fr4nck/darling-cocotron. These are D4rling-authored fixtures under GPL-3.0-or-later; existing production notices remain unchanged.
Build Objective-C fixtures with manual reference counting for i386 and x86_64 against the installed frameworks. Run one scenario per isolated guest process, with bounded timeout and stdin closed.
Arguments: placeholder|locales|real orig-first|copy-first; nonzero exit means failure.
