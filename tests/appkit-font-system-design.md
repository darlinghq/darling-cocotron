# NSFontDescriptor system designs

Build `appkit-font-system-design.m` against AppKit and run it in a Darling guest. Pass the families
the host's fontconfig should pick for the serif, monospaced and rounded designs, or `-` for a design
with no installed family:

```sh
darling shell appkit-font-system-design "$(fc-match -f '%{family[0]}' serif)" \
    "$(fc-match -f '%{family[0]}' monospace)" -
```

Designs apply only to the system font, and each non-default design maps to a CSS generic family in
fontconfig (`serif`, `monospace`, `ui-rounded`). Stock fontconfig configurations have no family for
`ui-rounded`, so the rounded design is nil there, as on a Mac without a rounded system font. To check
the rounded path, point `FONTCONFIG_FILE` at a configuration that gives `ui-rounded` a family:

```xml
<fontconfig>
  <include ignore_missing="no">/etc/fonts/fonts.conf</include>
  <match target="pattern">
    <test name="family"><string>ui-rounded</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>Nimbus Sans</string></edit>
  </match>
</fontconfig>
```

and pass `"Nimbus Sans"` (or the family you configured) as the third argument. The pre-fix AppKit
exports none of the design constants, so the program fails to link against it.
