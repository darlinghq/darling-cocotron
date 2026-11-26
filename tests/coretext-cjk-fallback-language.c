/* Copyright (C) 2026 Lubos Dolezel */
/* The language a CJK fallback font is chosen for (a quirk; see
 * substituteLanguage in CoreText/CTFont.m). Observed on macOS 26.7.3 with
 * CTFontCreateForStringWithLanguage and Helvetica as the current font:
 * - Han text gets the Simplified Chinese face (PingFang SC) with no language
 *   and with a language that isn't Chinese, Japanese or Korean, and the face
 *   of the given language otherwise (PingFang TC for zh-Hant, Hiragino Sans
 *   for ja, Apple SD Gothic Neo for ko);
 * - kana gets the Japanese face even with zh-Hans, Hangul the Korean face even
 *   with ja.
 * Which face serves a language depends on the installed fonts (in Darling, on
 * the fontconfig configuration), so this checks which choices are the same and
 * which differ, not the faces' names. Where no language has a face of its own
 * (a fontconfig configuration without per-language rules), the choices can't
 * differ and the test is skipped: run it in Darling through
 * coretext-cjk-fallback-language.sh, which supplies such rules. */
#include <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>

static int failures;

static CFStringRef fallbackName(const UniChar *text, CFIndex length, const char *language)
{
    CTFontRef base = CTFontCreateWithName(CFSTR("Helvetica"), 16, NULL);
    CFStringRef string = CFStringCreateWithCharacters(NULL, text, length);
    CFStringRef lang = language ? CFStringCreateWithCString(NULL, language, kCFStringEncodingUTF8) : NULL;
    CTFontRef font = CTFontCreateForStringWithLanguage(base, string, CFRangeMake(0, length), lang);
    CFStringRef name = font ? CTFontCopyPostScriptName(font) : CFStringCreateCopy(NULL, CFSTR("(none)"));
    if (font)
        CFRelease(font);
    if (lang)
        CFRelease(lang);
    CFRelease(string);
    CFRelease(base);
    return name;
}

static void compare(const char *what, CFStringRef a, CFStringRef b, int expectSame)
{
    char an[128], bn[128];
    CFStringGetCString(a, an, sizeof(an), kCFStringEncodingUTF8);
    CFStringGetCString(b, bn, sizeof(bn), kCFStringEncodingUTF8);
    int ok = strcmp(an, "(none)") != 0 && (strcmp(an, bn) == 0) == expectSame;
    printf("%s: %s (%s, %s)\n", ok ? "PASS" : "FAIL", what, an, bn);
    if (!ok)
        failures++;
    CFRelease(a);
    CFRelease(b);
}

static void same(const char *what, CFStringRef a, CFStringRef b) { compare(what, a, b, 1); }
static void differ(const char *what, CFStringRef a, CFStringRef b) { compare(what, a, b, 0); }

int main(void)
{
    static const UniChar han[] = { 0x4E2D, 0x6587 }, kana[] = { 0x3072, 0x3089 }, hangul[] = { 0xD55C, 0xAE00 };

    CFStringRef korean = fallbackName(han, 2, "ko"), chinese = fallbackName(han, 2, "zh-Hans");
    int distinct = CFStringCompare(korean, chinese, 0) != kCFCompareEqualTo;
    CFRelease(korean);
    CFRelease(chinese);
    if (!distinct) {
        printf("SKIP: Chinese and Korean text get the same face (no language-specific faces)\n");
        return 0;
    }

    differ("Han text without a language is not set as Korean", fallbackName(han, 2, NULL), fallbackName(han, 2, "ko"));
    differ("Han text without a language is not set as Japanese", fallbackName(han, 2, NULL), fallbackName(han, 2, "ja"));
    differ("Kana in Chinese is not set as Chinese", fallbackName(kana, 2, "zh-Hans"), fallbackName(han, 2, "zh-Hans"));
    differ("Hangul in Japanese is not set as Japanese", fallbackName(hangul, 2, "ja"), fallbackName(han, 2, "ja"));
    same("Han text without a language is set as Simplified Chinese", fallbackName(han, 2, NULL), fallbackName(han, 2, "zh-Hans"));
    same("Han text in English is set as Simplified Chinese", fallbackName(han, 2, "en"), fallbackName(han, 2, "zh-Hans"));
    same("zh-CN is Simplified Chinese", fallbackName(han, 2, "zh-CN"), fallbackName(han, 2, "zh-Hans"));
    same("zh-TW is Traditional Chinese", fallbackName(han, 2, "zh-TW"), fallbackName(han, 2, "zh-Hant"));
    same("Han text in Japanese gets the face of kana", fallbackName(han, 2, "ja"), fallbackName(kana, 2, NULL));
    same("Han text in Korean gets the face of Hangul", fallbackName(han, 2, "ko"), fallbackName(hangul, 2, NULL));
    same("kana is set as Japanese even in Chinese", fallbackName(kana, 2, "zh-Hans"), fallbackName(kana, 2, "ja"));
    same("Hangul is set as Korean even in Japanese", fallbackName(hangul, 2, "ja"), fallbackName(hangul, 2, "ko"));

    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
