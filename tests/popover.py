#!/usr/bin/env python3
"""Write Popover.nib, a nib with a top-level NSPopover, for popover.m.
usage: popover.py OUTPUT_DIR"""
import os
import sys

from nibfixture import RESPONDER, write_nib


def build(a, owner):
    content = a.obj("NSViewController", RESPONDER, NSTitle=a.add("Content"))
    popover = a.obj("NSPopover", RESPONDER, NSBehavior=1, NSAnimates=False,
                    NSContentWidth=200.0, NSContentHeight=100.0, NSContentViewController=content)
    return [popover], []


write_nib(os.path.join(sys.argv[1], "Popover.nib"), build)
