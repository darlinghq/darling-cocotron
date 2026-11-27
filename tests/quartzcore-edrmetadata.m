/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CAEDRMetadata must decode the public HDR10 SEI payloads before passing them to a
 * window-system surface. The vectors below follow SMPTE ST 2086 (mastering display
 * colour volume) and CTA-861.3 (content light level): both are big-endian, the xy
 * coordinates carry four decimals, the minimum luminance four decimals, and the
 * maximum luminance whole nits. The test checks the units and the conversion from
 * the SEI green/blue/red/white order to the r/g/b/white order used by the
 * Wayland color-management protocol.
 */
#import <Foundation/NSData.h>
#import <QuartzCore/CAEDRMetadata.h>
#import "../QuartzCore/CAEDRMetadataInternal.h"
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL: %s (line %d)\n", #cond, __LINE__); failures++; } } while (0)

static NSData *BigEndian16(const uint16_t *values, NSUInteger count) {
    NSMutableData *data = [NSMutableData dataWithCapacity: count * 2];
    for (NSUInteger i = 0; i < count; i++) {
        uint8_t bytes[2] = {(uint8_t) (values[i] >> 8), (uint8_t) values[i]};
        [data appendBytes: bytes length: sizeof(bytes)];
    }
    return data;
}

static CAEDRHDRDescription Decode(CAEDRMetadata *metadata) {
    CAEDRHDRDescription description = {};
    [metadata copyHDRDescription: &description];
    return description;
}

static void checkPrimaries(const CAEDRHDRDescription *description) {
    static const int32_t expected[8] = {
            708000, 292000, 170000, 797000, 131000, 46000, 312700, 329000}; // x/y * 1e6
    CHECK(description->hasMasteringDisplayPrimaries);
    for (NSUInteger i = 0; i < 8; i++)
        CHECK(description->masteringDisplayPrimaries[i] == expected[i]);
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    // BT.2020 primaries and D65 white, in the ST 2086 order: green, blue, red,
    // white. ST 2086 carries four decimals (0.1700 is 1700); the Wayland color
    // protocol carries six, so the decoded values are multiplied by 100.
    static const uint16_t display[10] = {
            1700, 7970, 1310, 460, 7080, 2920, 3127, 3290, 1000, 1};
    static const uint16_t content[2] = {1000, 400};
    CAEDRMetadata *hdr10 = [CAEDRMetadata HDR10MetadataWithDisplayInfo: BigEndian16(display, 10)
                                                           contentInfo: BigEndian16(content, 2)
                                                    opticalOutputScale: 100.0f];
    CAEDRHDRDescription decoded = Decode(hdr10);
    CHECK(decoded.transfer == CAEDRTransferHDR10);
    checkPrimaries(&decoded);
    CHECK(decoded.hasMasteringLuminance);
    CHECK(decoded.masteringMaxLuminance == 1000);
    CHECK(decoded.masteringMinLuminance == 1); // 0.0001 cd/m^2 * 10000
    CHECK(decoded.hasMaxCLL && decoded.maxCLL == 1000);
    CHECK(decoded.hasMaxFALL && decoded.maxFALL == 400);
    CHECK(decoded.opticalOutputScale == 100.0f);

    // The convenience constructor carries the luminance range directly.
    CAEDRMetadata *simple = [CAEDRMetadata HDR10MetadataWithMinLuminance: 0.0001f
                                                            maxLuminance: 1000.0f
                                                      opticalOutputScale: 100.0f];
    decoded = Decode(simple);
    CHECK(decoded.transfer == CAEDRTransferHDR10);
    CHECK(!decoded.hasMasteringDisplayPrimaries);
    CHECK(decoded.hasMasteringLuminance);
    CHECK(decoded.masteringMinLuminance == 1 && decoded.masteringMaxLuminance == 1000);
    CHECK(!decoded.hasMaxCLL && !decoded.hasMaxFALL);

    // HLG has no static HDR10 metadata, but its transfer must still reach the surface.
    CAEDRMetadata *hlg = [CAEDRMetadata HLGMetadata];
    decoded = Decode(hlg);
    CHECK(decoded.transfer == CAEDRTransferHLG);
    CHECK(!decoded.hasMasteringDisplayPrimaries && !decoded.hasMaxCLL);

    // Short or zero-valued payloads leave the corresponding fields unset so the
    // compositor's defaults apply.
    static const uint16_t zeroDisplay[10] = {0};
    static const uint16_t zeroContent[2] = {0};
    CAEDRMetadata *empty = [CAEDRMetadata HDR10MetadataWithDisplayInfo:
                                    BigEndian16(zeroDisplay, 10)
                                                           contentInfo: BigEndian16(zeroContent, 2)
                                                    opticalOutputScale: 0.0f];
    decoded = Decode(empty);
    CHECK(!decoded.hasMasteringDisplayPrimaries && !decoded.hasMasteringLuminance);
    CHECK(!decoded.hasMaxCLL && !decoded.hasMaxFALL);
    CHECK(decoded.opticalOutputScale == 0);

    NSData *shortData = BigEndian16(display, 9);
    CAEDRMetadata *shortMetadata = [CAEDRMetadata HDR10MetadataWithDisplayInfo: shortData
                                                                   contentInfo: nil
                                                            opticalOutputScale: 100.0f];
    decoded = Decode(shortMetadata);
    CHECK(!decoded.hasMasteringDisplayPrimaries && !decoded.hasMaxCLL);

    // A coordinate outside the ST 2086 bounds, or a range whose maximum does not exceed
    // its minimum, must not be passed to the compositor.
    uint16_t outOfRange[10];
    memcpy(outOfRange, display, sizeof(outOfRange));
    outOfRange[0] = 8000; // 0.8000 exceeds the 0.7400 x bound
    decoded = Decode([CAEDRMetadata HDR10MetadataWithDisplayInfo: BigEndian16(outOfRange, 10)
                                                     contentInfo: BigEndian16(content, 2)
                                              opticalOutputScale: 100.0f]);
    CHECK(!decoded.hasMasteringDisplayPrimaries && !decoded.hasMasteringLuminance);
    CHECK(decoded.hasMaxCLL && decoded.maxCLL == 1000);

    uint16_t badRange[10];
    memcpy(badRange, display, sizeof(badRange));
    badRange[8] = badRange[9] = 1000;
    decoded = Decode([CAEDRMetadata HDR10MetadataWithDisplayInfo: BigEndian16(badRange, 10)
                                                     contentInfo: nil
                                              opticalOutputScale: 100.0f]);
    CHECK(!decoded.hasMasteringDisplayPrimaries && !decoded.hasMasteringLuminance);

    // CTA-861.3 needs both light-level fields; a truncated payload supplies neither.
    decoded = Decode([CAEDRMetadata HDR10MetadataWithDisplayInfo: nil
                                                     contentInfo: BigEndian16(content, 1)
                                              opticalOutputScale: 100.0f]);
    CHECK(!decoded.hasMaxCLL && !decoded.hasMaxFALL);

    [pool release];
    if (failures == 0) {
        printf("ALL PASSED\n");
        return 0;
    }
    return 1;
}
