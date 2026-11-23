Build `appkit-colorwell-color-well-style.m` against the matching AppKit headers and framework;
run it inside a Darling prefix with a display (`PASS` and exit 0 on success). It calls
`[NSApplication sharedApplication]`, because creating a color well reaches the shared color
panel.

The documentation lists `colorWellStyle` (macOS 13) as a settable property of `NSColorWell`
whose type is an enumeration, `NSColorWell.Style` (`NSColorWellStyle`), of three styles named
`default`, `minimal` and `expanded`. It gives neither a starting value for the property nor
numbers for the styles. The test checks, on a
plain well and on an application subclass whose setter wraps the superclass one (the failing
receiver in a real application was a subclass): the default, set/get round trips of every case,
the value and the well's color and border not overwriting one another, two wells not sharing it,
the three cases being distinct, and `respondsToSelector:` for both accessors.

The public header numbers the cases 0, 1 and 2, and the test checks that. Observed on macOS 26.7.3
(probe `p770.m` of batch 12a): the default is the style called default; any value is stored; the value
is not reset by the well's other properties; an archive carries it under the key `NSColorWellStyle`
(only when it is not the default), which the test decodes. On master the enumeration and its constants do not exist, so the test
does not compile against master's header. The value is only stored: how the well looks or reacts
for a style is not implemented or tested.
