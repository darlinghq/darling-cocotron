#!/usr/bin/env python3
"""Write DefaultNibViewController.nib, the class-named nib for viewcontroller-default-nib.m.
usage: viewcontroller-default-nib.py OUTPUT_DIR"""
import os
import sys

from nibfixture import write_nib


def build(a, owner):
    view = a.view(320, 200)
    return [view], [a.outlet(owner, view, "view")]


write_nib(os.path.join(sys.argv[1], "DefaultNibViewController.nib"), build)
