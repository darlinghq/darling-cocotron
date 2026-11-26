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
#import <CoreGraphics/CoreGraphicsPrivate.h>

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
        } else if (!mainConnectionFailureLogged && !_CGSWindowServerConnectionsDenied()) {
            // (a process that denied itself connections expects to have none)
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

// Called by CGSShutdownServerConnections: the shutdown empties the connection table, so the
// cached id must not outlive it.
__attribute__((visibility("hidden")))
void _CGSResetMainConnection(void)
{
    pthread_mutex_lock(&mainConnectionLock);
    mainConnectionID = 0;
    mainConnectionFailureLogged = NO;
    pthread_mutex_unlock(&mainConnectionLock);
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

#pragma mark - Connection properties

static pthread_mutex_t connectionPropertiesLock = PTHREAD_MUTEX_INITIALIZER;
// connection id -> (key -> value)
static CFMutableDictionaryRef connectionProperties;

// A connection's properties may be set and read by the connection itself only.
static BOOL isOwnConnection(CGSConnectionID cid, CGSConnectionID ownerCid)
{
    return cid == ownerCid && _CGSConnectionForID(cid) != nil;
}

CGError CGSSetConnectionProperty(CGSConnectionID cid, CGSConnectionID ownerCid, CFStringRef key, CFTypeRef value)
{
    if (!isOwnConnection(cid, ownerCid) || key == NULL)
        return kCGErrorFailure;

    pthread_mutex_lock(&connectionPropertiesLock);
    if (connectionProperties == NULL)
        connectionProperties = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef properties = (CFMutableDictionaryRef) CFDictionaryGetValue(connectionProperties, (const void *) (uintptr_t) cid);
    if (properties == NULL && value != NULL) {
        properties = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(connectionProperties, (const void *) (uintptr_t) cid, properties);
        CFRelease(properties);
    }
    if (properties != NULL) {
        if (value != NULL)
            CFDictionarySetValue(properties, key, value);
        else
            CFDictionaryRemoveValue(properties, key);
    }
    pthread_mutex_unlock(&connectionPropertiesLock);
    return kCGErrorSuccess;
}

CGError CGSCopyConnectionProperty(CGSConnectionID cid, CGSConnectionID ownerCid, CFStringRef key, CFTypeRef *value)
{
    if (!isOwnConnection(cid, ownerCid) || key == NULL || value == NULL)
        return kCGErrorFailure;

    pthread_mutex_lock(&connectionPropertiesLock);
    CFDictionaryRef properties = connectionProperties != NULL
        ? (CFDictionaryRef) CFDictionaryGetValue(connectionProperties, (const void *) (uintptr_t) cid) : NULL;
    CFTypeRef found = properties != NULL ? CFDictionaryGetValue(properties, key) : NULL;
    *value = found != NULL ? CFRetain(found) : NULL;
    pthread_mutex_unlock(&connectionPropertiesLock);
    return kCGErrorSuccess;
}

#pragma mark - Connection notifications

// The display servers Darling draws through tell nothing of the occlusion or modification of
// windows, so registered procs are accepted and never called, and enabling these notifications
// succeeds without effect.
CGError CGSRegisterConnectionNotifyProc(CGSConnectionID cid, CGSNotifyConnectionProcPtr proc, uint32_t type, void *arg)
{
    return kCGErrorSuccess;
}

// Inference (no evidence of the value for a visible process; macOS gave false to a process with
// no visible window): the process counts as visible, since occlusion is not tracked.
CGError CGSPackagesEnableConnectionOcclusionNotifications(CGSConnectionID cid, bool enable, bool *outCurrentVisibilityState)
{
    if (outCurrentVisibilityState != NULL)
        *outCurrentVisibilityState = true;
    return kCGErrorSuccess;
}

// The connection counts as idle, as macOS reported for a connection with no window changes.
CGError CGSPackagesEnableConnectionWindowModificationNotifications(CGSConnectionID cid, bool enable, bool *outConnectionIsCurrentlyIdle)
{
    if (outConnectionIsCurrentlyIdle != NULL)
        *outConnectionIsCurrentlyIdle = true;
    return kCGErrorSuccess;
}
