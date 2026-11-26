// CGDataProviderCreateDirect and CGDataProviderCreateSequential (documented in
// Apple's CGDataProvider reference): the provider's data is what the callbacks
// produce, and the info is released (releaseInfo) when the provider is.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

static const unsigned char source[] = "0123456789abcdefghijklmnopqrstuvwxyz";
#define SOURCE_SIZE (sizeof(source) - 1)

typedef struct {
    size_t position;
    unsigned pointerReleases;
    unsigned infoReleases;
} Record;

static int failures;
#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); \
        failures++; \
    } else \
        printf("PASS %s\n", #condition); \
} while (0)

static const void *getBytePointer(void *info) {
    (void) info;
    return source;
}

static void releaseBytePointer(void *info, const void *pointer) {
    Record *record = info;
    if (pointer == source)
        record->pointerReleases++;
}

// hands out at most 5 bytes per call, so that the provider has to ask again
static size_t getBytesAtPosition(void *info, void *buffer, off_t position, size_t count) {
    (void) info;
    if (position >= (off_t) SOURCE_SIZE)
        return 0;
    size_t available = SOURCE_SIZE - (size_t) position;
    size_t n = count < available ? count : available;
    if (n > 5)
        n = 5;
    memcpy(buffer, source + position, n);
    return n;
}

static size_t getBytes(void *info, void *buffer, size_t count) {
    Record *record = info;
    size_t n = getBytesAtPosition(info, buffer, (off_t) record->position, count);
    record->position += n;
    return n;
}

static off_t skipForward(void *info, off_t count) {
    Record *record = info;
    record->position += (size_t) count;
    return count;
}

static void rewindStream(void *info) {
    ((Record *) info)->position = 0;
}

static void releaseInfo(void *info) {
    ((Record *) info)->infoReleases++;
}

static int providerHoldsSource(CGDataProviderRef provider) {
    CFDataRef data = CGDataProviderCopyData(provider);
    int same = data != NULL && (size_t) CFDataGetLength(data) == SOURCE_SIZE
        && memcmp(CFDataGetBytePtr(data), source, SOURCE_SIZE) == 0;
    if (data != NULL)
        CFRelease(data);
    return same;
}

int main(void) {
    Record pointerRecord = { 0 };
    CGDataProviderDirectCallbacks pointerCallbacks = { 0, getBytePointer, releaseBytePointer, NULL, releaseInfo };
    CGDataProviderRef provider = CGDataProviderCreateDirect(&pointerRecord, SOURCE_SIZE, &pointerCallbacks);
    CHECK(provider != NULL);
    CHECK(providerHoldsSource(provider));
    CHECK(pointerRecord.pointerReleases == 1);
    CHECK(pointerRecord.infoReleases == 0);
    CGDataProviderRelease(provider);
    CHECK(pointerRecord.infoReleases == 1);

    Record positionRecord = { 0 };
    CGDataProviderDirectCallbacks positionCallbacks = { 0, NULL, NULL, getBytesAtPosition, releaseInfo };
    provider = CGDataProviderCreateDirect(&positionRecord, SOURCE_SIZE, &positionCallbacks);
    CHECK(provider != NULL);
    CHECK(providerHoldsSource(provider));
    CGDataProviderRelease(provider);
    CHECK(positionRecord.infoReleases == 1);

    Record sequentialRecord = { 0 };
    CGDataProviderSequentialCallbacks sequentialCallbacks = { 0, getBytes, skipForward, rewindStream, releaseInfo };
    provider = CGDataProviderCreateSequential(&sequentialRecord, &sequentialCallbacks);
    CHECK(provider != NULL);
    CHECK(providerHoldsSource(provider));
    CGDataProviderRelease(provider);
    CHECK(sequentialRecord.infoReleases == 1);

    // a provider needs a way to get its data
    CGDataProviderDirectCallbacks none = { 0, NULL, NULL, NULL, NULL };
    CHECK(CGDataProviderCreateDirect(NULL, SOURCE_SIZE, &none) == NULL);
    CHECK(CGDataProviderCreateDirect(NULL, SOURCE_SIZE, NULL) == NULL);
    CHECK(CGDataProviderCreateSequential(NULL, NULL) == NULL);

    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
