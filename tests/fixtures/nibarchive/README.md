Copyright (C) 2026 Lubos Dolezel

# Compiled nib fixtures

Compiled on macOS 26.7.3 (x86_64) with Xcode 26.5 (ibtool bundle version 24765, short version 26.5)
from the hand-written sources in `src/` (no Apple application, template or sample was used).

| Path | Command | Contents |
|---|---|---|
| `flat/Menu.nib`, `flat/Custom.nib` | `ibtool --minimum-deployment-target 10.13 --compile flat/<Name>.nib src/<Name>.xib` | a single NIBArchive file |
| `dirs/Table.nib` | the same command for `src/Table.xib`: with a scroll view and table view ibtool writes a directory | `keyedobjects-101300.nib` and `keyedobjects-110000.nib`, both NIBArchive; the number is the minimum macOS version (10.13.0, 11.0.0) the file is for. They differ in the table view style and column widths |
| `compat/<Name>.nib/` | `ibtool --minimum-deployment-target 10.10 --compile compat/<Name>.nib src/<Name>.xib` | a directory with `keyedobjects.nib` (an NSKeyedArchiver binary property list, the format before 10.13) next to the NIBArchive file(s) above |

Sources: `Table.xib` (window, scroll view, table view with two columns and a header view; File's Owner `TableOwner` with outlets `window` and `table`), `Menu.xib` (a menu with File and Edit submenus: key equivalents, a separator, a checked item with tag and indentation, actions to the owner and to the first responder; owner `MenuOwner`), `Custom.xib` (a custom object `CustomHelper` with an outlet to the owner, a custom view of class `CustomPanelView` with a button whose action targets the helper; owner `CustomOwner`).

`../Fixture.nib` and `../Fixture.xib` (older, compiled with Xcode 27.2) are used by `appkit-nibarchive-ibtool-fixture.m`.

Tests: `appkit-nibarchive-compiled.m <this directory>` (checks objects, connections, awakeFromNib; it also passes on macOS 26.7.3) and `appkit-nibarchive-ibtool-fixture.m ../Fixture.nib`.
