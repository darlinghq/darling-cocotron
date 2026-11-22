// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.
//
// A KWin script: reports every window KWin lists (layer surfaces and pop-ups
// included) as one D-Bus call per window to org.darlinghq.test, which
// run-kwin.py watches with dbus-monitor.
function out(text) {
    callDBus("org.darlinghq.test", "/", "org.darlinghq.test", "line", String(text));
}
var windows = workspace.windowList();
for (var i = 0; i < windows.length; i++) {
    var w = windows[i], g = w.frameGeometry;
    out("WIN id=" + w.internalId + " pid=" + w.pid + " x=" + Math.round(g.x) + " y=" + Math.round(g.y) +
        " w=" + Math.round(g.width) + " h=" + Math.round(g.height) + " popup=" + (w.popupWindow ? 1 : 0) +
        " skipTaskbar=" + (w.skipTaskbar ? 1 : 0));
}
out("END");
