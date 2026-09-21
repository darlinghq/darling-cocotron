/*
 This file is part of Darling.

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/
#import <CoreGraphics/CGSServerSPI.h>
#import <CoreGraphics/CGWindowPrivate.h>
#include <math.h>
#include <pthread.h>

@class CGSConnection;

// Declared here rather than through CoreGraphicsPrivate.h; attribs is a nullable pointer there.
extern CGError CGSNewConnection(void *_Nullable attribs, CGSConnectionID *connId);
extern CGSConnection *_CGSConnectionForID(CGSConnectionID connId);

static pthread_mutex_t mainConnectionLock = PTHREAD_MUTEX_INITIALIZER;
static CGSConnectionID mainConnectionID; // 0 until created
static BOOL mainConnectionFailureLogged;

CGSConnectionID CGSMainConnectionID(void)
{
    CGSConnectionID result;

    // GUESS: created on the first call, under a lock so racing first calls create one connection.
    pthread_mutex_lock(&mainConnectionLock);
    if (mainConnectionID == 0) {
        CGSConnectionID created = 0;
        CGError error = CGSNewConnection(NULL, &created);

        if (error == kCGErrorSuccess && created != 0 &&
            _CGSConnectionForID(created) != nil) {
            mainConnectionID = created;
        } else if (!mainConnectionFailureLogged) {
            // GUESS: failure returns 0 and is not cached, so a later call retries.
            mainConnectionFailureLogged = YES;
            NSLog(@"CGSMainConnectionID: cannot create the default connection "
                  @"(CGSNewConnection error %d, id %u)",
                  (int) error, created);
        }
    }
    result = mainConnectionID;
    pthread_mutex_unlock(&mainConnectionLock);

    return result;
}

CGError CGSSetWindowAlpha(CGSConnectionID connection, CGSWindowID windowID,
                          float alpha)
{
    // GUESS: the identifier is the window number AppKit reports for the window.
    CGWindow *window = [CGWindow windowWithWindowNumber: windowID];
    // GUESS: an unknown window is an illegal argument.
    if (window == nil)
        return kCGErrorIllegalArgument;

    // GUESS: clamp to the NSWindow.alphaValue range (NaN becomes 0).
    [window setAlphaValue: fmin(fmax(alpha, 0.0), 1.0)];
    return kCGErrorSuccess;
}
