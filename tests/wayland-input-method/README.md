# Fake input method for the Wayland text input test

`fake-input-method.c` is a Wayland input method (zwp_input_method_v2) that composes text on a
compositor which has it (sway, other wlroots compositors). When a text input client enables
text input, it sends the composition "ka", then the composition of the kana for it, then commits
that kana as final text, then composes "x" and cancels it. `../appkit-wayland-text-input.m`
(Darling's Wayland AppKit backend) runs against it.

Build on the host (needs wayland-client and wayland-scanner):

    wayland-scanner private-code input-method-unstable-v2.xml im-protocol.c
    wayland-scanner client-header input-method-unstable-v2.xml im-client.h
    cc -o fake-input-method fake-input-method.c im-protocol.c -lwayland-client

Run it with the compositor's `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` before the test, then run the
test with `DARLING_TEST_INPUT_METHOD=1`.

`input-method-unstable-v2.xml` is the wlroots protocol description, kept unchanged:

- Source: https://gitlab.freedesktop.org/wlroots/wlroots, `protocol/input-method-unstable-v2.xml`, tag 0.16.2
- Copyright: 2008-2011 Kristian Høgsberg, 2010-2011 Intel, 2012-2013 Collabora, 2015-2016 Jan Arne
  Petersen, 2017-2018 Red Hat, 2018 Purism SPC
- Licence: the MIT permission notice at the top of the file; compatible with this project's licence.
