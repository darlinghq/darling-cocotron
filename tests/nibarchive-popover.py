#!/usr/bin/env python3
"""Write NIBArchivePopover.nib, a binary NIBArchive nib with a top-level NSPopover, for nibarchive-popover.m.
usage: nibarchive-popover.py OUTPUT_DIR

Authored from the layout documented in AppKit/nib.subproj/NSNibArchive.m; it embeds no bytes from any
compiled nib. The NSPopover keys and value types are the ones NSPopover -initWithCoder: reads."""
import os
import struct
import sys

EMPTY = "UINibEncoderEmptyKey"
INT8, TRUE, FALSE, DOUBLE, DATA, OBJECT = 0, 4, 5, 7, 8, 10


def varint(n):
    out = bytearray()
    while n >= 0x80:
        out.append(n & 0x7F)
        n >>= 7
    out.append(n | 0x80)  # the high bit marks the last byte
    return bytes(out)


class Nib:
    def __init__(self):
        self.classes, self.keys, self.objects, self.values = [], [], [], []

    def _index(self, table, item):
        if item not in table:
            table.append(item)
        return table.index(item)

    def add(self, cls, members):
        """members: (key, type, payload) tuples; returns the object index. Objects are numbered in
        creation order, so a member may only reference an index that already exists or is known."""
        first = len(self.values)
        for key, kind, payload in members:
            self.values.append(varint(self._index(self.keys, key)) + bytes([kind]) + payload)
        self.objects.append((self._index(self.classes, cls), first, len(members)))
        return len(self.objects) - 1

    def write(self, path):
        objects = b"".join(varint(c) + varint(f) + varint(n) for c, f, n in self.objects)
        keys = b"".join(varint(len(k.encode())) + k.encode() for k in self.keys)
        values = b"".join(self.values)
        classes = b"".join(varint(len(c) + 1) + varint(0) + c.encode() + b"\0" for c in self.classes)
        base = 10 + 40
        offsets = [base, base + len(objects)]
        offsets.append(offsets[1] + len(keys))
        offsets.append(offsets[2] + len(values))
        header = struct.pack("<10I", 1, 9, len(self.objects), offsets[0], len(self.keys), offsets[1],
                             len(self.values), offsets[2], len(self.classes), offsets[3])
        with open(path, "wb") as f:
            f.write(b"NIBArchive" + header + objects + keys + values + classes)


def ref(index):
    return OBJECT, struct.pack("<I", index)


def string(nib, text):
    return nib.add("NSString", [("NS.bytes", DATA, varint(len(text.encode())) + text.encode())])


def array(nib, items):
    return nib.add("NSArray", [(EMPTY, *ref(i)) for i in items])


# Object indexes are fixed up front because the root and NSIBObjectData reference later objects.
ROOT, DATA_OBJ, OWNER, OWNER_CLASS, TOP_KEYS, TOP_VALUES, NAMES_KEYS, NAMES_VALUES, NAME, CONNECTIONS, WINDOWS, POPOVER = range(12)

nib = Nib()
nib.add("NSObject", [("IB.objectdata", *ref(DATA_OBJ))])
nib.add("NSIBObjectData", [("NSRoot", *ref(OWNER)), ("NSObjectsKeys", *ref(TOP_KEYS)),
                           ("NSObjectsValues", *ref(TOP_VALUES)), ("NSNamesKeys", *ref(NAMES_KEYS)),
                           ("NSNamesValues", *ref(NAMES_VALUES)), ("NSConnections", *ref(CONNECTIONS)),
                           ("NSVisibleWindows", *ref(WINDOWS))])
nib.add("NSCustomObject", [("NSClassName", *ref(OWNER_CLASS))])
string(nib, "NSObject")
array(nib, [POPOVER])
array(nib, [OWNER])
array(nib, [OWNER])
array(nib, [NAME])
string(nib, "File's Owner")
array(nib, [])
nib.add("NSSet", [])
nib.add("NSPopover", [("NSBehavior", INT8, struct.pack("<b", 2)), ("NSAnimates", FALSE, b""),
                      ("NSContentWidth", DOUBLE, struct.pack("<d", 0.0)),
                      ("NSContentHeight", DOUBLE, struct.pack("<d", 0.0)),
                      ("NSHasFullSizeContent", TRUE, b"")])

nib.write(os.path.join(sys.argv[1], "NIBArchivePopover.nib"))
