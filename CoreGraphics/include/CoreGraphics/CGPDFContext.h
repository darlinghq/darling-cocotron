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

#ifndef _CG_PDFCONTEXT_H_
#define _CG_PDFCONTEXT_H_

#include <CoreFoundation/CFString.h>
#include <CoreGraphics/CoreGraphicsExport.h>

COREGRAPHICS_EXPORT const CFStringRef kCGPDFContextKeywords;
COREGRAPHICS_EXPORT const CFStringRef kCGPDFContextTitle;
COREGRAPHICS_EXPORT const CFStringRef kCGPDFContextMediaBox;

typedef struct CF_BRIDGED_TYPE(id) O2PDFContext *CGPDFContextRef;

CF_IMPLICIT_BRIDGING_ENABLED

COREGRAPHICS_EXPORT CGContextRef
CGPDFContextCreate(CGDataConsumerRef consumer, const CGRect *mediaBox,
                   CFDictionaryRef auxiliaryInfo);
COREGRAPHICS_EXPORT void CGPDFContextClose(CGContextRef self);

CF_IMPLICIT_BRIDGING_DISABLED

#endif
