/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The RandR header of Xlib, with the name Picture of the X Render extension made a different one.
 *
 * Xrandr.h reads Xrender.h, which declares the type Picture. QuickDraw's QD.h, reached through the umbrella header
 * ApplicationServices.h, declares a type of the same name (32-bit programs). The backends use no Render pictures, so
 * the Render type is renamed while the X headers are read; the code that includes this header sees QuickDraw's
 * Picture if it has any.
 */
#ifndef X11_XRANDR_H
#define X11_XRANDR_H

#include <X11/Xlib.h>

#define Picture X11RenderPicture
#include <X11/extensions/Xrandr.h>
#undef Picture

#endif
