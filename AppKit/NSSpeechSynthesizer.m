/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

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

#import <AppKit/NSSpeechSynthesizer.h>
#import <Foundation/NSArray.h>

NSVoiceGenderName const NSVoiceGenderFemale = @"VoiceGenderFemale";
NSVoiceGenderName const NSVoiceGenderMale = @"VoiceGenderMale";

NSVoiceAttributeKey const NSVoiceName = @"VoiceName";
NSVoiceAttributeKey const NSVoiceGender = @"VoiceGender";
NSVoiceAttributeKey const NSVoiceLocaleIdentifier = @"VoiceLocaleIdentifier";

NSSpeechPropertyKey const NSSpeechRateProperty = @"rate";
NSSpeechPropertyKey const NSSpeechPitchBaseProperty = @"pbas";
NSSpeechPropertyKey const NSSpeechVolumeProperty = @"volm";

@implementation NSSpeechSynthesizer

// There is no speech synthesizer, so there are no voices.

+ (NSArray<NSString *> *) availableVoices {
    return [NSArray array];
}

+ (NSString *) defaultVoice {
    return nil;
}

+ (NSDictionary<NSVoiceAttributeKey, id> *) attributesForVoice: (NSString *) voice {
    return nil;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
