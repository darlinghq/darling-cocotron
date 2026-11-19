#import "CGDisplayReconfiguration.h"
#include <pthread.h>
#include <stdlib.h>

// Callbacks are told about display changes this process makes through
// CoreGraphics (CGDisplaySwitchToMode and friends): once with
// kCGDisplayBeginConfigurationFlag before the change and once with the
// summary flags after it. Changes made by other processes are not reported.
typedef struct {
    CGDisplayReconfigurationCallBack callback;
    void *userInfo;
} ReconfigurationEntry;

static ReconfigurationEntry *gEntries;
static size_t gEntryCount;
static pthread_mutex_t gEntriesLock = PTHREAD_MUTEX_INITIALIZER;

CGError CGDisplayRegisterReconfigurationCallback(CGDisplayReconfigurationCallBack callback, void *userInfo) {
    if (callback == NULL)
        return kCGErrorIllegalArgument;
    pthread_mutex_lock(&gEntriesLock);
    ReconfigurationEntry *grown = realloc(gEntries, (gEntryCount + 1) * sizeof *gEntries);
    if (grown == NULL) {
        pthread_mutex_unlock(&gEntriesLock);
        return kCGErrorFailure;
    }
    gEntries = grown;
    gEntries[gEntryCount++] = (ReconfigurationEntry){callback, userInfo};
    pthread_mutex_unlock(&gEntriesLock);
    return kCGErrorSuccess;
}

CGError CGDisplayRemoveReconfigurationCallback(CGDisplayReconfigurationCallBack callback, void *userInfo) {
    CGError result = kCGErrorFailure;
    pthread_mutex_lock(&gEntriesLock);
    for (size_t i = 0; i < gEntryCount; i++) {
        if (gEntries[i].callback == callback && gEntries[i].userInfo == userInfo) {
            gEntries[i] = gEntries[--gEntryCount];
            result = kCGErrorSuccess;
            break;
        }
    }
    pthread_mutex_unlock(&gEntriesLock);
    return result;
}

void CGDisplayPostReconfiguration(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags) {
    // Callbacks may register or remove callbacks, so call a snapshot.
    pthread_mutex_lock(&gEntriesLock);
    size_t count = gEntryCount;
    ReconfigurationEntry *copy = count ? malloc(count * sizeof *copy) : NULL;
    if (copy)
        for (size_t i = 0; i < count; i++)
            copy[i] = gEntries[i];
    pthread_mutex_unlock(&gEntriesLock);
    if (copy == NULL)
        return;
    for (size_t i = 0; i < count; i++)
        copy[i].callback(display, flags, copy[i].userInfo);
    free(copy);
}

void CGRestorePermanentDisplayConfiguration()
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}
