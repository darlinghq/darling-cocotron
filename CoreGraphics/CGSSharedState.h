// Copyright (C) 2026 Lubos Dolezel
// The state the processes of the container share through a mapped file (two 32-bit words: the window id counter
// and the cursor scale), or NULL when the file cannot be used. Internal to CoreGraphics.
#include <stdatomic.h>
#include <stdint.h>

__attribute__((visibility("hidden"))) _Atomic uint32_t *_CGSSharedState(void);
