/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CAEDRMetadata must decode the public HDR10 SEI payloads before passing them to a
 * window-system surface. The vectors below follow SMPTE ST 2086 (mastering display
 * colour volume, 24 bytes: the green, blue, red primaries and the white point as
 * 16-bit x/y in units of 0.00002, then the maximum and minimum luminance as 32-bit
 * values in units of 0.0001 cd/m^2) and CTA-861.3 (content light level, two 16-bit
 * values in cd/m^2). Both are big-endian. The test checks the units and the
 * conversion from the SEI green/blue/red/white order to the r/g/b/white order used
 * by the Wayland color-management protocol.
 */
#import <Foundation/NSAutoreleasePool.h>
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

// The 24-byte ST 2086 payload: eight 16-bit coordinates (green, blue, red, white; units of 0.00002),
// then the 32-bit maximum and minimum luminance in units of 0.0001 cd/m^2.
static NSData *DisplayInfo(const uint16_t coordinates[8], uint32_t maxLuminance, uint32_t minLuminance) {
    NSMutableData *data = [NSMutableData dataWithData: BigEndian16(coordinates, 8)];
    uint8_t luminance[8] = {
            (uint8_t) (maxLuminance >> 24), (uint8_t) (maxLuminance >> 16),
            (uint8_t) (maxLuminance >> 8), (uint8_t) maxLuminance,
            (uint8_t) (minLuminance >> 24), (uint8_t) (minLuminance >> 16),
            (uint8_t) (minLuminance >> 8), (uint8_t) minLuminance};
    [data appendBytes: luminance length: sizeof(luminance)];
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

    // BT.2020 primaries and D65 white, in the ST 2086 order: green, blue, red, white. The unit is
    // 0.00002 (0.1700 is 8500); the Wayland color protocol carries six decimals, so the decoded
    // values are multiplied by 20. The luminances are 1000 cd/m^2 and 0.0001 cd/m^2.
    static const uint16_t coordinates[8] = {8500, 39850, 6550, 2300, 35400, 14600, 15635, 16450};
    NSData *displayData = DisplayInfo(coordinates, 10000000, 1);
    static const uint16_t content[2] = {1000, 400};
    CAEDRMetadata *hdr10 = [CAEDRMetadata HDR10MetadataWithDisplayInfo: displayData
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
    static const uint16_t zeroDisplay[8] = {0};
    static const uint16_t zeroContent[2] = {0};
    CAEDRMetadata *empty = [CAEDRMetadata HDR10MetadataWithDisplayInfo:
                                    DisplayInfo(zeroDisplay, 0, 0)
                                                           contentInfo: BigEndian16(zeroContent, 2)
                                                    opticalOutputScale: 0.0f];
    decoded = Decode(empty);
    CHECK(!decoded.hasMasteringDisplayPrimaries && !decoded.hasMasteringLuminance);
    CHECK(!decoded.hasMaxCLL && !decoded.hasMaxFALL);
    CHECK(decoded.opticalOutputScale == 0);

    NSData *shortData = [displayData subdataWithRange: NSMakeRange(0, 23)];
    CAEDRMetadata *shortMetadata = [CAEDRMetadata HDR10MetadataWithDisplayInfo: shortData
                                                                   contentInfo: nil
                                                            opticalOutputScale: 100.0f];
    decoded = Decode(shortMetadata);
    CHECK(!decoded.hasMasteringDisplayPrimaries && !decoded.hasMaxCLL);

    // A coordinate outside the ST 2086 bounds, or a range whose maximum does not exceed
    // its minimum, must not be passed to the compositor.
    uint16_t outOfRange[8];
    memcpy(outOfRange, coordinates, sizeof(outOfRange));
    outOfRange[0] = 40000; // 0.8000 exceeds the 0.7400 x bound
    decoded = Decode([CAEDRMetadata HDR10MetadataWithDisplayInfo: DisplayInfo(outOfRange, 10000000, 1)
                                                     contentInfo: BigEndian16(content, 2)
                                              opticalOutputScale: 100.0f]);
    CHECK(!decoded.hasMasteringDisplayPrimaries && !decoded.hasMasteringLuminance);
    CHECK(decoded.hasMaxCLL && decoded.maxCLL == 1000);

    decoded = Decode([CAEDRMetadata HDR10MetadataWithDisplayInfo: DisplayInfo(coordinates, 1000, 1000)
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
