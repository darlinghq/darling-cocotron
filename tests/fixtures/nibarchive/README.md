Copyright (C) 2026 Lubos Dolezel

# Compiled nib fixtures

Compiled on macOS 26.7.3 (x86_64) with Xcode 26.5 (ibtool bundle version 24765, short version 26.5)
from the hand-written sources in `src/` (no Apple application, template or sample was used).

| Path | Command | Contents |
|---|---|---|
| `flat/Menu.nib`, `flat/Custom.nib`, `flat/Tint.nib`, `flat/Swap.nib`, `flat/Scroll.nib`, `flat/Toolbar.nib` | `ibtool --minimum-deployment-target 10.13 --compile flat/<Name>.nib src/<Name>.xib` | a single NIBArchive file |
| `dirs/Table.nib` | the same command for `src/Table.xib`: with a scroll view and table view ibtool writes a directory | `keyedobjects-101300.nib` and `keyedobjects-110000.nib`, both NIBArchive; the number is the minimum macOS version (10.13.0, 11.0.0) the file is for. They differ in the table view style and column widths |
| `flat/StackGravity.nib` | `ibtool --minimum-deployment-target 10.13 --compile flat/StackGravity.nib src/StackGravity.xib` | a horizontal stack view of gravity areas (buttons A and B leading, C center, D trailing), custom space after A, visibility priorities 1000/600/1000/0 |
| `flat/CellViews.nib` | `ibtool --minimum-deployment-target 10.13 --compile CellViews.nib src/CellViews.xib` (a directory, as for `Table.xib`); the file is its `keyedobjects-101300.nib` | a single NIBArchive file |
| `compat/<Name>.nib/` | `ibtool --minimum-deployment-target 10.10 --compile compat/<Name>.nib src/<Name>.xib` | a directory with `keyedobjects.nib` (an NSKeyedArchiver binary property list, the format before 10.13) next to the NIBArchive file(s) above |

Sources: `Table.xib` (window, scroll view, table view with two columns and a header view; File's Owner `TableOwner` with outlets `window` and `table`), `Menu.xib` (a menu with File and Edit submenus: key equivalents, a separator, a checked item with tag and indentation, actions to the owner and to the first responder; owner `MenuOwner`), `Custom.xib` (a custom object `CustomHelper` with an outlet to the owner, a custom view of class `CustomPanelView` with a button whose action targets the helper; owner `CustomOwner`), `Tint.xib` (a slider whose cell has the custom class `TintReadingSliderCell`; owner `TintOwner` with outlet `slider`), `Swap.xib` (an image view with the custom class `PlainArtView`, which the test makes an NSView subclass, and a scroll view with the custom class `MissingListView`, which does not exist; owner `SwapOwner` with outlets `art` and `list`), `Scroll.xib` (two scroll views, one with usesPredominantAxisScrolling off; owner `ScrollOwner` with outlets `freeAxes` and `predominantAxis`), `Toolbar.xib` (a window with a toolbar of the custom class `LoggingToolbar`, items `ItemA` (in the default set) and `ItemB`, and a `delegate` outlet to a custom object `ToolbarDelegate`; owner `ToolbarOwner` with outlet `window`), `Splits.xib` (a view with three vertical split views of two subviews each, with the default, thin and pane splitter divider styles), `CellViews.xib` (a view-based table whose column has a prototype NSTableCellView "nameCell" with a text field bound to its objectValue; owner `CellViewsOwner` with outlets `window` and `table`, the table's data source and delegate).

`../Fixture.nib` and `../Fixture.xib` (older, compiled with Xcode 27.2) are used by `appkit-nibarchive-ibtool-fixture.m`.

Tests: `appkit-nibarchive-compiled.m <this directory>` (checks objects, connections, awakeFromNib; it also passes on macOS 26.7.3), `appkit-nibarchive-custom-classes.m <this directory>` (Tint, Swap and Scroll; it also passes on macOS 26.7.3), `appkit-toolbar-default-items.m <this directory>` (Toolbar; it also passes on macOS 26.7.3 and 10.14.4), `appkit-table-archived-cell-views.m <this directory>` (CellViews; it also passes on macOS 26.7.3) and `appkit-nibarchive-ibtool-fixture.m ../Fixture.nib`.
