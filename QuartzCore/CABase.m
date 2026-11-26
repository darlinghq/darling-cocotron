#import <Foundation/NSString.h>
#import <QuartzCore/CABase.h>
#import <mach/mach_time.h>
#import <mach/port.h>

static double conversionFactor() {
    struct mach_timebase_info timebase;
    kern_return_t error;

    if ((mach_timebase_info(&timebase)) != KERN_SUCCESS) {
        NSLog(@"mach_timebase_info returned %d", error);
        return 1;
    }

    return 0.000000001 * ((double) timebase.numer / (double) timebase.denom);
}

CFTimeInterval CACurrentMediaTime(void) {
    uint64_t value = mach_absolute_time();

    return ((double) value) * conversionFactor();
}

// Frees the memory of backing stores no longer in use. Layers are drawn without a render server
// and keep no such cache, so there is nothing to free.
void CABackingStoreCollectBlocking(void) {
}

// The port of the render server with the name, or of the default one for NULL; MACH_PORT_NULL
// when there is no such server, as there never is: layers are drawn in the process.
mach_port_t CARenderServerGetServerPort(const char *name) {
    return MACH_PORT_NULL;
}
