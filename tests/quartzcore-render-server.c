// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: QuartzCore's render server functions.
// - CABackingStoreCollectBlocking returns.
// - CARenderServerGetServerPort gives MACH_PORT_NULL for the name of a server
//   that does not exist (observed on macOS 26.7.3, x86_64), and the same port
//   on each call for the default server (NULL), which is MACH_PORT_NULL in
//   Darling, where there is no render server.
#include <mach/mach.h>
#include <stdio.h>

extern void CABackingStoreCollectBlocking(void);
extern mach_port_t CARenderServerGetServerPort(const char *name);

static int failures;

static void report(const char *name, int ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

int main(void)
{
    CABackingStoreCollectBlocking();
    report("CABackingStoreCollectBlocking returns", 1);
    report("no such server", CARenderServerGetServerPort("com.example.no-such-render-server") == MACH_PORT_NULL);
    report("default server: the same port each time", CARenderServerGetServerPort(NULL) == CARenderServerGetServerPort(NULL));
    return failures != 0;
}
