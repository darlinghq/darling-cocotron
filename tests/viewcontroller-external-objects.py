#!/usr/bin/env python3
"""Write ViewObjectsController.archive and ViewObjects-view.nib for viewcontroller-external-objects.m into the given directory.

The archive is a view controller the way a storyboard scene's controller nib archives it, with
NSExternalObjectsTableForViewLoading: UpstreamPlaceholder-1 is the controller itself and UpstreamPlaceholder-2 is another
object. The view nib reaches both through NSNibExternalObjectPlaceholder.
usage: viewcontroller-external-objects.py OUTPUT_DIR"""
import os
import plistlib
import sys

from nibfixture import Archive, RESPONDER, write_nib


def controller_archive(path):
    a = Archive()
    controller = a.add(None)
    shared = a.array([a.add("shared object")])
    table = a.obj("NSMutableDictionary", ["NSDictionary", "NSObject"],
                  **{"NS.keys": [a.add("UpstreamPlaceholder-1"), a.add("UpstreamPlaceholder-2")],
                     "NS.objects": [controller, shared]})
    a.objects[controller.data] = {
        "$class": a.cls("ViewObjectsController", ["NSViewController"] + RESPONDER),
        "NSNibName": a.add("ViewObjects-view"),
        "NSExternalObjectsTableForViewLoading": table}
    with open(path, "wb") as f:
        plistlib.dump({"$archiver": "NSKeyedArchiver", "$version": 100000,
                       "$top": {"root": controller}, "$objects": a.objects}, f, fmt=plistlib.FMT_BINARY)


def view(a, owner):
    first = a.obj("NSNibExternalObjectPlaceholder", ["NSObject"],
                  NSExternalObjectPlaceholderIdentifier=a.add("UpstreamPlaceholder-1"))
    second = a.obj("NSNibExternalObjectPlaceholder", ["NSObject"],
                   NSExternalObjectPlaceholderIdentifier=a.add("UpstreamPlaceholder-2"))
    content = a.view(240, 120)
    return [content, first, second], [a.outlet(first, content, "view"),
                                      a.outlet(first, second, "representedObject")]


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
controller_archive(os.path.join(out, "ViewObjectsController.archive"))
write_nib(os.path.join(out, "ViewObjects-view.nib"), view)
