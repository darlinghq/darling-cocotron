"""Write test nibs: keyed archives of an NSIBObjectData, the form Cocotron's NSNib reads."""
import plistlib

RESPONDER = ["NSResponder", "NSObject"]


class Archive:
    def __init__(self):
        self.objects = ["$null"]
        self.classes = {}

    def add(self, value):
        self.objects.append(value)
        return plistlib.UID(len(self.objects) - 1)

    def cls(self, name, supers):
        if name not in self.classes:
            self.classes[name] = self.add({"$classname": name, "$classes": [name] + supers})
        return self.classes[name]

    def obj(self, name, supers, **fields):
        uid = self.add(None)
        self.objects[uid.data] = dict(fields, **{"$class": self.cls(name, supers)})
        return uid

    def array(self, items):
        return self.obj("NSArray", ["NSObject"], **{"NS.objects": list(items)})

    def view(self, width, height):
        return self.obj("NSView", RESPONDER, NSFrame=self.add("{{0, 0}, {%d, %d}}" % (width, height)))

    def outlet(self, source, destination, label):
        return self.obj("NSNibOutletConnector", ["NSNibConnector", "NSObject"],
                        NSSource=source, NSDestination=destination, NSLabel=self.add(label))


def write_nib(path, build):
    """build(archive, owner) returns (top-level objects, connections); owner is the File's Owner."""
    a = Archive()
    owner = a.obj("NSCustomObject", ["NSObject"], NSClassName=a.add("NSObject"))
    top, connections = build(a, owner)
    data = a.obj("NSIBObjectData", ["NSObject"],
                 NSRoot=owner,
                 NSObjectsKeys=a.array(top), NSObjectsValues=a.array([owner] * len(top)),
                 NSNamesKeys=a.array([owner]), NSNamesValues=a.array([a.add("File's Owner")]),
                 NSConnections=a.array(connections),
                 NSVisibleWindows=a.obj("NSSet", ["NSObject"], **{"NS.objects": []}))
    with open(path, "wb") as f:
        plistlib.dump({"$archiver": "NSKeyedArchiver", "$version": 100000,
                       "$top": {"IB.objectdata": data}, "$objects": a.objects},
                      f, fmt=plistlib.FMT_BINARY)
