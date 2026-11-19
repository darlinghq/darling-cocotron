/* SPDX-License-Identifier: GPL-3.0-or-later */
/* D4rling / Cocotron ABI26-R2: real Objective-C runtime workload.
 * Copyright (C) 2026. Test fixture only; no claim of production integration.
 * The runner must compile this file against the private candidate header.
 */
#import <Foundation/Foundation.h>
#import <QuartzCore/LegacyIvarLayout.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

static volatile int g_created = 0;
static volatile int g_destroyed = 0;
static volatile int g_failed = 0;

@interface ABI26Value : NSObject <NSCopying> {
    int _number;
}
- (id)initWithNumber:(int)number;
- (int)number;
@end

@implementation ABI26Value
- (id)initWithNumber:(int)number {
    if ((self = [super init])) {
        _number = number;
        __sync_add_and_fetch(&g_created, 1);
    }
    return self;
}
- (int)number { return _number; }
- (id)copyWithZone:(NSZone *)zone {
    return [[ABI26Value allocWithZone:zone] initWithNumber:_number];
}
- (void)dealloc {
    __sync_add_and_fetch(&g_destroyed, 1);
    [super dealloc];
}
@end

@interface ABI26Box : NSObject {
    NS_EXTRA_IVARS_BEGIN(ABI26Box)
        id _retained;
        id _copied;
        int _flag;
    NS_EXTRA_IVARS_END(ABI26Box)
}
@property(retain) id retained;
@property(copy) id copied;
@property int flag;
@end

@implementation ABI26Box
NS_EXTRA_SYNTHESIZE_RETAIN(ABI26Box, retained, _retained, id, retained, setRetained:)
NS_EXTRA_SYNTHESIZE_COPY(ABI26Box, copied, _copied, id, copied, setCopied:)
NS_EXTRA_SYNTHESIZE_ASSIGN(ABI26Box, flag, _flag, int, flag, setFlag:)
- (void)dealloc {
    /* All worker threads must be joined before dealloc; no concurrent
     * NS_EXTRA_FREE/NS_EXTRA_COPY behavior is qualified by this fixture. */
#if !__OBJC2__
    if (NS_EXTRA_ALLOCATED(ABI26Box, self)) {
        struct ABI26BoxExtraIvars *extra = NS_EXTRA(ABI26Box, self);
        [extra->_retained release];
        [extra->_copied release];
    }
    NS_EXTRA_FREE(ABI26Box, self);
#else
    [_retained release];
    [_copied release];
#endif
    [super dealloc];
}
@end

enum { WRITERS = 2, READERS = 3, ROUNDS = 2200 };
typedef struct {
    ABI26Box *box;
    int role;
    int index;
    volatile int *start;
} Worker;

static void check_value(id value) {
    if (value) {
        int number = [(ABI26Value *)value number];
        if (number < 1 || number > WRITERS * ROUNDS)
            __sync_add_and_fetch(&g_failed, 1);
    }
}

static void *worker_main(void *opaque) {
    Worker *worker = (Worker *)opaque;
    NSAutoreleasePool *outer = [[NSAutoreleasePool alloc] init];
    while (!__atomic_load_n(worker->start, __ATOMIC_ACQUIRE)) sched_yield();

    for (int i = 0; i < ROUNDS; ++i) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        if (worker->role == 1) {
            int number = worker->index * ROUNDS + i + 1;
            ABI26Value *value = [[ABI26Value alloc] initWithNumber:number];
            [worker->box setRetained:value];
            [worker->box setCopied:value];
            [worker->box setFlag:number];
            [value release];
        } else {
            id retained = [worker->box retained];
            id copied = [worker->box copied];
            check_value(retained);
            check_value(copied);
            int flag = [worker->box flag];
            if (flag < 0 || flag > WRITERS * ROUNDS)
                __sync_add_and_fetch(&g_failed, 1);
        }
        [pool drain];
        if ((i + 1) % 550 == 0)
            fprintf(stderr, "ABI26_PROGRESS role=%d thread=%d iterations=%d\n",
                    worker->role, worker->index, i + 1);
    }
    [outer drain];
    return NULL;
}

int main(void) {
    alarm(65);
    NSAutoreleasePool *main_pool = [[NSAutoreleasePool alloc] init];
    ABI26Box *box = [[ABI26Box alloc] init];
    pthread_t threads[WRITERS + READERS];
    Worker args[WRITERS + READERS];
    volatile int started = 0;
    int launched = 0;

    for (int i = 0; i < WRITERS + READERS; ++i) {
        args[i].box = box;
        args[i].role = (i < WRITERS) ? 1 : 0;
        args[i].index = i < WRITERS ? i : i - WRITERS;
        args[i].start = &started;
        int rc = pthread_create(&threads[i], NULL, worker_main, &args[i]);
        if (rc != 0) {
            fprintf(stderr, "ABI26_THREAD_CREATE_FAIL rc=%d\n", rc);
            __sync_add_and_fetch(&g_failed, 1);
            break;
        }
        ++launched;
    }
    __atomic_store_n(&started, 1, __ATOMIC_RELEASE);
    for (int i = 0; i < launched; ++i) pthread_join(threads[i], NULL);

    [box setRetained:nil];
    [box setCopied:nil];
    [box release];
    [main_pool drain];

    int made = g_created;
    int freed = g_destroyed;
    printf("ABI26_GUEST_WORKERS=%d/%d\n", launched, WRITERS + READERS);
    printf("ABI26_GUEST_CREATED=%d\n", made);
    printf("ABI26_GUEST_DEALLOCATED=%d\n", freed);
    printf("ABI26_GUEST_BAD_READS=%d\n", g_failed);
    printf("ABI26_GUEST_RETAIN_COPY_STRESS=%s\n",
           launched == WRITERS + READERS && g_failed == 0 && made == freed
           && made == WRITERS * ROUNDS * 2 ? "PASS" : "FAIL");
    puts("ABI26_CONCURRENT_COPY_DEALLOC=NOT_QUALIFIED");
    return (launched == WRITERS + READERS && g_failed == 0 && made == freed
            && made == WRITERS * ROUNDS * 2) ? 0 : 1;
}
