// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: NSGestureRecognizer's delays, touch type, name and pressure
// configuration properties, the prevention and failure-requirement methods,
// and how the properties are archived. The SDK header documents the base
// class defaults and that subclasses have their own; the values and archive
// keys below were observed on macOS 26.7.3 (x86_64) with the same calls.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

static unsigned delays(NSGestureRecognizer *g)
{
    return (g.delaysPrimaryMouseButtonEvents << 0) | (g.delaysSecondaryMouseButtonEvents << 1) |
           (g.delaysOtherMouseButtonEvents << 2) | (g.delaysKeyEvents << 3) |
           (g.delaysMagnificationEvents << 4) | (g.delaysRotationEvents << 5);
}

static NSData *archive(id object)
{
    NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initRequiringSecureCoding: NO] autorelease];
    [archiver encodeObject: object forKey: @"root"];
    [archiver finishEncoding];
    return [archiver encodedData];
}

// The keys the recognizer wrote for itself, without $class.
static NSDictionary *archivedKeys(id object)
{
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData: archive(object) options: 0 format: NULL error: NULL];
    NSMutableDictionary *keys = [[[plist[@"$objects"] objectAtIndex: 1] mutableCopy] autorelease];
    [keys removeObjectForKey: @"$class"];
    return keys;
}

static id unarchive(NSData *data)
{
    NSKeyedUnarchiver *unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingFromData: data error: NULL] autorelease];
    unarchiver.requiresSecureCoding = NO;
    return [unarchiver decodeObjectForKey: @"root"];
}

int main(void)
{
    @autoreleasepool {
        struct { NSString *name; unsigned delays; } defaults[] = {
            { @"NSGestureRecognizer", 0 },
            { @"NSClickGestureRecognizer", 1 << 0 },
            { @"NSPanGestureRecognizer", 1 << 0 },
            { @"NSPressGestureRecognizer", 1 << 0 },
            { @"NSMagnificationGestureRecognizer", 1 << 4 },
            { @"NSRotationGestureRecognizer", 1 << 5 },
            { @"NSImmediateActionGestureRecognizer", 1 << 0 },
        };
        for (size_t i = 0; i < sizeof(defaults) / sizeof(defaults[0]); i++) {
            Class cls = NSClassFromString(defaults[i].name);
            NSGestureRecognizer *a = [[[cls alloc] initWithTarget: nil action: NULL] autorelease];
            NSGestureRecognizer *b = [[[cls alloc] init] autorelease];
            char name[128];
            snprintf(name, sizeof(name), "%s delays by default", defaults[i].name.UTF8String);
            report(name, delays(a) == defaults[i].delays && delays(b) == defaults[i].delays);
        }

        NSGestureRecognizer *g = [[[NSGestureRecognizer alloc] initWithTarget: nil action: NULL] autorelease];
        NSGestureRecognizer *other = [[[NSGestureRecognizer alloc] initWithTarget: nil action: NULL] autorelease];
        report("no allowed touch types by default", g.allowedTouchTypes == 0);
        report("no name by default", g.name == nil);
        report("no pressure configuration by default", g.pressureConfiguration == nil);
        report("no modifier flags before any event", g.modifierFlags == 0);
        report("can prevent and be prevented", [g canPreventGestureRecognizer: other] && [g canBePreventedByGestureRecognizer: other]);
        report("no failure requirements",
               ![g shouldRequireFailureOfGestureRecognizer: other] && ![g shouldBeRequiredToFailByGestureRecognizer: other]);

        g.delaysSecondaryMouseButtonEvents = YES;
        g.delaysKeyEvents = YES;
        report("delays setters", delays(g) == ((1 << 1) | (1 << 3)));
        g.delaysKeyEvents = NO;
        report("delays setter clears", delays(g) == (1 << 1));
        g.allowedTouchTypes = NSTouchTypeMaskDirect;
        report("allowed touch types setter", g.allowedTouchTypes == NSTouchTypeMaskDirect);
        NSMutableString *name = [NSMutableString stringWithString: @"pan"];
        g.name = name;
        [name appendString: @"ned"];
        report("name is copied", [g.name isEqualToString: @"pan"]);
        NSPressureConfiguration *pressure = [[[NSPressureConfiguration alloc] initWithPressureBehavior: NSPressureBehaviorPrimaryDeepClick] autorelease];
        g.pressureConfiguration = pressure;
        report("pressure configuration is kept", g.pressureConfiguration == pressure);
        report("pressure configuration's behavior", pressure.pressureBehavior == NSPressureBehaviorPrimaryDeepClick);
        report("pressure configuration's default behavior",
               [[[[NSPressureConfiguration alloc] init] autorelease] pressureBehavior] == NSPressureBehaviorPrimaryDefault);

        report("archive of a default recognizer is empty", [archivedKeys(other) count] == 0);
        NSDictionary *keys = archivedKeys(g);
        report("archive keys", [keys isEqual: (@{
            @"NSGestureRecognizer.delaysSecondaryMouseButtonEvents": @YES,
            @"NSGestureRecognizer.allowedTouchTypes": @(NSTouchTypeMaskDirect),
        })]);
        g.enabled = NO;
        report("disabled is archived", [archivedKeys(g)[@"NSGestureRecognizer.disabled"] isEqual: @YES]);

        NSGestureRecognizer *copy = unarchive(archive(g));
        report("unarchived delays", delays(copy) == (1 << 1));
        report("unarchived allowed touch types", copy.allowedTouchTypes == NSTouchTypeMaskDirect);
        report("unarchived disabled", !copy.enabled);
        report("name and pressure configuration aren't archived", copy.name == nil && copy.pressureConfiguration == nil);

        NSClickGestureRecognizer *click = [[[NSClickGestureRecognizer alloc] initWithTarget: nil action: NULL] autorelease];
        click.delaysPrimaryMouseButtonEvents = NO;
        report("unarchiving keeps a cleared subclass default", ![unarchive(archive(click)) delaysPrimaryMouseButtonEvents]);

        NSView *view = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
        NSGestureRecognizer *targeted = [[[NSGestureRecognizer alloc] initWithTarget: view action: @selector(display)] autorelease];
        NSKeyedArchiver *archiver = [[[NSKeyedArchiver alloc] initRequiringSecureCoding: NO] autorelease];
        [archiver encodeObject: view forKey: @"view"];
        [archiver encodeObject: targeted forKey: @"root"];
        [archiver finishEncoding];
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData: [archiver encodedData] options: 0 format: NULL error: NULL];
        NSDictionary *targetedKeys = nil;
        for (id object in plist[@"$objects"])
            if ([object isKindOfClass: [NSDictionary class]] && object[@"NSGestureRecognizer.action"])
                targetedKeys = object;
        report("target and action keys", targetedKeys[@"NSGestureRecognizer.target"] != nil);
        NSKeyedUnarchiver *unarchiver = [[[NSKeyedUnarchiver alloc] initForReadingFromData: [archiver encodedData] error: NULL] autorelease];
        unarchiver.requiresSecureCoding = NO;
        NSView *decodedView = [unarchiver decodeObjectForKey: @"view"];
        NSGestureRecognizer *decoded = [unarchiver decodeObjectForKey: @"root"];
        report("unarchived target and action", decoded.target == decodedView && decoded.action == @selector(display));
    }
    return failures != 0;
}
