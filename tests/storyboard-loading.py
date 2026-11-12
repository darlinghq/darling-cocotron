#!/usr/bin/env python3
"""Write Fixture.storyboardc, a compiled storyboard for storyboard-loading.m, into the given directory.

A compiled storyboard is a directory with one nib per scene and an Info.plist naming the initial scene
and mapping scene identifiers to nib names.
usage: storyboard-loading.py OUTPUT_DIR"""
import os
import plistlib
import sys

from nibfixture import RESPONDER, write_nib


def window_scene(a, owner):
    return [a.obj("NSWindowController", RESPONDER)], []


def detail_scene(a, owner):
    controller = a.obj("FixtureViewController", ["NSViewController"] + RESPONDER,
                       NSNibName=a.add("Detail-view"), NSTitle=a.add("Detail"))
    return [controller], []


def detail_view(a, owner):
    view = a.view(240, 120)
    return [view], [a.outlet(owner, view, "view")]


def placeholder_scene(a, owner):
    controller = a.obj("FixtureViewController", ["NSViewController"] + RESPONDER, NSTitle=a.add("Placeholder"))
    placeholder = a.obj("NSNibExternalObjectPlaceholder", ["NSObject"],
                        NSExternalObjectPlaceholderIdentifier=a.add("FixtureSceneObject"))
    return [controller, placeholder], [a.outlet(controller, placeholder, "representedObject")]


def two_controllers(a, owner):
    return [a.obj("NSViewController", RESPONDER), a.obj("NSViewController", RESPONDER)], []


out = os.path.join(sys.argv[1], "Fixture.storyboardc")
os.makedirs(out, exist_ok=True)
write_nib(os.path.join(out, "Window.nib"), window_scene)
write_nib(os.path.join(out, "DetailController.nib"), detail_scene)
write_nib(os.path.join(out, "Detail-view.nib"), detail_view)
write_nib(os.path.join(out, "Ambiguous.nib"), two_controllers)
write_nib(os.path.join(out, "PlaceholderController.nib"), placeholder_scene)
with open(os.path.join(out, "Info.plist"), "wb") as f:
    plistlib.dump({"NSStoryboardDesignatedEntryPointIdentifier": "Window",
                   "NSStoryboardVersion": 1,
                   "NSViewControllerIdentifiersToNibNames": {
                       "Window": "Window", "Detail": "DetailController",
                       "Ambiguous": "Ambiguous", "Unbuilt": "Unbuilt",
                       "Placeholder": "PlaceholderController"}}, f)
