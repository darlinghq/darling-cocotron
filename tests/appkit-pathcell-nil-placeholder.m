// Copyright (C) 2026 Lubos Dolezel
//
// NSPathCell placeholder string and placeholder attributed string. The documentation (macOS
// 10.5) declares placeholderString as an optional string (Swift String?) and
// placeholderAttributedString as an optional, copied attributed string
// (@NSCopying NSAttributedString?), and says the attributed string is drawn in place of the
// path components when there are none and it is not nil, else the plain string is drawn with
// default attributes when it is not nil. So nil is a valid value of both and means no
// placeholder, and it is the value of a cell decoded from an archive that has none.
// The documentation does not say how the two relate beyond that drawing precedence. On macOS
// 26.7.3 and 10.14.4 (x86_64 and i386; mac-probes/cristim/batch12a/p765.m, p765b.m) a cell has
// one placeholder, a string or an attributed string: setting either replaces what was there
// (nil clears it whichever kind it was) and each getter answers nil while the placeholder is
// of the other kind. A cell archive keeps it under the one key NSPlaceholderString, and it
// decodes back to the property it came from.
// Test: test_quirk_pathcell_has_one_placeholder (below)
// Build: clang -fobjc-arc -framework AppKit appkit-pathcell-nil-placeholder.m
// Needs a Darling guest; it does not start an NSApplication.
// On master the nil cases do not survive: -setPlaceholderString: passes nil to
// -[NSAttributedString initWithString:], which crashes (decoding an archive with no placeholder
// key crashes the same way inside -initWithCoder:). The non-nil cases pass on master and pin
// the behaviour that must not change.
// Not covered: drawing of the placeholder (nothing draws it yet).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// An application subclass whose setter wraps the superclass one.
@interface MyPathCell : NSPathCell
@end
@implementation MyPathCell
- (void)setPlaceholderString:(NSString *)string {
    (void)[self placeholderString];
    [super setPlaceholderString:string];
}
@end

// Stands in for the cell in a keyed archive: it writes the placeholder key only when
// standInPlaceholder is set, and no other key, as a nib without a placeholder does.
static id standInPlaceholder;
@interface ArchivedStandIn : NSObject <NSCoding>
@end
@implementation ArchivedStandIn
- (void)encodeWithCoder:(NSCoder *)coder {
    if (standInPlaceholder != nil)
        [coder encodeObject:standInPlaceholder forKey:@"NSPlaceholderString"];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static NSPathCell *decoded(id placeholder, Class cellClass) {
    standInPlaceholder = placeholder;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:[ArchivedStandIn new] forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [unarchiver setClass:cellClass forClassName:@"ArchivedStandIn"];
    return [unarchiver decodeObjectForKey:@"root"];
}

static void checkSetAndClear(NSPathCell *cell) {
    // an object that has no placeholder yet takes nil without raising, and still has none
    @try {
        [cell setPlaceholderString:nil];
    } @catch (NSException *exception) {
        fprintf(stderr, "FAIL line %d: -setPlaceholderString:nil raised %s\n", __LINE__,
                [[exception name] UTF8String]);
        failures++;
    }
    CHECK([cell placeholderString] == nil);

    [cell setPlaceholderString:@"Choose a folder"];
    CHECK([[cell placeholderString] isEqualToString:@"Choose a folder"]);

    // the empty string is a placeholder, not the absence of one
    [cell setPlaceholderString:@""];
    CHECK([cell placeholderString] != nil);
    CHECK([[cell placeholderString] length] == 0);

    // nil clears a placeholder that was set, and a cleared cell takes a new one
    [cell setPlaceholderString:@"Choose a folder"];
    [cell setPlaceholderString:nil];
    CHECK([cell placeholderString] == nil);
    [cell setPlaceholderString:@"Another"];
    CHECK([[cell placeholderString] isEqualToString:@"Another"]);
    [cell setPlaceholderString:nil];
    CHECK([cell placeholderString] == nil);

    // the attributed string: nil accepted, set, copied, cleared with nil
    @try {
        [cell setPlaceholderAttributedString:nil];
    } @catch (NSException *exception) {
        fprintf(stderr, "FAIL line %d: -setPlaceholderAttributedString:nil raised %s\n", __LINE__,
                [[exception name] UTF8String]);
        failures++;
    }
    CHECK([cell placeholderAttributedString] == nil);

    NSDictionary *attributes = @{NSForegroundColorAttributeName: [NSColor redColor]};
    NSMutableAttributedString *styled =
        [[NSMutableAttributedString alloc] initWithString:@"Styled" attributes:attributes];
    [cell setPlaceholderAttributedString:styled];
    CHECK([[cell placeholderAttributedString] isEqualToAttributedString:styled]);
    [styled appendAttributedString:[[NSAttributedString alloc] initWithString:@" more"]];
    CHECK([[[cell placeholderAttributedString] string] isEqualToString:@"Styled"]);   // @NSCopying

    [cell setPlaceholderAttributedString:nil];
    CHECK([cell placeholderAttributedString] == nil);
}

int main(void) {
    @autoreleasepool {
        CHECK([NSPathCell instancesRespondToSelector:@selector(placeholderString)]);
        CHECK([NSPathCell instancesRespondToSelector:@selector(setPlaceholderString:)]);
        CHECK([NSPathCell instancesRespondToSelector:@selector(placeholderAttributedString)]);
        CHECK([NSPathCell instancesRespondToSelector:@selector(setPlaceholderAttributedString:)]);

        NSPathCell *fresh = [[NSPathCell alloc] init];
        CHECK([fresh placeholderString] == nil);
        checkSetAndClear(fresh);

        MyPathCell *mine = [[MyPathCell alloc] init];
        CHECK([mine placeholderString] == nil);
        checkSetAndClear(mine);

        // a cell decoded from an archive with no placeholder key has none (the normal case)
        NSPathCell *fromArchive = decoded(nil, [NSPathCell class]);
        CHECK(fromArchive != nil);
        CHECK([fromArchive isKindOfClass:[NSPathCell class]]);
        CHECK([fromArchive placeholderString] == nil);
        checkSetAndClear(fromArchive);

        // the application subclass decodes the same way
        MyPathCell *mineFromArchive = (MyPathCell *)decoded(nil, [MyPathCell class]);
        CHECK([mineFromArchive isKindOfClass:[MyPathCell class]]);
        CHECK([mineFromArchive placeholderString] == nil);

        // a decoded placeholder is kept, and can be cleared
        NSPathCell *withKey = decoded(@"From the archive", [NSPathCell class]);
        CHECK([[withKey placeholderString] isEqualToString:@"From the archive"]);
        [withKey setPlaceholderString:nil];
        CHECK([withKey placeholderString] == nil);

        // an attributed placeholder in the archive decodes to the attributed property only
        NSPathCell *attributed = decoded([[NSAttributedString alloc] initWithString:@"Styled"], [NSPathCell class]);
        CHECK([[[attributed placeholderAttributedString] string] isEqualToString:@"Styled"]);
        CHECK([attributed placeholderString] == nil);

        // test_quirk_pathcell_has_one_placeholder (macOS 26.7.3 and 10.14.4)
        NSPathCell *both = [[NSPathCell alloc] init];
        NSAttributedString *styledText = [[NSAttributedString alloc] initWithString:@"Styled"];
        [both setPlaceholderString:@"Plain"];
        CHECK([both placeholderAttributedString] == nil);
        [both setPlaceholderAttributedString:styledText];
        CHECK([both placeholderString] == nil);
        CHECK([[[both placeholderAttributedString] string] isEqualToString:@"Styled"]);
        [both setPlaceholderString:@"Plain"];
        CHECK([[both placeholderString] isEqualToString:@"Plain"]);
        CHECK([both placeholderAttributedString] == nil);
        [both setPlaceholderAttributedString:nil];
        CHECK([both placeholderString] == nil);
        CHECK([both placeholderAttributedString] == nil);
        [both setPlaceholderAttributedString:styledText];
        [both setPlaceholderString:nil];
        CHECK([both placeholderString] == nil);
        CHECK([both placeholderAttributedString] == nil);
        // the plain string is copied, and the empty attributed string is a placeholder
        NSMutableString *changing = [NSMutableString stringWithString:@"Plain"];
        [both setPlaceholderString:changing];
        [changing appendString:@" more"];
        CHECK([[both placeholderString] isEqualToString:@"Plain"]);
        [both setPlaceholderAttributedString:[[NSAttributedString alloc] initWithString:@""]];
        CHECK([both placeholderString] == nil);
        CHECK([both placeholderAttributedString] != nil);

        // cells do not share the placeholder
        NSPathCell *first = [[NSPathCell alloc] init];
        NSPathCell *second = [[NSPathCell alloc] init];
        [first setPlaceholderString:@"One"];
        CHECK([second placeholderString] == nil);
        [second setPlaceholderString:@"Two"];
        [first setPlaceholderString:nil];
        CHECK([[second placeholderString] isEqualToString:@"Two"]);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
