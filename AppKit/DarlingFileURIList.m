/* Copyright (c) 2008 Johannes Fortmann

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

#import "DarlingFileURIList.h"
#include <string.h>

static const NSUInteger DarlingURITransferLimit = 16 * 1024 * 1024;
static const NSUInteger DarlingURIRecordLimit = 4096;
// Host paths reach the guest through this prefix, so a drop and a paste of the same
// file agree on its name whichever backend delivered it.
static NSString *const DarlingURIHostRoot = @"/Volumes/SystemRoot";

static BOOL DarlingURILiteralByte(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
           (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_' ||
           c == '~' || c == '/';
}

static int DarlingURIHexValue(unsigned char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static BOOL DarlingURIValidHostPath(NSString *path) {
    if ([path length] >= 4096) return NO;
    NSData *bytes = [path dataUsingEncoding: NSUTF8StringEncoding];
    // The byte bound includes the guest prefix, and is checked before the path is split.
    if (!bytes || [bytes length] + [DarlingURIHostRoot length] >= 4096 ||
        memchr([bytes bytes], 0, [bytes length]) != NULL) return NO;
    return [path hasPrefix: @"/"] && ![path hasPrefix: @"//"] &&
           ![[path componentsSeparatedByString: @"/"] containsObject: @".."];
}

// Decodes one URI path into a host path, refusing anything that could escape it.
static NSString *DarlingURIHostPathFromURI(NSString *path) {
    NSData *encoded = [path dataUsingEncoding: NSUTF8StringEncoding];
    if (!encoded) return nil;
    const unsigned char *p = [encoded bytes];
    NSMutableData *decoded = [NSMutableData dataWithCapacity: [encoded length]];
    for (NSUInteger i = 0; i < [encoded length]; i++) {
        unsigned char c = p[i];
        if (c == '%') {
            if (i + 2 >= [encoded length]) return nil;
            int hi = DarlingURIHexValue(p[i + 1]), lo = DarlingURIHexValue(p[i + 2]);
            if (hi < 0 || lo < 0) return nil;
            c = (hi << 4) | lo;
            i += 2;
            // A NUL would truncate, and an escaped slash would forge a new path
            // component the sender never wrote.
            if (!c || c == '/') return nil;
        } else if (!DarlingURILiteralByte(c) && c != ':' && c != '@' &&
                   strchr("!$&'()*+,;=", c) == NULL) {
            return nil;
        }
        [decoded appendBytes: &c length: 1];
    }
    NSString *host = [[[NSString alloc] initWithData: decoded
                                            encoding: NSUTF8StringEncoding] autorelease];
    return DarlingURIValidHostPath(host) ? host : nil;
}

static NSString *DarlingURIHostPathFromLine(NSString *line) {
    if ([line length] < 6 ||
        [[line substringToIndex: 5] caseInsensitiveCompare: @"file:"] != NSOrderedSame)
        return nil;
    NSString *path = [line substringFromIndex: 5];
    if ([path hasPrefix: @"//"]) {
        NSRange slash = [path rangeOfString: @"/"
                                   options: 0
                                     range: NSMakeRange(2, [path length] - 2)];
        if (slash.location == NSNotFound) return nil;
        NSString *authority = [path substringWithRange: NSMakeRange(2, slash.location - 2)];
        if ([authority length] &&
            [authority caseInsensitiveCompare: @"localhost"] != NSOrderedSame)
            return nil;
        path = [path substringFromIndex: slash.location];
    }
    return DarlingURIHostPathFromURI(path);
}

NSArray *DarlingFilenamesFromURIList(NSData *data) {
    if (![data isKindOfClass: [NSData class]] || ![data length] ||
        [data length] > DarlingURITransferLimit)
        return nil;
    // Bound the record count before splitting, so an input of nothing but newlines
    // cannot be expanded into an unbounded array.
    const unsigned char *wire = [data bytes];
    NSUInteger lines = 0;
    for (NSUInteger i = 0; i < [data length]; i++)
        if (wire[i] == '\n' && ++lines > DarlingURIRecordLimit) return nil;
    if (lines == DarlingURIRecordLimit && wire[[data length] - 1] != '\n') return nil;

    NSString *text = [[[NSString alloc] initWithData: data
                                            encoding: NSUTF8StringEncoding] autorelease];
    if (!text || memchr(wire, 0, [data length]) != NULL) return nil;

    NSMutableArray *files = [NSMutableArray array];
    for (NSString *rawLine in [text componentsSeparatedByString: @"\n"]) {
        NSString *line = [rawLine hasSuffix: @"\r"]
                                 ? [rawLine substringToIndex: [rawLine length] - 1]
                                 : rawLine;
        if (![line length] || [line hasPrefix: @"#"]) continue;
        NSString *host = DarlingURIHostPathFromLine(line);
        if (!host) return nil; // All or nothing: a partial list would drop files.
        [files addObject: [DarlingURIHostRoot stringByAppendingString: host]];
    }
    return [files count] ? files : nil;
}

NSData *DarlingURIListFromFilenames(NSArray *filenames) {
    if (![filenames isKindOfClass: [NSArray class]] || ![filenames count] ||
        [filenames count] > DarlingURIRecordLimit)
        return nil;
    NSMutableData *result = [NSMutableData data];
    NSString *boundary = [DarlingURIHostRoot stringByAppendingString: @"/"];
    static const char hex[] = "0123456789ABCDEF";
    for (id filename in filenames) {
        if (![filename isKindOfClass: [NSString class]] || ![filename hasPrefix: boundary])
            return nil;
        NSString *host = [filename substringFromIndex: [DarlingURIHostRoot length]];
        if (!DarlingURIValidHostPath(host)) return nil;
        NSData *bytes = [host dataUsingEncoding: NSUTF8StringEncoding];
        if ([result length] + 9 + 3 * [bytes length] > DarlingURITransferLimit) return nil;
        [result appendBytes: "file://" length: 7];
        const unsigned char *p = [bytes bytes];
        for (NSUInteger i = 0; i < [bytes length]; i++) {
            if (DarlingURILiteralByte(p[i])) {
                [result appendBytes: p + i length: 1];
            } else {
                char escaped[] = {'%', hex[p[i] >> 4], hex[p[i] & 15]};
                [result appendBytes: escaped length: 3];
            }
        }
        [result appendBytes: "\r\n" length: 2];
    }
    return result;
}
