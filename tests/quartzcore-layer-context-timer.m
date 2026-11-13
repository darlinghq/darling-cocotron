/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CALayerContext frame timer: render requests made while a frame is being
 * drawn are kept and produce exactly one further frame, an idle context stops
 * its timer, -invalidate cancels the timer (also from inside a frame) and is
 * repeatable, and a cancelled context can be started again.
 *
 * -render and -flush are overridden to count frames; the timer, the request
 * bookkeeping and -invalidate are the real ones. Needs CGL (a display
 * server, Xvfb is enough).
 */
#import <Foundation/Foundation.h>
#import <QuartzCore/CALayerContext.h>
#include <stdio.h>

static unsigned frames, requestedFrames;
static BOOL cancelInFrame;

@interface CountingContext : CALayerContext
@end

@implementation CountingContext
- (void) render {
	++frames;
	if (cancelInFrame && frames == 1)
		[self invalidate];
	// A delegate asks for another frame after the current one began; many
	// requests in one frame must coalesce into a single further frame.
	if (frames < requestedFrames)
		for (unsigned i = 0; i < 10; ++i)
			[self startTimerIfNeeded];
}
- (void) flush {
}
@end

static int failures;

static void expectFrames(unsigned expected, const char *what) {
	if (frames != expected) {
		fprintf(stderr, "FAIL: %s: %u frames, expected %u\n", what, frames, expected);
		failures++;
	}
}

static void spin(NSTimeInterval seconds) {
	[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

int main(void) {
	@autoreleasepool {
		for (requestedFrames = 1; requestedFrames <= 3; ++requestedFrames) {
			frames = 0;
			CountingContext *c = [[CountingContext alloc] initWithFrame: CGRectMake(0, 0, 16, 16)];
			if (c == nil) {
				fprintf(stderr, "SKIP: no CGL context\n");
				return 0;
			}
			[c startTimerIfNeeded];
			spin(0.3);
			expectFrames(requestedFrames, "requests made during a frame are kept and coalesced");
			[c release];
		}

		// Idle stopping: no further frames once nothing is requested.
		frames = 0;
		requestedFrames = 1;
		CountingContext *idle = [[CountingContext alloc] initWithFrame: CGRectMake(0, 0, 16, 16)];
		[idle startTimerIfNeeded];
		spin(0.2);
		unsigned afterFirst = frames;
		spin(0.2);
		expectFrames(afterFirst, "an idle context renders nothing more");
		[idle release];

		// Cancelling from inside the frame, with and without a replacement
		// request made by the same frame.
		cancelInFrame = YES;
		for (requestedFrames = 1; requestedFrames <= 2; ++requestedFrames) {
			frames = 0;
			CountingContext *c = [[CountingContext alloc] initWithFrame: CGRectMake(0, 0, 16, 16)];
			[c startTimerIfNeeded];
			spin(0.3);
			expectFrames(requestedFrames, "invalidate inside a frame, with a replacement request only if asked");
			[c release];
		}
		cancelInFrame = NO;

		// Repeated invalidation, no callbacks afterwards, restart works.
		frames = 0;
		requestedFrames = 1;
		CountingContext *c = [[CountingContext alloc] initWithFrame: CGRectMake(0, 0, 16, 16)];
		[c invalidate];
		[c startTimerIfNeeded];
		[c invalidate];
		[c invalidate];
		spin(0.1);
		expectFrames(0, "no frame after invalidate");
		[c startTimerIfNeeded];
		spin(0.2);
		expectFrames(1, "restart after invalidate renders a frame");
		[c release];
	}
	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
