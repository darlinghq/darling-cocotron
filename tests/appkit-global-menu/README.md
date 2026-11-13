# Global application menu tests

These test how AppKit shows the application's main menu outside its windows:
in the desktop's global menu (exported over D-Bus with the `com.canonical.dbusmenu`
protocol and announced to the `com.canonical.AppMenu.Registrar`), or, when the
desktop has none, in a menu bar window of the application's own along the top of
the screen. They also cover the preference that brings the old strip inside each
titled window back.

The guest program is `../appkit-global-menu.m`; the host scripts start it and
inspect it from outside. Everything runs against Xvfb `:99` with a window manager
(xfwm4). Build the guest programs with the guest cross-compiler (host clang, ld64
and the SDK of the source tree), then run the scripts on the host:

    guest-cc.sh -o /tmp/agm ../appkit-global-menu.m -framework Foundation -framework AppKit
    guest-cc.sh -o /tmp/amc ../appkit-menu-change-notifications.m -framework Foundation -framework AppKit
    guest-cc.sh -o /tmp/appkit-menu-sticky-click ../appkit-menu-sticky-click.m -framework Foundation -framework AppKit
    ./run-exporter.py /tmp/agm
    ./run-bar.py /tmp/agm
    ./run-strip.py /tmp/agm
    ./run-sticky.py /tmp/appkit-menu-sticky-click
    darling shell env DISPLAY=:99 /Volumes/SystemRoot/tmp/amc </dev/null

| Script | What it checks |
| --- | --- |
| `run-exporter.py` | A private session bus (`dbus-daemon`) and `fake-registrar.c`, a registrar written against libdbus. The program has a panel as its only window. Checks RegisterWindow, the X properties KDE reads, `GetLayout`, `GetGroupProperties`, `GetProperty`, the properties of items (labels, shortcuts, enabled, hidden, check marks, separators, submenus), `AboutToShow` (runs `menuNeedsUpdate:` and validation), `opened`/`closed` events, `clicked` (performs the action on the main thread; a disabled item does not), and `LayoutUpdated` after the application changes its menu. |
| `run-bar.py` | No registrar: a dock window at the top, full width, with a strut, is shown while the application is active and hidden while another client has the focus; with `xdotool` it opens a menu and chooses an item. Then without any session bus. |
| `run-strip.py` | The `DarlingInWindowMenuBar` preference. |
| `run-sticky.py` | `../appkit-menu-sticky-click.m` in four modes (the menu bar, the in-window strip, a pop-up button and a context menu): a menu opened by a click that is released at once stays open; a second click on an item chooses it; a click outside closes it without choosing; Escape closes it and Return chooses the item under the pointer; the application never resigns while its menu is open. |

`fake-registrar.c` can be built on its own:

    cc -o fake-registrar fake-registrar.c $(pkg-config --cflags --libs dbus-1)

Needs on the host: `dbus-daemon`, `gdbus`, `xprop`, `xwininfo`, `xdotool`,
`xmessage`, a C compiler and the libdbus-1 headers.
