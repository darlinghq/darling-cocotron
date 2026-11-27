#!/usr/bin/env python3
# Host contract test for CoreGraphics display streams.
#
# Public contract sources:
#   https://developer.apple.com/documentation/coregraphics/1454448-cgdisplaystreamcreatewithdispatchqueue
#   https://developer.apple.com/documentation/coregraphics/cgdisplaystream
#
# AVFoundation and ScreenCaptureKit build on this lower layer, so rate limiting
# and queue-depth behavior belongs here rather than in either higher framework.

import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "CoreGraphics/CGDisplayStream.m")
HEADER = os.path.join(ROOT, "CoreGraphics/include/CoreGraphics/CGDisplayStream.h")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def need(name, pattern, text):
    if not re.search(pattern, text, re.MULTILINE):
        print(f"FAIL: {name}")
        raise SystemExit(1)


source = read(SOURCE)
header = read(HEADER)

# The public entry point must accept a property dictionary and handler queue.
need("public create", r"CGDisplayStreamCreateWithDispatchQueue\s*\(", header)
need("implemented create", r"CGDisplayStreamCreateWithDispatchQueue\s*\(", source)

# kCGDisplayStreamMinimumFrameTime is a CFNumber of seconds. The implementation
# converts it to a nanosecond interval and uses a monotonic clock, so wall-clock
# adjustments cannot produce bursts or permanently stall frames.
need("minimum frame time key", r"kCGDisplayStreamMinimumFrameTime", source)
need("seconds conversion", r"1000000000\.0", source)
need("monotonic clock", r"CLOCK_MONOTONIC", source)
need("hold-off", r"now - _lastFrameTimeNs < minimumNs", source)

# A bounded queue drops frames when full and reports the accumulated drops in
# the next CGDisplayStreamUpdate, matching the public update contract.
need("queue depth key", r"kCGDisplayStreamQueueDepth", source)
need("queue bound", r"queued >= _queueDepth", source)
need("drop accounting", r"dropCount:\s*_pendingDrops", source)
need("drop reset", r"_pendingDrops\s*=\s*0", source)

print("PASS: CoreGraphics display stream contract")
