# Copyright (C) 2026 Darling Developers
# Writes Assets-multileaf.car, a small compiled asset catalog written by hand, not by actool. Its trees are not
# single leaves, as those of the actool-compiled fixture Assets.car are: FACETKEYS has an inner root node over two
# leaves, and RENDITIONS has three levels (a root over two inner nodes, each over two leaves). The images are
# uncompressed bitmaps.
#
# Usage: make-multileaf-car.py [output path]    (default: Assets-multileaf.car next to this script)
#
# The file layout follows the BSD-licensed xcbuild libbom headers and sources (bom_format.h: the header, the block
# index, the variables, the tree and its nodes with their forward and backward links; bom.c: block_count equal to the
# index count, a free list of a count word and two empty entries; bom_tree.c: node_size 4096) and what
# AppKit/NSAssetCatalog.m reads of a rendition. The reader does not read these fields, and they are placeholders
# that claim nothing about what an Apple compiler writes: the node size (libbom's value, not the real node length),
# the count word of an inner node (written as its number of children minus one), the key index of an inner node's
# entries (0), the first two words of a facet, the version of a rendition's bitmap record, and the layout and every
# other header field of a rendition that is not listed in the catalog below (zero).
#
# The catalog (identifier in parentheses), one list per leaf of each tree, in leaf order:
#   FACETKEYS leaf 0:    Red (1), Gradient (2)
#   FACETKEYS leaf 1:    Gray (3), Blue (4), Green (5)
#   RENDITIONS leaf 0:   Red      ARGB 2 x 2, every pixel red
#   RENDITIONS leaf 1:   Gradient ARGB 4 x 2, row 0 red, green, blue, white; row 1 black, yellow, cyan, magenta
#   RENDITIONS leaf 2:   Gray     GA8 3 x 2 (template), gray 0, 128, 255 over 64, 192, and a clear pixel (gray 0,
#                                 alpha 0)
#   RENDITIONS leaf 3:   Blue     ARGB 1 x 1, blue; Green ARGB 2 x 1, green, yellow
# All other pixels are opaque. tests/appkit-asset-catalog-multileaf.m holds the same values.
import struct
import sys
import os

ATTRIBUTE_SCALE = 12
ATTRIBUTE_IDENTIFIER = 17
PIXEL_FORMAT_ARGB = 0x41524742
PIXEL_FORMAT_GA8 = 0x47413820
FLAG_TEMPLATE = 1 << 3


def be32(value):
    return struct.pack('>I', value)


def le16(value):
    return struct.pack('<H', value)


def le32(value):
    return struct.pack('<I', value)


class Blocks:
    """The numbered blocks of the store; block 0 is the null block."""

    def __init__(self):
        self.data = [b'']

    def reserve(self):
        self.data.append(None)
        return len(self.data) - 1

    def set(self, number, data):
        self.data[number] = data

    def add(self, data):
        number = self.reserve()
        self.set(number, data)
        return number


def node(is_leaf, count, forward, backward, entries):
    out = struct.pack('>HHII', 1 if is_leaf else 0, count, forward, backward)
    for value_block, key_block in entries:
        out += be32(value_block) + be32(key_block)
    return out


def leaf(*entries):
    return ('leaf', list(entries))


def inner(*children):
    return ('inner', list(children))


def add_tree(blocks, root):
    """A tree of leaf() and inner() nodes; returns the block of its header. Leaves are linked in order."""
    leaves = []

    def collect(spec):
        if spec[0] == 'leaf':
            leaves.append(spec)
        else:
            for child in spec[1]:
                collect(child)

    collect(root)
    numbers = {id(spec): blocks.reserve() for spec in leaves}

    def build(spec):
        """Fills in the node's blocks and returns its block number."""
        if spec[0] == 'leaf':
            i = next(j for j, other in enumerate(leaves) if other is spec)
            entries = [(blocks.add(value), blocks.add(key)) for key, value in spec[1]]
            forward = numbers[id(leaves[i + 1])] if i + 1 < len(leaves) else 0
            backward = numbers[id(leaves[i - 1])] if i > 0 else 0
            number = numbers[id(spec)]
            blocks.set(number, node(True, len(entries), forward, backward, entries))
            return number
        children = [(build(child), 0) for child in spec[1]]
        return blocks.add(node(False, len(children) - 1, 0, 0, children))

    top = build(root)
    paths = sum(len(spec[1]) for spec in leaves)
    return blocks.add(b'tree' + be32(1) + be32(top) + be32(4096) + be32(paths) + b'\0')


def facet(identifier):
    # Two words the reader does not read, the attribute count, and (attribute, value) pairs.
    return le16(0) + le16(0) + le16(1) + le16(ATTRIBUTE_IDENTIFIER) + le16(identifier)


def rendition_key(identifier):
    return le16(1) + le16(identifier)  # KEYFORMAT order: scale, identifier


def rendition(width, height, pixel_format, flags, pixels):
    header = bytearray(184)
    header[0:4] = b'ISTC'
    header[8:12] = le32(flags)
    header[12:16] = le32(width)
    header[16:20] = le32(height)
    header[20:24] = le32(100)  # scale 1
    header[24:28] = le32(pixel_format)
    header[36:38] = le16(0)  # a layout the reader treats as a plain bitmap
    header[168:172] = le32(0)  # no TLV entries
    data = b'MLEC' + le32(1) + le32(0) + le32(len(pixels)) + pixels  # compression 0: the pixels as they are
    return bytes(header) + data


def argb(*pixels):
    """Bytes of (r, g, b, a) pixels as premultiplied BGRA; the alpha values used here are 0 or 255."""
    return b''.join(bytes((b, g, r, a)) for r, g, b, a in pixels)


def ga8(*pixels):
    return b''.join(bytes(pixel) for pixel in pixels)


def build():
    red, green, blue = (255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255)
    white, black = (255, 255, 255, 255), (0, 0, 0, 255)
    yellow, cyan, magenta = (255, 255, 0, 255), (0, 255, 255, 255), (255, 0, 255, 255)

    blocks = Blocks()
    key_format = b'tmfk' + le32(1) + le32(2) + le32(ATTRIBUTE_SCALE) + le32(ATTRIBUTE_IDENTIFIER)
    facets = add_tree(blocks, inner(
        leaf((b'Red', facet(1)), (b'Gradient', facet(2))),
        leaf((b'Gray', facet(3)), (b'Blue', facet(4)), (b'Green', facet(5))),
    ))
    renditions = add_tree(blocks, inner(
        inner(
            leaf((rendition_key(1), rendition(2, 2, PIXEL_FORMAT_ARGB, 0, argb(red, red, red, red)))),
            leaf((rendition_key(2), rendition(4, 2, PIXEL_FORMAT_ARGB, 0,
                                              argb(red, green, blue, white, black, yellow, cyan, magenta)))),
        ),
        inner(
            leaf((rendition_key(3), rendition(3, 2, PIXEL_FORMAT_GA8, FLAG_TEMPLATE,
                                              ga8((0, 255), (128, 255), (255, 255), (64, 255), (192, 255), (0, 0))))),
            leaf((rendition_key(4), rendition(1, 1, PIXEL_FORMAT_ARGB, 0, argb(blue))),
                 (rendition_key(5), rendition(2, 1, PIXEL_FORMAT_ARGB, 0, argb(green, yellow)))),
        ),
    ))
    key_format_block = blocks.add(key_format)
    variables = [(b'FACETKEYS', facets), (b'KEYFORMAT', key_format_block), (b'RENDITIONS', renditions)]

    body = bytearray()
    entries = [(0, 0)]
    for data in blocks.data[1:]:
        entries.append((32 + len(body), len(data)))
        body += data
        body += b'\0' * (-len(body) % 4)
    index = be32(len(entries)) + b''.join(be32(address) + be32(length) for address, length in entries)
    index += be32(0) + bytes(16)  # an empty free list: its count word and two empty entries
    var_data = be32(len(variables))
    for name, block in variables:
        var_data += be32(block) + bytes((len(name),)) + name

    index_offset = 32 + len(body)
    variables_offset = index_offset + len(index)
    header = b'BOMStore' + be32(1) + be32(len(entries)) + be32(index_offset) + be32(len(index)) + \
        be32(variables_offset) + be32(len(var_data))
    return header + bytes(body) + index + var_data


if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'Assets-multileaf.car')
    with open(path, 'wb') as f:
        f.write(build())
