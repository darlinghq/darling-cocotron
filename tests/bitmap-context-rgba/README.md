Guest test: a bitmap context made with `kCGImageAlphaPremultipliedLast` and the default
byte order must store the bytes of each pixel as R, G, B, A. Apps rely on it to build RGBA
textures. The test fills one pixel with (255, 128, 64, 255) and reads the bytes back.

Build it with the Darling tree's AppKit compile flags, linking Foundation and CoreGraphics, and
run it in a guest with a private runtime and prefix:

```sh
python3 build-probe.py tests/bitmap-context-rgba/client.m "$OUT/client"
DPREFIX="$PREFIX" DARLING_INSTALL_PREFIX="$RUNTIME/image/usr/local" "$RUNTIME/darling" shell "/Volumes/SystemRoot$OUT/client"
```

(`build-probe.py` is any helper that compiles one Objective-C file with that tree's flags.)

Before: `fill bytes 255 64 128 255`, exit 1 (the context wrote A, B, G, R and the green and blue
channels came out swapped). After: `fill bytes 255 128 64 255`, exit 0.
