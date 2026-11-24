/* AppKit's Pocket backend: a window on the phone host.

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import "PocketWindow.h"
#import "PocketDisplay.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSWindow.h>
#import <Onyx2D/O2Context_builtin_FT.h>
#import <Onyx2D/O2Surface.h>
#include <elfcalls.h>
#include <errno.h>
#include <sys/mman.h>
#include <unistd.h>
#include <math.h>
#include <string.h>

extern struct elf_calls *_elfcalls;

// NSView replaces the user CTM whenever it locks focus, so the scale goes in
// the device transform, with Onyx2D's bottom-left to top-left flip.
@interface PocketDrawingContext : O2Context_builtin_FT
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize;
@end

@implementation PocketDrawingContext
- (id) initWithSurface: (O2Surface *) surface logicalSize: (NSSize) logicalSize {
    if ((self = [super initWithSurface: surface flipped: NO]) != nil) {
        CGFloat sx = O2SurfaceGetWidth(surface) / logicalSize.width;
        CGFloat sy = O2SurfaceGetHeight(surface) / logicalSize.height;
        _userToDeviceTransform = O2AffineTransformMake(sx, 0, 0, -sy, 0, O2SurfaceGetHeight(surface));
        O2ContextSetCTM(self, O2AffineTransformIdentity);
    }
    return self;
}
@end

// Memory the host can map: a memfd where the host's libc has one (Linux, and
// Android from API 30), else an unlinked POSIX shared memory object.
static int createSharedMemory(size_t size) {
    static int (*memfdCreate)(const char *, unsigned int);
    static BOOL looked;
    int fd = -1;

    if (!looked) {
        looked = YES;
        if (_elfcalls != NULL)
            memfdCreate = _elfcalls->dlsym(NULL, "memfd_create");
    }
    if (memfdCreate != NULL)
        fd = memfdCreate("darling-pocket", 1 /* MFD_CLOEXEC */);

    if (fd < 0 && _elfcalls != NULL && _elfcalls->shm_open != NULL) {
        static unsigned counter;
        char name[64];
        for (int attempt = 0; fd < 0 && attempt < 16; attempt++) {
            snprintf(name, sizeof(name), "/darling-pocket-%d-%u", getpid(), counter++);
            // Native, so the Linux O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC.
            fd = _elfcalls->shm_open(name, 02 | 0100 | 0200 | 02000000, 0600);
        }
        if (fd >= 0)
            _elfcalls->shm_unlink(name);
    }
    if (fd < 0)
        return -1;
    if (ftruncate(fd, (off_t) size) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

@implementation PocketWindow

- (instancetype) initWithDelegate: (NSWindow *) delegate {
    if ((self = [super init]) == nil)
        return nil;
    _delegate = delegate;
    _level = [delegate level];
    _styleMask = [delegate styleMask];
    _isOpaque = [delegate isOpaque];
    _deviceDictionary = [NSMutableDictionary new];
    _display = [(PocketDisplay *) [NSDisplay currentDisplay] retain];
    _frame = [delegate frame];
    _frame.size.width = MAX(_frame.size.width, 1.0);
    _frame.size.height = MAX(_frame.size.height, 1.0);
    [_display windowCreated: self];
    return self;
}

- (void) dealloc {
    [self invalidate];
    [_display release];
    [_deviceDictionary release];
    [_title release];
    [super dealloc];
}

- (void) invalidate {
    if (_invalidated)
        return;
    _invalidated = YES;
    [_context release];
    _context = nil;
    [_delegate platformWindowDidInvalidateCGContext: self];
    _delegate = nil;
    struct pocket_window_id message = {[self number]};
    [_display send: POCKET_DESTROY bytes: &message length: sizeof(message)];
    if (_pixels != NULL)
        munmap(_pixels, _bufferSize);
    _pixels = NULL;
    [_display windowDestroyed: self];
}

- (void) setDelegate: (id) delegate { _delegate = delegate; }
- (NSWindow *) delegate { return _delegate; }
- (void) syncDelegateProperties {}
- (uint32_t) number { return (uint32_t) [self windowNumber]; }
- (BOOL) isVisible { return _visible; }
- (int) level { return _level; }
- (O2Rect) frame { return _frame; }

#pragma mark - What the host knows

// The window in the screen's pixels, from the top left.
- (void) sendState {
    if (_invalidated)
        return;
    CGFloat scale = [_display scale];
    NSRect screen = [_display screenFrame];
    struct pocket_window message = {
        .window = [self number],
        .x = (int32_t) lround(_frame.origin.x * scale),
        .y = (int32_t) lround((NSMaxY(screen) - NSMaxY(_frame)) * scale),
        .width = (int32_t) lround(_frame.size.width * scale),
        .height = (int32_t) lround(_frame.size.height * scale),
        .flags = (_visible ? POCKET_WINDOW_VISIBLE : 0) | (_isOpaque ? POCKET_WINDOW_OPAQUE : 0),
        .level = _level,
    };
    [_display send: POCKET_WINDOW bytes: &message length: sizeof(message)];
}

- (void) show {
    BOOL wasVisible = _visible;
    _visible = YES;
    [_display windowRaised: self];
    if (!wasVisible) {
        [self sendState];
        [_delegate platformWindowActivated: self displayIfNeeded: YES];
    }
}

- (void) hide {
    if (!_visible)
        return;
    _visible = NO;
    [self sendState];
    [_display updateKeyboard];
}

- (void) showWindowWithoutActivation { [self show]; }
- (void) showWindowForAppActivation: (NSRect) frame { [self show]; }
- (void) hideWindowForAppDeactivation: (NSRect) frame {}
- (void) hideWindow { [self hide]; }

- (void) sheetOrderFrontFromFrame: (NSRect) frame aboveWindow: (CGWindow *) aboveWindow {
    [self setFrame: frame];
    [self show];
}

- (void) sheetOrderOutToFrame: (NSRect) frame { [self hide]; }

- (void) placeAboveWindow: (NSInteger) otherNumber { [self show]; }

- (void) placeBelowWindow: (NSInteger) otherNumber {
    [self show];
    [_display windowLowered: self];
}

- (void) makeKey { [self show]; }
- (void) makeMain {}
- (void) captureEvents {}
- (void) miniaturize { [self hide]; }
- (void) deminiaturize { [self show]; }
- (BOOL) isMiniaturized { return NO; }
- (void) flashWindow {}

- (NSUInteger) styleMask { return _styleMask; }
- (void) setStyleMask: (NSUInteger) mask { _styleMask = mask; }

- (void) setLevel: (int) value {
    _level = value;
    [self sendState];
}

- (void) setTitle: (NSString *) title {
    [_title release];
    _title = [title copy];
}

- (void) setOpaque: (BOOL) value {
    _isOpaque = value;
    [self sendState];
}

- (void) setAlphaValue: (CGFloat) value {}
- (void) setHasShadow: (BOOL) value {}
- (CGLContextObj) cglContext { return NULL; }

- (void) addEntriesToDeviceDictionary: (NSDictionary *) entries {
    [_deviceDictionary addEntriesFromDictionary: entries];
}

// Layers and OpenGL views draw into the window's own content here.
- (CGSubWindow *) createSubWindowWithFrame: (CGRect) frame { return nil; }

- (void) setFrame: (O2Rect) frame {
    frame.size.width = MAX(frame.size.width, 1.0);
    frame.size.height = MAX(frame.size.height, 1.0);
    if (NSEqualRects(frame, _frame))
        return;
    if (!NSEqualSizes(frame.size, _frame.size)) {
        [_context release];
        _context = nil;
        [_delegate platformWindowDidInvalidateCGContext: self];
    }
    _frame = frame;
    [self sendState];
}

// The screen's scale or size changed.
- (void) screenChanged {
    [_context release];
    _context = nil;
    [_delegate platformWindowDidInvalidateCGContext: self];
    [self sendState];
    [_delegate display];
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    NSPoint global = [_display mouseLocation];
    return NSMakePoint(global.x - _frame.origin.x, global.y - _frame.origin.y);
}

- (CGFloat) backingScaleFactor { return [_display scale]; }

#pragma mark - Drawing

- (O2Context *) cgContext {
    if (_context == nil) {
        CGFloat scale = [_display scale];
        NSSize logical = NSMakeSize(ceil(_frame.size.width), ceil(_frame.size.height));
        size_t width = (size_t) ceil(logical.width * scale);
        size_t height = (size_t) ceil(logical.height * scale);
        if (width < 1 || height < 1 || width > 16384 || height > 16384) {
            NSLog(@"Pocket backend: a %zux%zu window buffer is too large", width, height);
            return nil;
        }
        O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
        O2Surface *surface = [[O2Surface alloc] initWithBytes: NULL
                                                        width: width
                                                       height: height
                                             bitsPerComponent: 8
                                                  bytesPerRow: 0
                                                   colorSpace: colorSpace
                                                   bitmapInfo: kO2ImageAlphaPremultipliedFirst | kO2BitmapByteOrder32Little];
        O2ColorSpaceRelease(colorSpace);
        _context = [[PocketDrawingContext alloc] initWithSurface: surface logicalSize: logical];
        [surface release];
    }
    return _context;
}

// A shared buffer as large as the surface, given to the host.
- (BOOL) ensureBufferWidth: (uint32_t) width height: (uint32_t) height {
    if (_pixels != NULL && _bufferWidth == width && _bufferHeight == height)
        return YES;
    if (_pixels != NULL)
        munmap(_pixels, _bufferSize);
    _pixels = NULL;

    size_t size = (size_t) width * height * 4;
    int fd = createSharedMemory(size);
    if (fd < 0) {
        NSLog(@"Pocket backend: no shared memory for a %ux%u window", width, height);
        return NO;
    }
    void *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) {
        NSLog(@"Pocket backend: cannot map a %ux%u window buffer: %s", width, height, strerror(errno));
        close(fd);
        return NO;
    }
    struct pocket_buffer message = {
        .window = [self number],
        .width = width,
        .height = height,
        .stride = width * 4,
        .format = POCKET_FORMAT_BGRA,
    };
    [_display send: POCKET_BUFFER bytes: &message length: sizeof(message) fd: fd];
    close(fd);
    _pixels = pixels;
    _bufferSize = size;
    _bufferWidth = width;
    _bufferHeight = height;
    return YES;
}

- (void) present {
    if (!_needsPresent || _busy || !_visible || _context == nil || _invalidated)
        return;
    O2Surface *surface = [_context surface];
    size_t width = O2SurfaceGetWidth(surface);
    size_t height = O2SurfaceGetHeight(surface);
    size_t stride = O2SurfaceGetBytesPerRow(surface);
    const uint8_t *pixels = O2SurfaceGetPixelBytes(surface);
    if (pixels == NULL || ![self ensureBufferWidth: (uint32_t) width height: (uint32_t) height])
        return;

    if (stride == width * 4)
        memcpy(_pixels, pixels, width * height * 4);
    else
        for (size_t row = 0; row < height; row++)
            memcpy((uint8_t *) _pixels + row * width * 4, pixels + row * stride, width * 4);

    struct pocket_present message = {[self number], 0, 0, (int32_t) width, (int32_t) height};
    [_display send: POCKET_PRESENT bytes: &message length: sizeof(message)];
    _busy = YES;
    _needsPresent = NO;
}

- (void) flushBuffer {
    if (_context == nil)
        return;
    O2ContextFlush(_context);
    _needsPresent = YES;
    [self present];
    [_display updateKeyboard];
}

- (void) bufferReleased {
    _busy = NO;
    [self present];
}

@end
