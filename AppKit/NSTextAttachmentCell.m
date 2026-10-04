/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/NSRaise.h>
#import <AppKit/NSTextAttachmentCell.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSTextAttachment.h>

@implementation NSTextAttachmentCell

/* The attachment carries raw bytes; it never builds an NSImage for us (`initWithData:ofType:` leaves
 * `_attachmentImage` nil and `_bounds` zero), so the cell decodes and caches one. Cached because -cellSize is called
 * repeatedly by the layout manager while it measures a line fragment. */
- (NSImage *) attachmentImage {
    if (_attachmentImage == nil) {
        NSData *contents = [_attachment contents];
        if (contents != nil && [contents length] > 0)
            _attachmentImage = [[NSImage alloc] initWithData: contents];
    }
    return _attachmentImage;
}

- (void) setAttachment: (NSTextAttachment *) attachment {
    if (attachment != _attachment) {
        [_attachmentImage release];
        _attachmentImage = nil;
    }
    /* Unretained on purpose: the attachment owns the cell, so a strong reference back would be a
     * retain cycle and -dealloc would never run. The cell only reads the attachment while the
     * attachment is alive, during layout and drawing. */
    [_attachment release];
    _attachment = attachment;
}

- (NSTextAttachment *) attachment {
    return _attachment;
}

- (NSSize) cellSize {
    NSImage *image = [self attachmentImage];
    if (image == nil) {
        /* No decodable image: fall back to whatever bounds the attachment declares, else nothing. */
        return [_attachment bounds].size;
    }
    return [image size];
}

- (NSPoint) cellBaselineOffset {
    return NSMakePoint(0, 0);
}

- (NSRect) cellFrameForTextContainer: (NSTextContainer *) textContainer
                proposedLineFragment: (NSRect) proposedRect
                       glyphPosition: (NSPoint) glyphPoint
                      characterIndex: (unsigned) characterIndex
{
    /* Attachments lay out inline at the proposed origin; height comes from the cell, width from the
     * fragment so a wide image does not run past the container. */
    NSSize size = [self cellSize];
    CGFloat width = size.width;
    if (proposedRect.size.width > 0 && width > proposedRect.size.width)
        width = proposedRect.size.width;
    return NSMakeRect(NSMinX(proposedRect), NSMinY(proposedRect), width, size.height);
}

- (BOOL) wantsToTrackMouse {
    return YES;
}

- (BOOL) wantsToTrackMouseForEvent: (NSEvent *) event
                            inRect: (NSRect) rect
                            ofView: (NSView *) view
                  atCharacterIndex: (unsigned) characterIndex
{
    return [self wantsToTrackMouse];
}

- (BOOL) trackMouse: (NSEvent *) event
                  inRect: (NSRect) rect
                  ofView: (NSView *) view
        atCharacterIndex: (unsigned) characterIndex
            untilMouseUp: (BOOL) untilMouseUp
{
    return NO;
}

- (BOOL) trackMouse: (NSEvent *) event
              inRect: (NSRect) rect
              ofView: (NSView *) view
        untilMouseUp: (BOOL) untilMouseUp
{
    return NO;
}

- (void) highlight: (BOOL) highlight
         withFrame: (NSRect) frame
            inView: (NSView *) view
{
    /* Deliberately a no-op: selection highlighting for attachments is drawn by the layout manager's
     * own highlight pass, and painting here would double-draw it. */
}

- (void) drawWithFrame: (NSRect) frame
                inView: (NSView *) view
        characterIndex: (unsigned) characterIndex
         layoutManager: (NSLayoutManager *) layoutManager
{
    NSImage *image = [self attachmentImage];
    if (image == nil || NSIsEmptyRect(frame))
        return;
    /* Draw the representation rather than the NSImage: -[NSImage drawInRect:] is not registered in
     * this AppKit (the runtime raises "unrecognized selector" for it), while NSImageRep's
     * drawInRect: is what NSImage's own drawing path calls internally. */
    NSImageRep *rep = [[image representations] lastObject];
    if (rep != nil)
        [rep drawInRect: frame];
    else
        [image drawInRect: frame];
}

- (void) drawWithFrame: (NSRect) frame
                inView: (NSView *) view
        characterIndex: (unsigned) characterIndex
{
    [self drawWithFrame: frame inView: view characterIndex: characterIndex layoutManager: nil];
}

- (void) drawWithFrame: (NSRect) frame inView: (NSView *) view {
    [self drawWithFrame: frame inView: view characterIndex: 0 layoutManager: nil];
}

- (void) dealloc {
    [_attachmentImage release];
    [_attachment release];
    [super dealloc];
}

@end
