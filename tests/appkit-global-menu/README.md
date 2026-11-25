/home/lubos/vd/darling-d/.git/modules/src/external/cocotron c14755ac [cristim-batch14b]
/home/lubos/darling-wt/cocotron-metal-drawable-usage        22ad208b [metal-drawable-usage]
/home/lubos/darling-wt/focus-steal-defer                    b015616b [focus-steal-defer]
# Global application menu tests

These test how AppKit shows the application's main menu outside its windows:
in the desktop's global menu (exported over D-Bus with the `com.canonical.dbusmenu`
protocol and announced to the `com.canonical.AppMenu.Registrar`), or, when the
desktop has none, in a strip inside each window that can carry it, with a menu bar
window of the application's own along the top of the screen while no visible
window carries a strip. They also cover the `DarlingMenuBarStyle` preference
(`auto`, the default, `window` and `screen`) and the older `DarlingInWindowMenuBar`.

The guest program is `../appkit-global-menu.m`; the host scripts start it and
inspect it from outside. Everything runs against Xvfb `:99` with a window manager
(xfwm4), except `run-kwin.py`, which starts a KWin of its own. Build the guest programs with the guest cross-compiler (host clang, ld64
and the SDK of the source tree), then run the scripts on the host:

    guest-cc.sh -o /tmp/agm ../appkit-global-menu.m -framework Foundation -framework AppKit
    guest-cc.sh -o /tmp/amc ../appkit-menu-change-notifications.m -framework Foundation -framework AppKit
    guest-cc.sh -o /tmp/appkit-menu-sticky-click ../appkit-menu-sticky-click.m -framework Foundation -framework AppKit
    ./run-exporter.py /tmp/agm
    ./run-bar.py /tmp/agm
    ./run-bar-hiding.py /tmp/agm
    ./run-strip.py /tmp/agm
    ./run-sticky.py /tmp/appkit-menu-sticky-click
    ./run-bar-tracking.py kwin /tmp/agm
    ./run-bar-tracking.py sway /tmp/agm
    ./run-bar-tracking.py x11 /tmp/agm :99
    ./run-kwin.py /tmp/agm
    ./run-kwin-menu-style.py /tmp/agm
    ./run-menu-style-x11.py /tmp/agm :99
    ./run-kwin.py --registrar kded /tmp/agm
    darling shell env DISPLAY=:99 /Volumes/SystemRoot/tmp/amc </dev/null

The private KWin is always started with `--no-lockscreen`. A KWin session has its own lock screen, which authenticates against the host's real PAM configuration. Keys a test sends into a locked test session therefore count as failed logins of the user running the tests, and can lock that user out of the desktop.


| Script | What it checks |
| --- | --- |
| `run-exporter.py` | A private session bus (`dbus-daemon`) and `fake-registrar.c`, a registrar written against libdbus. The program has a panel as its only window. Checks RegisterWindow, the X properties KDE reads, `GetLayout`, `GetGroupProperties`, `GetProperty`, the properties of items (labels, shortcuts, enabled, hidden, check marks, separators, submenus), `AboutToShow` (runs `menuNeedsUpdate:` and validation), `opened`/`closed` events, `clicked` (performs the action on the main thread; a disabled item does not), and `LayoutUpdated` after the application changes its menu. |
| `run-bar.py` | No registrar: a dock window at the top, full width, with a strut, is shown while the application is active and hidden while another client has the focus; with `xdotool` it opens a menu and chooses an item. Then without any session bus. |
| `run-bar-hiding.py` | `../appkit-global-menu.m` in its `hiding` mode: the application's own menu bar is shown, and hidden while the key window has the full screen style and while the presentation options hide the menu bar (`NSApplicationPresentationHideMenuBar`, `NSApplicationPresentationAutoHideMenuBar`), and shown again afterwards. |
| `run-strip.py` | The `DarlingMenuBarStyle` and `DarlingInWindowMenuBar` preferences. |
| `run-kwin-menu-style.py` | Under a private virtual KWin (Wayland): by default a titled window has the strip and there is no menu bar surface; with no window, or only a borderless one, the surface is there; it goes away when a window that can carry the strip appears and comes back when it closes; with a global menu (`fake-registrar.c`) the menu is exported and there is neither strip nor surface; the preference values; and another application (a native Wayland client, kcalc) taking the focus: the application resigns and its surface goes away, and the focus coming back brings it back. |
| `run-sway-menu-style.py` | The same default and focus cases under a headless sway (layer shell, no appmenu protocol), and the menu bar owner cases (below). |
| `run-menu-style-x11.py` | The same cases on X11, against an Xvfb with xfwm4 (`run-menu-style-x11.py PROGRAM [DISPLAY]`), with xmessage as the other application. |
| `run-kwin.py` | Under a private virtual KWin (`kwin_wayland --virtual --no-lockscreen --xwayland`) with its own session bus, on Wayland and on X11 (KWin's Xwayland): with a global menu (`fake-registrar.c`, or with `--registrar kded` Plasma's own appmenu service in `kded6`, switched on by owning `org.kde.kappmenuview` as the Global Menu applet does) the window has no strip, the menu is exported, and KWin reports the menu's address for the window (read with `appmenu-watcher.py` through `org_kde_plasma_window_management`, as the applet reads it); without one the window draws the strip on Wayland, and the application's menu bar is at the top of the screen on X11. Needs `kwin_wayland`, `Xwayland`, and for `--registrar kded` `kded6` and python3-dbus. |
| `run-kwin-bar.py` | Under a private virtual KWin (layer shell, no Xwayland) with its own session bus and a libei pointer (`kwin-pointer.c`; KWin's windows are listed by `kwin-windows.js`): with no global menu the menu bar is one layer surface along the top that stays mapped (a borderless window, a titled window and no window at all), a click on a title opens its menu right under the bar and a click on an item runs its action; with a global menu present from the start there is no bar, and it goes away and comes back as the registrar appears and disappears. Run it as `timeout -s KILL 560 ./run-kwin-bar.py /tmp/agm`. |
| `run-bar-tracking.py` | Tracking of the menus of the application's own menu bar, with a pointer and keyboard driven from outside, under a private virtual KWin (libei, `kwin-pointer.c`), a headless sway (virtual pointer and keyboard protocols, `wl-input.c`, whose protocol glue `wl-input.xml` is turned into C by `wayland-scanner`) or an Xvfb with xfwm4 (xdotool): `run-bar-tracking.py kwin\|sway\|x11 GUEST_PROGRAM [DISPLAY]`. For an application that has the keyboard focus (a borderless window) and for the menu bar owner that has not (an `owner` program and an `LSUIElement` helper whose window has it): the pointer moves in small steps from the File title straight down into its menu, which stays open with its first item highlighted; the pointer over the empty part of the bar keeps the open menu; a menu is opened by a click, closed by a click on its title and opened again, and Down and Return run the first item's action (each time); Escape closes the submenu and, with the keyboard focus, a second Escape ends the tracking. Two more cases need no pointer: `parent` (a regular application with a bar starts, 0 and 300 ms after its bar was ordered in, a windowless process outside any bundle that activates itself over and over; the process is prohibited like on macOS and neither becomes the front application nor the menu bar owner, and the application neither resigns nor loses its bar) and `startup` (the window the application showed at startup is closed `DELAYMS` after the bar was ordered in: the application stays active, keeps the menu bar and its bar). Two cases cover the recognition of an application bundle by its contents: `policy` (NSRunningApplication's activation policy and bundle URL, and NSApplication's policy, for a bundle with and without a `.app` extension, with no package type, with `LSUIElement`, with another package type, without Info.plist, and for a bare executable) and `noext` (an application in `Outer.AppBundle/Probe` that never sets a policy owns the menu bar and shows it). `--cases` selects cases. Under sway the keyboard checks of the owner case are left out: sway gives a popup of a layer surface that takes no keyboard no keyboard focus while another client has it. |
| `run-sticky.py` | `../appkit-menu-sticky-click.m` in four modes (the menu bar, the in-window strip, a pop-up button and a context menu): a menu opened by a click that is released at once stays open; a second click on an item chooses it; a click outside closes it without choosing; Escape closes it and Return chooses the item under the pointer; the application never resigns while its menu is open. |

The menu bar owner cases (`owner` as the last argument runs only these; `focus` runs only the
focus cases) of `run-kwin-menu-style.py`, `run-sway-menu-style.py` and `run-menu-style-x11.py`
use the program's `owner` and `helper` modes: a regular application with a main menu and an
offscreen 1x1 window starts a helper (the copy of the program in an `LSUIElement` bundle, and a
second helper that switches itself to the accessory policy at run time) whose window gets the
focus. The application stays `NSWorkspace.menuBarOwningApplication` and keeps its bar although it
resigned (the helper does not take the menu bar over); a native client taking the focus from the
helper takes the bar away, the focus returning to the helper brings it back, and when the helper
quits the application is active again.

`fake-registrar.c` can be built on its own:

    cc -o fake-registrar fake-registrar.c $(pkg-config --cflags --libs dbus-1)

Needs on the host: `dbus-daemon`, `gdbus`, `xprop`, `xwininfo`, `xdotool`,
`xmessage`, a C compiler and the libdbus-1 headers.
