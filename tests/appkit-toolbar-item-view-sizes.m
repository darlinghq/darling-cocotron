// Copyright (C) 2026 Lubos Dolezel
//
// The size of a toolbar item that has a view. Observed black-box on macOS 26.7.3 (x86_64):
//  - an item with a view and no minimum and maximum size of its own reports the view's intrinsic content size as
//    both -minSize and -maxSize (the view's frame in a dimension without an intrinsic size), and the view is that
//    size in the toolbar;
//  - an item with explicit sizes keeps them: a 35 point wide pop-up button stays about that wide however long its
//    title is;
//  - the size follows the view while it has none of its own: the item of a pop-up button that selects a longer
//    title is as wide as the button asks for;
//  - a nib's item that has the "ignore minimum and maximum size" flag set (NSToolbarItemIgnoreMinMaxSizes) is
//    sized like the first kind although the nib also stores a size, and one without the flag like the second.
// The nibs were compiled by ibtool from a window with a toolbar of two pop-up button items whose nib sizes are
// 35 x 25 (the second variant has the flag set); an item laid out with autoresizing and one with constraints.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s: ", __LINE__, #c); fprintf(stderr, __VA_ARGS__); fputc(10, stderr); failures++; } } while (0)

static NSString *nibWithSizes =
    @"TklCQXJjaGl2ZQEAAAAKAAAAUgAAADIAAACCAAAAYgEAAH4BAACzCgAAFQAAAGsSAACAgIKBgoqCjIKDjoOEkYGFkoKGlI6EooGE"
    @"o4GEpIGEpYGHpoyEsoGIs4WEuIGJuZSEzYGKzpSE4oGL45WM+IOE+4GN/IKO/oOPAYGMhA2BgZAOgYWEE4GBhBSBgZEVgYKEF4GB"
    @"kBiBhYQdgYGRHoGChCCBgYQhgYGPIoGMhC6BgYQvgYGEMIGBiTGBlIRFgYGKRoGUi1qBlY1vgYKOcYGDj3SBjI8AgoySDIKDkg+C"
    @"g44SgoGTE4KIhBuCgYQcgoGEHYKBjh6CgZIfgpGCMIKCgzKCg4Q1goGSNoKRkkeCkpJZgpKUa4KBlGyCgZRtgoGUboKBlG+CgZRw"
    @"goGUcYKBlHKCgZRzgoGUdIKBlHWCgZR2goGUd4KBlHiCgZR5goGUeoKBlHuCgY58goGSfYKBk05TVG9vbGJhcklkZW50aWZpZXKK"
    @"TlNLZXlFcXVpdoxOU1dpbmRvd1JlY3SKTlNPaWRzS2V5c5lOU1Rvb2xiYXJJdGVtTmF2aWdhdGlvbmFsk05TQ29udHJvbENvbnRp"
    @"bnVvdXOTTlNBbHRlcm5hdGVDb250ZW50c41OU0NvbnRyb2xTaXplkU5TVG9vbGJhclNpemVNb2RlkE5TVG9vbGJhckl0ZW1UYWeS"
    @"TlNVc2VzSXRlbUZyb21NZW51iU5TU3VwcG9ydJpJQi5zeXN0ZW1Gb250VXBkYXRlVmVyc2lvbo1OU01uZW1vbmljTG9jmE5TSGlk"
    @"ZGVuSW5SZXByZXNlbnRhdGlvbplOU0NvbnRyb2xXcml0aW5nRGlyZWN0aW9unU5TVXNlckludGVyZmFjZUl0ZW1JZGVudGlmaWVy"
    @"jU5TQWx0ZXJzU3RhdGWTTlNUb29sYmFySXRlbVRhcmdldJROU1Rvb2xiYXJJdGVtTWluU2l6ZYtOU0NlbGxGbGFnc5FOU0tleUVx"
    @"dWl2TW9kTWFza4tOU01lbnVJdGVtc5pOU01lbnVJdGVtUmVzcGVjdEFsaWdubWVudIxOU1dpbmRvd1ZpZXeeTlNUb29sYmFySXRl"
    @"bUlnbm9yZU1pbk1heFNpemVzik5TLnNpemV2YWyUVUlOaWJFbmNvZGVyRW1wdHlLZXmZTlNUb29sYmFyUHJlZmVyc1RvQmVTaG93"
    @"bp9JQk5TU2hhZG93ZWRTeW1ib2xDb25maWd1cmF0aW9uiE5TQWN0aW9ulU5TVG9vbGJhckl0ZW1Cb3JkZXJlZJFJQk5TQ2xpcHNU"
    @"b0JvdW5kc49OU1NlbGVjdGVkSW5kZXiaTlNUb29sYmFySXRlbUF1dG92YWxpZGF0ZXONTlNXaW5kb3dUaXRsZZROU1Rvb2xiYXJE"
    @"aXNwbGF5TW9kZZBOU1Zpc2libGVXaW5kb3dzjU5TTmliVG91Y2hCYXKZTlNUb29sYmFySXRlbVBhbGV0dGVMYWJlbJROU1Rvb2xi"
    @"YXJJdGVtTWF4U2l6ZZZOU0NvbnRyb2xUZXh0QWxpZ25tZW50jU5TT2JqZWN0c0tleXOaSUJEZXNpZ25JbWFnZUNvbmZpZ3VyYXRp"
    @"b26bTlNDb250cm9sVXNlc1NpbmdsZUxpbmVNb2Rlmk5TVG9vbGJhcklCSWRlbnRpZmllZEl0ZW1zl05TVG9vbGJhcklCQWxsb3dl"
    @"ZEl0ZW1zkE5TV2luZG93U3VidGl0bGWOTlNSZXNvdXJjZU5hbWWHTlNGcmFtZYhOU1RhcmdldIZOU05hbWWRTlNXaW5kb3dTdHls"
    @"ZU1hc2uJTlNPbkltYWdll0lCTlNTYWZlQXJlYUxheW91dEd1aWRlj05TUHJlZmVycmVkRWRnZYxOU1NjcmVlblJlY3SSTlNUb29s"
    @"YmFySXRlbUxhYmVskU5TVG9vbGJhckRlbGVnYXRli05TVmlld0NsYXNzlklCTlNMYXlvdXRNYXJnaW5zR3VpZGWSTlNUb29sYmFy"
    @"SXRlbUltYWdlhk5TTWVudY5OU0lubGluZWRWYWx1ZZhOU1Rvb2xiYXJJc1VzZXJSZW1vdmFibGWNTlNCdXR0b25GbGFnc41OU0Nv"
    @"bnRyb2xWaWV3i05TQ2xhc3NOYW1ljElCTW9kdWxlTmFtZaZOU1ZpZXdXYW50c0Jlc3RSZXNvbHV0aW9uT3BlbkdMU3VyZmFjZZpO"
    @"U1Rvb2xiYXJJQlNlbGVjdGFibGVJdGVtc5dOU0FjY2Vzc2liaWxpdHlPaWRzS2V5c59OU1Rvb2xiYXJJdGVtVmlzaWJpbGl0eVBy"
    @"aW9yaXR5iE5TdkZsYWdzkk5TVG9vbGJhckl0ZW1UaXRsZZROU1dpbmRvd0lzUmVzdG9yYWJsZZJOU1Rvb2xiYXJJdGVtU3R5bGWP"
    @"TlNLZXlFcXVpdmFsZW50kElCTW9kdWxlUHJvdmlkZXKMTlNPaWRzVmFsdWVzj05TUGVyaW9kaWNEZWxheY5OU0J1dHRvbkZsYWdz"
    @"Mp5OU0NvbnRyb2xSZWZ1c2VzRmlyc3RSZXNwb25kZXKgTlNUb29sYmFyQWxsb3dzVXNlckN1c3RvbWl6YXRpb26GTlNDZWxshk5T"
    @"Um9vdIhOUy5ieXRlc5lOU0FjY2Vzc2liaWxpdHlPaWRzVmFsdWVzjE5TQmV6ZWxTdHlsZZROU1Rvb2xiYXJJdGVtVG9vbFRpcJRO"
    @"U1Rvb2xiYXJJdGVtRW5hYmxlZIdOU1RpdGxliE5TZkZsYWdzik5TQ29udGVudHOPTlNBdXhCdXR0b25UeXBliU5TV1RGbGFnc59O"
    @"U1Rvb2xiYXJBdXRvc2F2ZXNDb25maWd1cmF0aW9unk5TQWxsb3dzTG9naWNhbExheW91dERpcmVjdGlvboxOU01peGVkSW1hZ2WS"
    @"TlNQZXJpb2RpY0ludGVydmFshk5TU2l6ZY9OU05leHRSZXNwb25kZXKMTlNDZWxsRmxhZ3MyiU5TRW5hYmxlZJpOU01pbkZ1bGxT"
    @"Y3JlZW5Db250ZW50U2l6ZZ5OU0FsbG93c0tleUVxdWl2YWxlbnRNaXJyb3JpbmeWTlNDb250cm9sTGluZUJyZWFrTW9kZY1JQk5h"
    @"bWVzcGFjZUlEi05TRnJhbWVTaXplik5TTWVudUl0ZW2LSUJDbGFzc05hbWWMSUJEZXNpZ25TaXpll05TVG9vbGJhcklCRGVmYXVs"
    @"dEl0ZW1zjUlCLm9iamVjdGRhdGGRTlNUb29sYmFySXRlbVZpZXeZTlNBY2Nlc3NpYmlsaXR5Q29ubmVjdG9yc59OU1Rvb2xiYXJD"
    @"ZW50ZXJlZEl0ZW1JZGVudGlmaWVyl05TVG9vbGJhckl0ZW1JZGVudGlmaWVyik5TLnNwZWNpYWyQSUJDbGFzc1JlZmVyZW5jZY1O"
    @"U0Nvbm5lY3Rpb25zj05TV2luZG93QmFja2luZ49OU09iamVjdHNWYWx1ZXOhTlNBbGxvd3NLZXlFcXVpdmFsZW50TG9jYWxpemF0"
    @"aW9uk05TVG9vbGJhckl0ZW1BY3Rpb26aTlNNYXhGdWxsU2NyZWVuQ29udGVudFNpemWNTlNXaW5kb3dDbGFzc49OU0Fycm93UG9z"
    @"aXRpb26JTlMuaW50dmFsl05TQ29udHJvbFNlbmRBY3Rpb25NYXNr8QoBAAAAjAAB1QoCAAAApQoFAAAA+Ao3AAAAqgo4AAAA+go8"
    @"AAAAgwo9AAAAzwo+AAAA8wpQAAAAxwpRAAAA1wpRAAAA9woDAAAAwwoEAAAA7goEAAAAxAnOCdYIiE5TT2JqZWN0vwWbCgYAAAC0"
    @"AAP5AAKCCgcAAADfAgAAeGCjCggAAACvCgkAAAD+CgoAAAC7CgsAAACQCZgKMwAAALgKNQAAAMsF6Ao2AAAA/Qo2AAAA1giYe3s3"
    @"MjAsIDQwNX0sIHs0ODAsIDI3MH191giBV9YIgNYIiE5TV2luZG93gAoMAAAAugmcBdMF4ASkAAGIAAH0Ca0KDQAAAK4KMAAAAPAK"
    @"MQAAAMYKMgAAANYIglRCvwWbCg4AAACbCg8AAACbCicAAACbCigAAADWCIVJVEVNMfUKDgAAALkKEAAAAKcKEAAAANkJ8goRAAAA"
    @"nwW9CcoKCQAAAJIJ/AmTCiYAAACoCiYAAACZBNoFogWJAADIAACEBMAFzAAA1giGT3V0cHV05QmmCckBDAGxChIAAADFBbYJvAmg"
    @"AADnBdQKEwAAAOEEhwAAhQTSBKwEqQAE6gAEjwP//////////wGBAASdCdYIk3t7MCwgMTR9LCB7MzUsIDI1fX2UAkAAAATmAgAI"
    @"ABDdCgkAAACLChQAAADCChEAAADBAwBAgIb/////0QGjANgAC4YKCQAAAM0KCQAAANABkAHjAEveAAftCZcFvgoWAAAAoQP/////"
    @"/////7cAAYoFkQX/AAKzChUAAADkBwAAAAAAACpA3AEWBtYIki5BcHBsZVN5c3RlbVVJRm9udNsKCQAAAJYKFwAAAL8FmwoYAAAA"
    @"mwokAAAAvgoWAAAA+wXpBdsKGQAAAIEKCQAAAJUCAAAQAI0C////f7UKGgAAAOIKHwAAAJ4KIwAAALIKEwAAAI4E1giHRGVmYXVs"
    @"dMMKGwAAALAKHAAAAOsJ7wodAAAAqwnWCIdOU0ltYWdl1giPTlNNZW51Q2hlY2ttYXJr9gACmgoeAAAA1giIezE4LCAxNn3DChsA"
    @"AACwCiAAAADrCe8KIQAAAKsJ1giQTlNNZW51TWl4ZWRTdGF0ZfYAApoKIgAAANYIh3sxOCwgNH3WCJFfcG9wVXBJdGVtQWN0aW9u"
    @"Or4KFgAAAPsF6QXbCiUAAACBCgkAAACVAgAAEACNAv///3+1ChoAAADiCh8AAACeCiMAAACyChMAAACOBNYInEEgbG9uZyBpdGVt"
    @"IHRpdGxlIHRvIGJlIHdpZGXWCIh7MzUsIDI1fdYIhUlURU0y9QonAAAAuQopAAAApwopAAAA2QnyCioAAACfBb0JygoJAAAAkgn8"
    @"CZMKJgAAAKgKJgAAAJkE2gWiBYkAAMgAAIQEwAXMAADWCIVPcmRlcuUJpgnJAQwBsQoSAAAAxQW2CbwJoAAA5wXUCisAAADhBIcA"
    @"AIUE0gSsBKkABOoABI8D//////////8BgQAEnQmUAkAAAATmAgAIABDdCgkAAACLChQAAADCCioAAADBAwBAgIb/////0QGjANgA"
    @"C4YKCQAAAM0KCQAAANABkAHjAEveAAftCZcFvgosAAAAoQP//////////7cAAYoFkQX/AALbCgkAAACWCi0AAAC/BZsKLgAAAJsK"
    @"LwAAAL4KLAAAAPsF6QXbChkAAACBCgkAAACVAgAAEACNAv///3+1ChoAAADiCh8AAACeCiMAAACyCisAAACOBL4KLAAAAPsF6QXb"
    @"CiUAAACBCgkAAACVAgAAEACNAv///3+1ChoAAADiCh8AAACeCiMAAACyCisAAACOBL8FmwoPAAAAmwooAAAAvwWbCg8AAACbCigA"
    @"AAC/BeUJpgnJAQAB7Ao0AAAAxQW2CbwJoAAA1giKezQ4MCwgMjcwfdYIlnt7MCwgMH0sIHsxOTIwLCAxMDgwfX3WCIZ7MCwgMH2/"
    @"Bb8Fmwo5AAAAmwoGAAAAmwozAAAAmwoLAAAAmwoPAAAAmwoRAAAAmwoTAAAAmwoWAAAAmwoYAAAAmwokAAAAmwooAAAAmwoqAAAA"
    @"mworAAAAmwosAAAAmwouAAAAmwovAAAA9wo6AAAAwwo7AAAA7goEAAAAxAnOCdYIjU5TQXBwbGljYXRpb26/BZsKAgAAAJsKAgAA"
    @"AJsKBgAAAJsKBgAAAJsKCwAAAJsKDwAAAJsKEQAAAJsKEwAAAJsKFgAAAJsKFgAAAJsKCwAAAJsKKAAAAJsKKgAAAJsKKwAAAJsK"
    @"LAAAAJsKLAAAAL8FmwoCAAAAmwo5AAAAmwoGAAAAmwozAAAAmwoLAAAAmwoPAAAAmwoRAAAAmwoTAAAAmwoWAAAAmwoYAAAAmwok"
    @"AAAAmwooAAAAmwoqAAAAmworAAAAmwosAAAAmwouAAAAmwovAAAAvwWbCj8AAACbCkAAAACbCkEAAACbCkIAAACbCkMAAACbCkQA"
    @"AACbCkUAAACbCkYAAACbCkcAAACbCkgAAACbCkkAAACbCkoAAACbCksAAACbCkwAAACbCk0AAACbCk4AAACbCk8AAAAAgQABAIEA"
    @"AgCBAAMAgQAEAIEABQCBAAYAgQAHAIEACACBAAkAgQAKAIEACwCBAAwAgQANAIEADgCBAA8AgQAQAIEAEb8FvwWJgE5TT2JqZWN0"
    @"AI+ATlNJQk9iamVjdERhdGEAj4BOU0N1c3RvbU9iamVjdACRgElCQ2xhc3NSZWZlcmVuY2UAiYBOU1N0cmluZwCNgE5TTXV0YWJs"
    @"ZVNldACRgE5TV2luZG93VGVtcGxhdGUAioBOU1Rvb2xiYXIAlIBOU011dGFibGVEaWN0aW9uYXJ5AI6ATlNUb29sYmFySXRlbQCO"
    @"gE5TUG9wVXBCdXR0b24AkoBOU1BvcFVwQnV0dG9uQ2VsbACHgE5TRm9udACHgE5TTWVudQCPgE5TTXV0YWJsZUFycmF5AIuATlNN"
    @"ZW51SXRlbQCRgE5TQ3VzdG9tUmVzb3VyY2UAiIBOU1ZhbHVlAIiATlNBcnJheQCHgE5TVmlldwCJgE5TTnVtYmVyAA==";

static NSString *nibIgnoringSizes =
    @"TklCQXJjaGl2ZQEAAAAKAAAAUgAAADIAAACCAAAAYgEAAH4BAACzCgAAFQAAAGsSAACAgIKBgoqCjIKDjoOEkYGFkoKGlI6EooGE"
    @"o4GEpIGEpYGHpoyEsoGIs4WEuIGJuZSEzYGKzpSE4oGL45WM+IOE+4GN/IKO/oOPAYGMhA2BgZAOgYWEE4GBhBSBgZEVgYKEF4GB"
    @"kBiBhYQdgYGRHoGChCCBgYQhgYGPIoGMhC6BgYQvgYGEMIGBiTGBlIRFgYGKRoGUi1qBlY1vgYKOcYGDj3SBjI8AgoySDIKDkg+C"
    @"g44SgoGTE4KIhBuCgYQcgoGEHYKBjh6CgZIfgpGCMIKCgzKCg4Q1goGSNoKRkkeCkpJZgpKUa4KBlGyCgZRtgoGUboKBlG+CgZRw"
    @"goGUcYKBlHKCgZRzgoGUdIKBlHWCgZR2goGUd4KBlHiCgZR5goGUeoKBlHuCgY58goGSfYKBk05TVG9vbGJhcklkZW50aWZpZXKK"
    @"TlNLZXlFcXVpdoxOU1dpbmRvd1JlY3SKTlNPaWRzS2V5c5lOU1Rvb2xiYXJJdGVtTmF2aWdhdGlvbmFsk05TQ29udHJvbENvbnRp"
    @"bnVvdXOTTlNBbHRlcm5hdGVDb250ZW50c41OU0NvbnRyb2xTaXplkU5TVG9vbGJhclNpemVNb2RlkE5TVG9vbGJhckl0ZW1UYWeS"
    @"TlNVc2VzSXRlbUZyb21NZW51iU5TU3VwcG9ydJpJQi5zeXN0ZW1Gb250VXBkYXRlVmVyc2lvbo1OU01uZW1vbmljTG9jmE5TSGlk"
    @"ZGVuSW5SZXByZXNlbnRhdGlvbplOU0NvbnRyb2xXcml0aW5nRGlyZWN0aW9unU5TVXNlckludGVyZmFjZUl0ZW1JZGVudGlmaWVy"
    @"jU5TQWx0ZXJzU3RhdGWTTlNUb29sYmFySXRlbVRhcmdldJROU1Rvb2xiYXJJdGVtTWluU2l6ZYtOU0NlbGxGbGFnc5FOU0tleUVx"
    @"dWl2TW9kTWFza4tOU01lbnVJdGVtc5pOU01lbnVJdGVtUmVzcGVjdEFsaWdubWVudIxOU1dpbmRvd1ZpZXeeTlNUb29sYmFySXRl"
    @"bUlnbm9yZU1pbk1heFNpemVzik5TLnNpemV2YWyUVUlOaWJFbmNvZGVyRW1wdHlLZXmZTlNUb29sYmFyUHJlZmVyc1RvQmVTaG93"
    @"bp9JQk5TU2hhZG93ZWRTeW1ib2xDb25maWd1cmF0aW9uiE5TQWN0aW9ulU5TVG9vbGJhckl0ZW1Cb3JkZXJlZJFJQk5TQ2xpcHNU"
    @"b0JvdW5kc49OU1NlbGVjdGVkSW5kZXiaTlNUb29sYmFySXRlbUF1dG92YWxpZGF0ZXONTlNXaW5kb3dUaXRsZZROU1Rvb2xiYXJE"
    @"aXNwbGF5TW9kZZBOU1Zpc2libGVXaW5kb3dzjU5TTmliVG91Y2hCYXKZTlNUb29sYmFySXRlbVBhbGV0dGVMYWJlbJROU1Rvb2xi"
    @"YXJJdGVtTWF4U2l6ZZZOU0NvbnRyb2xUZXh0QWxpZ25tZW50jU5TT2JqZWN0c0tleXOaSUJEZXNpZ25JbWFnZUNvbmZpZ3VyYXRp"
    @"b26bTlNDb250cm9sVXNlc1NpbmdsZUxpbmVNb2Rlmk5TVG9vbGJhcklCSWRlbnRpZmllZEl0ZW1zl05TVG9vbGJhcklCQWxsb3dl"
    @"ZEl0ZW1zkE5TV2luZG93U3VidGl0bGWOTlNSZXNvdXJjZU5hbWWHTlNGcmFtZYhOU1RhcmdldIZOU05hbWWRTlNXaW5kb3dTdHls"
    @"ZU1hc2uJTlNPbkltYWdll0lCTlNTYWZlQXJlYUxheW91dEd1aWRlj05TUHJlZmVycmVkRWRnZYxOU1NjcmVlblJlY3SSTlNUb29s"
    @"YmFySXRlbUxhYmVskU5TVG9vbGJhckRlbGVnYXRli05TVmlld0NsYXNzlklCTlNMYXlvdXRNYXJnaW5zR3VpZGWSTlNUb29sYmFy"
    @"SXRlbUltYWdlhk5TTWVudY5OU0lubGluZWRWYWx1ZZhOU1Rvb2xiYXJJc1VzZXJSZW1vdmFibGWNTlNCdXR0b25GbGFnc41OU0Nv"
    @"bnRyb2xWaWV3i05TQ2xhc3NOYW1ljElCTW9kdWxlTmFtZaZOU1ZpZXdXYW50c0Jlc3RSZXNvbHV0aW9uT3BlbkdMU3VyZmFjZZpO"
    @"U1Rvb2xiYXJJQlNlbGVjdGFibGVJdGVtc5dOU0FjY2Vzc2liaWxpdHlPaWRzS2V5c59OU1Rvb2xiYXJJdGVtVmlzaWJpbGl0eVBy"
    @"aW9yaXR5iE5TdkZsYWdzkk5TVG9vbGJhckl0ZW1UaXRsZZROU1dpbmRvd0lzUmVzdG9yYWJsZZJOU1Rvb2xiYXJJdGVtU3R5bGWP"
    @"TlNLZXlFcXVpdmFsZW50kElCTW9kdWxlUHJvdmlkZXKMTlNPaWRzVmFsdWVzj05TUGVyaW9kaWNEZWxheY5OU0J1dHRvbkZsYWdz"
    @"Mp5OU0NvbnRyb2xSZWZ1c2VzRmlyc3RSZXNwb25kZXKgTlNUb29sYmFyQWxsb3dzVXNlckN1c3RvbWl6YXRpb26GTlNDZWxshk5T"
    @"Um9vdIhOUy5ieXRlc5lOU0FjY2Vzc2liaWxpdHlPaWRzVmFsdWVzjE5TQmV6ZWxTdHlsZZROU1Rvb2xiYXJJdGVtVG9vbFRpcJRO"
    @"U1Rvb2xiYXJJdGVtRW5hYmxlZIdOU1RpdGxliE5TZkZsYWdzik5TQ29udGVudHOPTlNBdXhCdXR0b25UeXBliU5TV1RGbGFnc59O"
    @"U1Rvb2xiYXJBdXRvc2F2ZXNDb25maWd1cmF0aW9unk5TQWxsb3dzTG9naWNhbExheW91dERpcmVjdGlvboxOU01peGVkSW1hZ2WS"
    @"TlNQZXJpb2RpY0ludGVydmFshk5TU2l6ZY9OU05leHRSZXNwb25kZXKMTlNDZWxsRmxhZ3MyiU5TRW5hYmxlZJpOU01pbkZ1bGxT"
    @"Y3JlZW5Db250ZW50U2l6ZZ5OU0FsbG93c0tleUVxdWl2YWxlbnRNaXJyb3JpbmeWTlNDb250cm9sTGluZUJyZWFrTW9kZY1JQk5h"
    @"bWVzcGFjZUlEi05TRnJhbWVTaXplik5TTWVudUl0ZW2LSUJDbGFzc05hbWWMSUJEZXNpZ25TaXpll05TVG9vbGJhcklCRGVmYXVs"
    @"dEl0ZW1zjUlCLm9iamVjdGRhdGGRTlNUb29sYmFySXRlbVZpZXeZTlNBY2Nlc3NpYmlsaXR5Q29ubmVjdG9yc59OU1Rvb2xiYXJD"
    @"ZW50ZXJlZEl0ZW1JZGVudGlmaWVyl05TVG9vbGJhckl0ZW1JZGVudGlmaWVyik5TLnNwZWNpYWyQSUJDbGFzc1JlZmVyZW5jZY1O"
    @"U0Nvbm5lY3Rpb25zj05TV2luZG93QmFja2luZ49OU09iamVjdHNWYWx1ZXOhTlNBbGxvd3NLZXlFcXVpdmFsZW50TG9jYWxpemF0"
    @"aW9uk05TVG9vbGJhckl0ZW1BY3Rpb26aTlNNYXhGdWxsU2NyZWVuQ29udGVudFNpemWNTlNXaW5kb3dDbGFzc49OU0Fycm93UG9z"
    @"aXRpb26JTlMuaW50dmFsl05TQ29udHJvbFNlbmRBY3Rpb25NYXNr8QoBAAAAjAAB1QoCAAAApQoFAAAA+Ao3AAAAqgo4AAAA+go8"
    @"AAAAgwo9AAAAzwo+AAAA8wpQAAAAxwpRAAAA1wpRAAAA9woDAAAAwwoEAAAA7goEAAAAxAnOCdYIiE5TT2JqZWN0vwWbCgYAAAC0"
    @"AAP5AAKCCgcAAADfAgAAeGCjCggAAACvCgkAAAD+CgoAAAC7CgsAAACQCZgKMwAAALgKNQAAAMsF6Ao2AAAA/Qo2AAAA1giYe3s3"
    @"MjAsIDQwNX0sIHs0ODAsIDI3MH191giBV9YIgNYIiE5TV2luZG93gAoMAAAAugmcBdMF4ASkAAGIAAH0Ca0KDQAAAK4KMAAAAPAK"
    @"MQAAAMYKMgAAANYIglRCvwWbCg4AAACbCg8AAACbCicAAACbCigAAADWCIVJVEVNMfUKDgAAALkKEAAAAKcKEAAAANkJ8goRAAAA"
    @"nwW9CcoKCQAAAJIJ/AmTCiYAAACoCiYAAACZBdoFogWJAADIAACEBMAFzAAA1giGT3V0cHV05QmmCckBDAGxChIAAADFBbYJvAmg"
    @"AADnBdQKEwAAAOEEhwAAhQTSBKwEqQAE6gAEjwP//////////wGBAASdCdYIk3t7MCwgMTR9LCB7MzUsIDI1fX2UAkAAAATmAgAI"
    @"ABDdCgkAAACLChQAAADCChEAAADBAwBAgIb/////0QGjANgAC4YKCQAAAM0KCQAAANABkAHjAEveAAftCZcFvgoWAAAAoQP/////"
    @"/////7cAAYoFkQX/AAKzChUAAADkBwAAAAAAACpA3AEWBtYIki5BcHBsZVN5c3RlbVVJRm9udNsKCQAAAJYKFwAAAL8FmwoYAAAA"
    @"mwokAAAAvgoWAAAA+wXpBdsKGQAAAIEKCQAAAJUCAAAQAI0C////f7UKGgAAAOIKHwAAAJ4KIwAAALIKEwAAAI4E1giHRGVmYXVs"
    @"dMMKGwAAALAKHAAAAOsJ7wodAAAAqwnWCIdOU0ltYWdl1giPTlNNZW51Q2hlY2ttYXJr9gACmgoeAAAA1giIezE4LCAxNn3DChsA"
    @"AACwCiAAAADrCe8KIQAAAKsJ1giQTlNNZW51TWl4ZWRTdGF0ZfYAApoKIgAAANYIh3sxOCwgNH3WCJFfcG9wVXBJdGVtQWN0aW9u"
    @"Or4KFgAAAPsF6QXbCiUAAACBCgkAAACVAgAAEACNAv///3+1ChoAAADiCh8AAACeCiMAAACyChMAAACOBNYInEEgbG9uZyBpdGVt"
    @"IHRpdGxlIHRvIGJlIHdpZGXWCIh7MzUsIDI1fdYIhUlURU0y9QonAAAAuQopAAAApwopAAAA2QnyCioAAACfBb0JygoJAAAAkgn8"
    @"CZMKJgAAAKgKJgAAAJkF2gWiBYkAAMgAAIQEwAXMAADWCIVPcmRlcuUJpgnJAQwBsQoSAAAAxQW2CbwJoAAA5wXUCisAAADhBIcA"
    @"AIUE0gSsBKkABOoABI8D//////////8BgQAEnQmUAkAAAATmAgAIABDdCgkAAACLChQAAADCCioAAADBAwBAgIb/////0QGjANgA"
    @"C4YKCQAAAM0KCQAAANABkAHjAEveAAftCZcFvgosAAAAoQP//////////7cAAYoFkQX/AALbCgkAAACWCi0AAAC/BZsKLgAAAJsK"
    @"LwAAAL4KLAAAAPsF6QXbChkAAACBCgkAAACVAgAAEACNAv///3+1ChoAAADiCh8AAACeCiMAAACyCisAAACOBL4KLAAAAPsF6QXb"
    @"CiUAAACBCgkAAACVAgAAEACNAv///3+1ChoAAADiCh8AAACeCiMAAACyCisAAACOBL8FmwoPAAAAmwooAAAAvwWbCg8AAACbCigA"
    @"AAC/BeUJpgnJAQAB7Ao0AAAAxQW2CbwJoAAA1giKezQ4MCwgMjcwfdYIlnt7MCwgMH0sIHsxOTIwLCAxMDgwfX3WCIZ7MCwgMH2/"
    @"Bb8Fmwo5AAAAmwoGAAAAmwozAAAAmwoLAAAAmwoPAAAAmwoRAAAAmwoTAAAAmwoWAAAAmwoYAAAAmwokAAAAmwooAAAAmwoqAAAA"
    @"mworAAAAmwosAAAAmwouAAAAmwovAAAA9wo6AAAAwwo7AAAA7goEAAAAxAnOCdYIjU5TQXBwbGljYXRpb26/BZsKAgAAAJsKAgAA"
    @"AJsKBgAAAJsKBgAAAJsKCwAAAJsKDwAAAJsKEQAAAJsKEwAAAJsKFgAAAJsKFgAAAJsKCwAAAJsKKAAAAJsKKgAAAJsKKwAAAJsK"
    @"LAAAAJsKLAAAAL8FmwoCAAAAmwo5AAAAmwoGAAAAmwozAAAAmwoLAAAAmwoPAAAAmwoRAAAAmwoTAAAAmwoWAAAAmwoYAAAAmwok"
    @"AAAAmwooAAAAmwoqAAAAmworAAAAmwosAAAAmwouAAAAmwovAAAAvwWbCj8AAACbCkAAAACbCkEAAACbCkIAAACbCkMAAACbCkQA"
    @"AACbCkUAAACbCkYAAACbCkcAAACbCkgAAACbCkkAAACbCkoAAACbCksAAACbCkwAAACbCk0AAACbCk4AAACbCk8AAAAAgQABAIEA"
    @"AgCBAAMAgQAEAIEABQCBAAYAgQAHAIEACACBAAkAgQAKAIEACwCBAAwAgQANAIEADgCBAA8AgQAQAIEAEb8FvwWJgE5TT2JqZWN0"
    @"AI+ATlNJQk9iamVjdERhdGEAj4BOU0N1c3RvbU9iamVjdACRgElCQ2xhc3NSZWZlcmVuY2UAiYBOU1N0cmluZwCNgE5TTXV0YWJs"
    @"ZVNldACRgE5TV2luZG93VGVtcGxhdGUAioBOU1Rvb2xiYXIAlIBOU011dGFibGVEaWN0aW9uYXJ5AI6ATlNUb29sYmFySXRlbQCO"
    @"gE5TUG9wVXBCdXR0b24AkoBOU1BvcFVwQnV0dG9uQ2VsbACHgE5TRm9udACHgE5TTWVudQCPgE5TTXV0YWJsZUFycmF5AIuATlNN"
    @"ZW51SXRlbQCRgE5TQ3VzdG9tUmVzb3VyY2UAiIBOU1ZhbHVlAIiATlNBcnJheQCHgE5TVmlldwCJgE5TTnVtYmVyAA==";

@interface Delegate : NSObject <NSToolbarDelegate> {
    NSMutableDictionary *items;
}
@end

@implementation Delegate
- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar {
    return @[ @"popup", @"plain", @"explicit", @"button" ];
}
- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar {
    return [self toolbarAllowedItemIdentifiers: toolbar];
}
- (NSToolbarItem *) toolbar: (NSToolbar *) toolbar
      itemForItemIdentifier: (NSString *) identifier
  willBeInsertedIntoToolbar: (BOOL) flag
{
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];
    [item setLabel: identifier];
    if ([identifier isEqual: @"popup"] || [identifier isEqual: @"explicit"]) {
        NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 35, 25) pullsDown: NO] autorelease];
        [popup addItemWithTitle: @"A rather long output device name"];
        [item setView: popup];
        if ([identifier isEqual: @"explicit"]) {
            [item setMinSize: NSMakeSize(35, 25)];
            [item setMaxSize: NSMakeSize(35, 25)];
        }
    } else if ([identifier isEqual: @"plain"]) {
        [item setView: [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 80, 30)] autorelease]];
    } else {
        NSButton *button = [[[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 35, 25)] autorelease];
        [button setTitle: @"A fairly long button title"];
        [button setBezelStyle: NSBezelStyleRounded];
        [item setView: button];
    }
    return item;
}
@end

static NSWindow *showWindow(NSWindow *window) {
    [window setFrameOrigin: NSMakePoint(100, 300)];
    [window setContentSize: NSMakeSize(900, 200)];
    [window orderFrontRegardless];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.6]];
    return window;
}

static NSToolbarItem *itemNamed(NSToolbar *toolbar, NSString *name) {
    for (NSToolbarItem *item in [toolbar items])
        if ([[item itemIdentifier] isEqual: name])
            return item;
    return nil;
}

static BOOL sameSize(NSSize a, NSSize b) {
    return fabs(a.width - b.width) < 0.5 && fabs(a.height - b.height) < 0.5;
}

static void checkFollowsView(NSToolbarItem *item, const char *what) {
    NSView *view = [item view];
    NSSize intrinsic = [view intrinsicContentSize];
    CHECK(intrinsic.width > 50, "%s: intrinsic width %g", what, intrinsic.width);
    CHECK(sameSize([item minSize], intrinsic), "%s: minSize %s, intrinsic %s", what,
          [NSStringFromSize([item minSize]) UTF8String], [NSStringFromSize(intrinsic) UTF8String]);
    CHECK(sameSize([item maxSize], intrinsic), "%s: maxSize %s, intrinsic %s", what,
          [NSStringFromSize([item maxSize]) UTF8String], [NSStringFromSize(intrinsic) UTF8String]);
    CHECK(fabs(NSWidth([view frame]) - intrinsic.width) < 0.5, "%s: view width %g, intrinsic %g", what,
          NSWidth([view frame]), intrinsic.width);
}

static void checkKeepsExplicitSize(NSToolbarItem *item, const char *what) {
    NSView *view = [item view];
    NSSize intrinsic = [view intrinsicContentSize];
    CHECK(intrinsic.width > 100, "%s: intrinsic width %g", what, intrinsic.width);
    CHECK(fabs(NSWidth([view frame]) - 35) <= 7, "%s: view width %g, wanted about 35", what, NSWidth([view frame]));
    CHECK(fabs([item maxSize].width - 35) <= 7, "%s: maxSize %s", what, [NSStringFromSize([item maxSize]) UTF8String]);
}

static NSWindow *windowFromNib(NSString *base64, id owner) {
    NSData *data = [[[NSData alloc] initWithBase64EncodedString: base64 options: 0] autorelease];
    NSNib *nib = [[[NSNib alloc] initWithNibData: data bundle: nil] autorelease];
    NSArray *top = nil;
    if (![nib instantiateWithOwner: owner topLevelObjects: &top]) {
        fprintf(stderr, "FAIL nib did not load\n");
        failures++;
        return nil;
    }
    for (id object in top)
        if ([object isKindOfClass: [NSWindow class]])
            return object;
    return nil;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyAccessory];

        // Items made in code
        {
            Delegate *delegate = [[Delegate alloc] init];
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 300, 900, 200)
                                                           styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier: @"sizes"];
            [toolbar setDelegate: delegate];
            [window setToolbar: toolbar];
            NSToolbarItem *popup = itemNamed(toolbar, @"popup");
            CHECK(sameSize([popup minSize], [[popup view] intrinsicContentSize]), "popup minSize before the window is shown: %s",
                  [NSStringFromSize([popup minSize]) UTF8String]);
            showWindow(window);
            checkFollowsView(popup, "popup without sizes");
            checkFollowsView(itemNamed(toolbar, @"button"), "button without sizes");
            NSToolbarItem *plain = itemNamed(toolbar, @"plain");
            CHECK(sameSize([plain minSize], NSMakeSize(80, 30)) && sameSize([plain maxSize], NSMakeSize(80, 30)),
                  "plain view: min %s max %s", [NSStringFromSize([plain minSize]) UTF8String],
                  [NSStringFromSize([plain maxSize]) UTF8String]);
            checkKeepsExplicitSize(itemNamed(toolbar, @"explicit"), "popup with explicit sizes");

            // The size follows the view while it has no sizes of its own: a pop-up button that now shows
            // a longer title is laid out wider (the toolbar did not change when only the item was added)
            NSPopUpButton *late = (NSPopUpButton *) [popup view];
            CGFloat before = NSWidth([late frame]);
            [late addItemWithTitle: @"An even longer item title than the first one was, to widen the button"];
            [late selectItemAtIndex: 1];
            [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.4]];
            CHECK(NSWidth([late frame]) > before + 20, "width after selecting a longer item: %g, before %g",
                  NSWidth([late frame]), before);
            checkFollowsView(popup, "popup after selecting a longer item");
            [window close];
        }

        // Items from a nib
        {
            NSWindow *window = windowFromNib(nibWithSizes, [[NSObject alloc] init]);
            if (window) {
                showWindow(window);
                for (NSToolbarItem *item in [[window toolbar] items])
                    checkKeepsExplicitSize(item, "nib item with sizes");
                [window close];
            }
            window = windowFromNib(nibIgnoringSizes, [[NSObject alloc] init]);
            if (window) {
                showWindow(window);
                CHECK([[[window toolbar] items] count] == 2, "items: %lu", (unsigned long) [[[window toolbar] items] count]);
                for (NSToolbarItem *item in [[window toolbar] items])
                    checkFollowsView(item, "nib item ignoring its sizes");
                [window close];
            }
        }

        if (failures) {
            printf("%d FAILED\n", failures);
            return 1;
        }
        printf("ALL PASSED\n");
    }
    return 0;
}
