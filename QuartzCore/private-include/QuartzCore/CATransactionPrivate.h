/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Developers

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

#import <QuartzCore/CATransaction.h>

// Commit handlers are not part of the public SDK. Applications that use them
// (WebKit, Chromium) declare the method and the phases themselves.

typedef NS_ENUM(unsigned int, CATransactionPhase) {
    kCATransactionPhasePreLayout,
    kCATransactionPhasePreCommit,
    kCATransactionPhasePostCommit,
};

@interface CATransaction ()

// Runs the handler once, in the given phase of the commit of the current
// thread's outermost transaction. With no transaction open, an implicit
// one is started. A handler added for a phase that the commit in progress
// has already passed runs in the next commit.
+ (void) addCommitHandler: (void (^)(void)) handler
                 forPhase: (CATransactionPhase) phase;

@end
