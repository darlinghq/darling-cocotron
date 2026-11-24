// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.
//
// A KWin script: makes the window whose internal id is @TARGET@ the active
// one, as a user switching to it would. run-kwin-menu-style.py replaces the word.
var windows = workspace.windowList();
for (var i = 0; i < windows.length; i++) {
    if (String(windows[i].internalId) == "@TARGET@") {
        workspace.activeWindow = windows[i];
        break;
    }
}
