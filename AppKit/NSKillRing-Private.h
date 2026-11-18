/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <Foundation/NSString.h>

// The kill ring behind the text views' deleteToXXX/yank commands. Text
// engines outside AppKit use the same functions (the prototypes are those
// WebKit declares), so a kill in one place can be yanked in another.

NS_ASSUME_NONNULL_BEGIN

// Enables the ring; until this is called the other functions do nothing and
// the yank returns nil. Calling it again changes nothing.
extern void _NSInitializeKillRing(void);
// Appends to the current entry of the ring, or to a new one when the previous
// operation was a yank.
extern void _NSAppendToKillRing(NSString *text);
// Like _NSAppendToKillRing(), but puts the text in front of the entry.
extern void _NSPrependToKillRing(NSString *text);
// The next append goes to a new, empty entry.
extern void _NSNewKillRingSequence(void);
// Marks the last operation as a yank, so the next append starts a new entry.
extern void _NSSetKillRingToYankedState(void);
// The current entry (empty when nothing was killed); does not cycle.
extern NSString *_Nullable _NSYankFromKillRing(void);

NS_ASSUME_NONNULL_END
