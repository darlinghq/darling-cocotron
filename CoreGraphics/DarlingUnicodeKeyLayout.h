/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Builds a 'uchr' keyboard layout (the data behind kTISPropertyUnicodeKeyLayoutData, read by
// UCKeyTranslate) from what a window system's keymap says about each key. Shared by the X11 and
// Wayland backends, which only supply the keysym a key gives in a modifier layer.
//
// The layout has one keyboard-type entry that serves every type, 128 key codes and nine tables:
// the eight combinations of Shift, Caps Lock and Option (Option stands for the third level of the
// keymap, AltGr on most layouts), and a Control table. The modifier byte (the Carbon modifier
// flags shifted right by 8, 256 values) selects the table; Command does not change it. A dead key
// is a state record that enters a state and a state terminator that gives its spacing character;
// every character that combines with a dead key gets a record with an entry for each such state.
// Characters that a plain table entry cannot hold (the high bits of a UCKeyOutput are flags, and
// characters outside the BMP) go through the sequence data.
//
// Plain C, no window-system dependencies, so host tests can include it. The caller includes
// <CarbonCore/UnicodeUtilities.h> first.
#ifndef DARLING_UNICODE_KEY_LAYOUT_H
#define DARLING_UNICODE_KEY_LAYOUT_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Layers of a key: bit 0 Shift, bit 1 Caps Lock, bit 2 Option (the keymap's third level).
enum {
    DarlingKeyLayerShift = 1,
    DarlingKeyLayerCaps = 2,
    DarlingKeyLayerOption = 4,
    DarlingKeyLayerCount = 8
};

// kUCKeyStateEntryTerminalFormat of UnicodeUtilities.h, spelled out so that the layout builder
// does not depend on a header that has it.
enum { DarlingKeyStateEntryTerminalFormat = 0x0001 };

typedef struct DarlingKeyLayoutSource {
    void *context;
    // The X11 keysym of the key with the Carbon virtual key code `carbonKey` (0..127) in the
    // layer (a combination of the DarlingKeyLayer bits), 0 for no keysym.
    uint32_t (*keysym)(void *context, int carbonKey, unsigned layer);
    // The Unicode character of a keysym, 0 if it has none.
    uint32_t (*codepoint)(void *context, uint32_t keysym);
    // The single character the base followed by the combining character make when composed
    // (canonical composition), 0 if they do not compose to one character.
    uint32_t (*compose)(void *context, uint32_t base, uint32_t combining);
} DarlingKeyLayoutSource;

enum {
    DarlingKeyLayoutKeyCount = 128,
    DarlingKeyLayoutTableCount = DarlingKeyLayerCount + 1,
    DarlingKeyLayoutControlTable = DarlingKeyLayerCount,
    DarlingKeyLayoutModifierCount = 256,
    DarlingKeyLayoutMaxStates = 64
};

// A dead keysym with its combining character and the spacing character the dead key gives when
// it is followed by Space (the same pairing the X compose tables use).
typedef struct {
    uint32_t keysym, combining, spacing;
} DarlingDeadKeyInfo;

static const DarlingDeadKeyInfo DarlingDeadKeys[] = {
    {0xfe50, 0x0300, 0x0060}, // dead_grave
    {0xfe51, 0x0301, 0x00b4}, // dead_acute
    {0xfe52, 0x0302, 0x005e}, // dead_circumflex
    {0xfe53, 0x0303, 0x007e}, // dead_tilde
    {0xfe54, 0x0304, 0x00af}, // dead_macron
    {0xfe55, 0x0306, 0x02d8}, // dead_breve
    {0xfe56, 0x0307, 0x02d9}, // dead_abovedot
    {0xfe57, 0x0308, 0x00a8}, // dead_diaeresis
    {0xfe58, 0x030a, 0x02da}, // dead_abovering
    {0xfe59, 0x030b, 0x02dd}, // dead_doubleacute
    {0xfe5a, 0x030c, 0x02c7}, // dead_caron
    {0xfe5b, 0x0327, 0x00b8}, // dead_cedilla
    {0xfe5c, 0x0328, 0x02db}, // dead_ogonek
    {0xfe60, 0x0323, 0x002e}, // dead_belowdot
    {0xfe61, 0x0309, 0x02c0}, // dead_hook
    {0xfe62, 0x031b, 0x02bc}, // dead_horn
    {0xfe66, 0x030f, 0x02f5}, // dead_doublegrave
};

static inline const DarlingDeadKeyInfo *DarlingDeadKeyForKeysym(uint32_t keysym) {
    for (size_t i = 0; i < sizeof DarlingDeadKeys / sizeof DarlingDeadKeys[0]; i++)
        if (DarlingDeadKeys[i].keysym == keysym)
            return &DarlingDeadKeys[i];
    return NULL;
}

// The character Mac layouts give for keys that edit or navigate: a control code. Returns 0 for a
// keysym that is not one of these.
static inline uint32_t DarlingKeysymControlCode(uint32_t keysym) {
    switch (keysym) {
    case 0xff08: return 0x08; // BackSpace
    case 0xff09: case 0xfe20: return 0x09; // Tab, ISO_Left_Tab
    case 0xff0d: return 0x0d; // Return
    case 0xff8d: return 0x03; // KP_Enter
    case 0xff1b: return 0x1b; // Escape
    case 0xffff: return 0x7f; // Delete
    case 0xff51: return 0x1c; // Left
    case 0xff53: return 0x1d; // Right
    case 0xff52: return 0x1e; // Up
    case 0xff54: return 0x1f; // Down
    case 0xff50: return 0x01; // Home
    case 0xff57: return 0x04; // End
    case 0xff55: return 0x0b; // Page_Up
    case 0xff56: return 0x0c; // Page_Down
    case 0xff6a: return 0x05; // Help
    default:
        if (keysym >= 0xffbe && keysym <= 0xffd5) // F1..F24
            return 0x10;
        return 0;
    }
}

// The digit or punctuation a keypad navigation keysym stands for with Num Lock on. The layers of a
// layout do not model Num Lock, and a keypad key gives its digit on a Mac.
static inline uint32_t DarlingKeysymKeypadCharacter(uint32_t keysym) {
    switch (keysym) {
    case 0xff95: return '7'; // KP_Home
    case 0xff96: return '4'; // KP_Left
    case 0xff97: return '8'; // KP_Up
    case 0xff98: return '6'; // KP_Right
    case 0xff99: return '2'; // KP_Down
    case 0xff9a: return '9'; // KP_Prior
    case 0xff9b: return '3'; // KP_Next
    case 0xff9c: return '1'; // KP_End
    case 0xff9d: return '5'; // KP_Begin
    case 0xff9e: return '0'; // KP_Insert
    case 0xff9f: return '.'; // KP_Delete
    default: return 0;
    }
}

typedef struct {
    uint8_t kind; // 0 none, 1 character, 2 dead key
    uint32_t value; // the character, or the dead state number
} DarlingKeyCell;

typedef struct {
    uint8_t *bytes;
    size_t length, capacity;
    int failed;
} DarlingLayoutBuffer;

static inline size_t DarlingLayoutAppend(DarlingLayoutBuffer *b, const void *data, size_t length) {
    if (b->failed)
        return 0;
    if (b->length + length > b->capacity) {
        size_t capacity = b->capacity ? b->capacity * 2 : 4096;
        while (capacity < b->length + length)
            capacity *= 2;
        uint8_t *bytes = realloc(b->bytes, capacity);
        if (bytes == NULL) {
            b->failed = 1;
            return 0;
        }
        b->bytes = bytes;
        b->capacity = capacity;
    }
    size_t at = b->length;
    if (data != NULL)
        memcpy(b->bytes + at, data, length);
    else
        memset(b->bytes + at, 0, length);
    b->length += length;
    return at;
}

static inline void DarlingLayoutPut16(DarlingLayoutBuffer *b, uint16_t v) {
    DarlingLayoutAppend(b, &v, sizeof v);
}

static inline void DarlingLayoutPut32(DarlingLayoutBuffer *b, uint32_t v) {
    DarlingLayoutAppend(b, &v, sizeof v);
}

static inline void DarlingLayoutSet32(DarlingLayoutBuffer *b, size_t at, uint32_t v) {
    if (!b->failed)
        memcpy(b->bytes + at, &v, sizeof v);
}

static inline void DarlingLayoutAlign4(DarlingLayoutBuffer *b) {
    while (b->length % 4 != 0)
        DarlingLayoutAppend(b, NULL, 1);
}

// The sequence data: every entry holds the UTF-16 units of one string.
typedef struct {
    uint16_t *units;
    size_t unitCount;
    uint16_t *starts; // unit offset of each sequence
    size_t count;
    int failed;
} DarlingSequences;

// Gives the UCKeyOutput (or UCKeyCharSeq) value for a character: the character itself when a plain
// entry can hold it, otherwise an index into the sequence data.
static inline uint16_t DarlingEncodeCharacter(DarlingSequences *sequences, uint32_t codepoint) {
    if (codepoint == 0)
        return 0xFFFE;
    if (codepoint <= 0xFFFF && (codepoint & 0xC000) != 0x4000 && (codepoint & 0xC000) != 0x8000 &&
        codepoint != 0xFFFE && codepoint != 0xFFFF)
        return (uint16_t) codepoint;
    if (codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF) || codepoint == 0xFFFE ||
        codepoint == 0xFFFF || sequences->count >= 0x3FFF || sequences->failed)
        return 0xFFFE;

    uint16_t *units = realloc(sequences->units, (sequences->unitCount + 2) * sizeof(uint16_t));
    uint16_t *starts = realloc(sequences->starts, (sequences->count + 2) * sizeof(uint16_t));
    if (units != NULL)
        sequences->units = units;
    if (starts != NULL)
        sequences->starts = starts;
    if (units == NULL || starts == NULL) {
        sequences->failed = 1;
        return 0xFFFE;
    }
    sequences->starts[sequences->count] = (uint16_t) sequences->unitCount;
    if (codepoint > 0xFFFF) {
        codepoint -= 0x10000;
        sequences->units[sequences->unitCount++] = (uint16_t) (0xD800 + (codepoint >> 10));
        sequences->units[sequences->unitCount++] = (uint16_t) (0xDC00 + (codepoint & 0x3FF));
    } else
        sequences->units[sequences->unitCount++] = (uint16_t) codepoint;
    return (uint16_t) (kUCKeyOutputSequenceIndexMask | sequences->count++);
}

// Builds the layout. The result is malloc'ed and its size goes to *byteLength; NULL when out of
// memory. The caller frees it.
static inline UCKeyboardLayout *DarlingCreateUnicodeKeyLayout(const DarlingKeyLayoutSource *source,
                                                              uint32_t *byteLength) {
    DarlingKeyCell *cells = calloc((size_t) DarlingKeyLayoutTableCount * DarlingKeyLayoutKeyCount,
                                   sizeof(DarlingKeyCell));
    if (cells == NULL)
        return NULL;
#define CELL(table, key) cells[(size_t) (table) * DarlingKeyLayoutKeyCount + (key)]

    // The dead keys found, one state each.
    const DarlingDeadKeyInfo *states[DarlingKeyLayoutMaxStates];
    unsigned stateCount = 0;

    for (unsigned layer = 0; layer < DarlingKeyLayerCount; layer++) {
        for (int key = 0; key < DarlingKeyLayoutKeyCount; key++) {
            uint32_t keysym = source->keysym(source->context, key, layer);
            DarlingKeyCell *cell = &CELL(layer, key);
            if (keysym == 0)
                continue;
            if (keysym >= 0xfe50 && keysym <= 0xfe8f) {
                const DarlingDeadKeyInfo *dead = DarlingDeadKeyForKeysym(keysym);
                if (dead == NULL)
                    continue;
                unsigned state = 0;
                while (state < stateCount && states[state] != dead)
                    state++;
                if (state == stateCount) {
                    if (stateCount == DarlingKeyLayoutMaxStates)
                        continue;
                    states[stateCount++] = dead;
                }
                cell->kind = 2;
                cell->value = state + 1;
                continue;
            }
            uint32_t code = DarlingKeysymControlCode(keysym);
            if (code == 0)
                code = DarlingKeysymKeypadCharacter(keysym);
            if (code == 0)
                code = source->codepoint(source->context, keysym);
            // AppKit's function-key characters are not what a layout produces.
            if (code >= 0xF700 && code <= 0xF8FF)
                code = 0;
            if (code != 0) {
                cell->kind = 1;
                cell->value = code;
            }
        }
    }

    // The Control table: control codes for the keys that give an ASCII letter or punctuation of
    // the 0x40..0x7F block, and for control codes the plain character; no dead keys.
    for (int key = 0; key < DarlingKeyLayoutKeyCount; key++) {
        DarlingKeyCell plain = CELL(0, key);
        if (plain.kind == 1 && plain.value >= 0x40 && plain.value <= 0x7f)
            plain.value &= 0x1f;
        else if (plain.kind == 2)
            plain.kind = 0;
        CELL(DarlingKeyLayoutControlTable, key) = plain;
    }

    DarlingSequences sequences = {0};

    // The characters that combine with a dead state need a state record of their own: one per
    // distinct character.
    uint32_t *recordBases = NULL;
    size_t recordBaseCount = 0;
    if (stateCount > 0) {
        recordBases = calloc((size_t) DarlingKeyLayoutTableCount * DarlingKeyLayoutKeyCount + 1,
                             sizeof(uint32_t));
        if (recordBases == NULL) {
            free(cells);
            return NULL;
        }
        recordBases[recordBaseCount++] = 0x20; // Space: the dead key's own character
        for (size_t i = 0; i < (size_t) DarlingKeyLayoutTableCount * DarlingKeyLayoutKeyCount; i++) {
            if (cells[i].kind != 1 || cells[i].value > 0xFFFF)
                continue;
            int combines = 0;
            for (unsigned s = 0; s < stateCount && !combines; s++)
                combines = source->compose(source->context, cells[i].value, states[s]->combining) != 0;
            if (!combines)
                continue;
            size_t j = 0;
            while (j < recordBaseCount && recordBases[j] != cells[i].value)
                j++;
            if (j == recordBaseCount)
                recordBases[recordBaseCount++] = cells[i].value;
        }
    }
    const size_t recordCount = stateCount + recordBaseCount;

    DarlingLayoutBuffer out = {0};
    // Header and the one keyboard type entry: it serves every keyboard type.
    DarlingLayoutPut16(&out, kUCKeyLayoutHeaderFormat);
    DarlingLayoutPut16(&out, 0x0100);
    size_t featureOffset = out.length;
    DarlingLayoutPut32(&out, 0);
    DarlingLayoutPut32(&out, 1);
    size_t typeHeader = out.length;
    DarlingLayoutAppend(&out, NULL, sizeof(UCKeyboardTypeHeader));
    DarlingLayoutAlign4(&out);

    DarlingLayoutSet32(&out, featureOffset, (uint32_t) out.length);
    DarlingLayoutPut16(&out, kUCKeyLayoutFeatureInfoFormat);
    DarlingLayoutPut16(&out, 0);
    DarlingLayoutPut32(&out, 2);

    size_t modifiersAt = out.length;
    DarlingLayoutPut16(&out, kUCKeyModifiersToTableNumFormat);
    DarlingLayoutPut16(&out, 0);
    DarlingLayoutPut32(&out, DarlingKeyLayoutModifierCount);
    for (unsigned byte = 0; byte < DarlingKeyLayoutModifierCount; byte++) {
        unsigned table;
        if (byte & 0x90) // Control, either side
            table = DarlingKeyLayoutControlTable;
        else
            table = ((byte & 0x22) ? DarlingKeyLayerShift : 0) | ((byte & 0x04) ? DarlingKeyLayerCaps : 0) |
                    ((byte & 0x48) ? DarlingKeyLayerOption : 0);
        uint8_t t = (uint8_t) table;
        DarlingLayoutAppend(&out, &t, 1);
    }
    DarlingLayoutAlign4(&out);

    size_t tableIndexAt = out.length;
    DarlingLayoutPut16(&out, kUCKeyToCharTableIndexFormat);
    DarlingLayoutPut16(&out, DarlingKeyLayoutKeyCount);
    DarlingLayoutPut32(&out, DarlingKeyLayoutTableCount);
    size_t tableOffsetsAt = out.length;
    DarlingLayoutAppend(&out, NULL, 4 * DarlingKeyLayoutTableCount);
    size_t tablesAt = out.length;
    DarlingLayoutAppend(&out, NULL, (size_t) DarlingKeyLayoutTableCount * DarlingKeyLayoutKeyCount * 2);
    DarlingLayoutAlign4(&out);

    // State record numbers: the dead keys first, then the combining characters.
    size_t recordsAt = 0;
    size_t recordOffsetsAt = 0;
    if (recordCount > 0) {
        recordsAt = out.length;
        DarlingLayoutPut16(&out, kUCKeyStateRecordsIndexFormat);
        DarlingLayoutPut16(&out, (uint16_t) recordCount);
        recordOffsetsAt = out.length;
        DarlingLayoutAppend(&out, NULL, 4 * recordCount);
        for (unsigned s = 0; s < stateCount; s++) {
            // Entering the dead state; the key itself gives no character.
            DarlingLayoutSet32(&out, recordOffsetsAt + 4 * s, (uint32_t) out.length);
            DarlingLayoutPut16(&out, 0xFFFF);
            DarlingLayoutPut16(&out, (uint16_t) (s + 1));
            DarlingLayoutPut16(&out, 0);
            DarlingLayoutPut16(&out, DarlingKeyStateEntryTerminalFormat);
        }
        for (size_t b = 0; b < recordBaseCount; b++) {
            uint32_t base = recordBases[b];
            uint16_t entryChars[DarlingKeyLayoutMaxStates];
            uint16_t entryCount = 0;
            uint16_t entryState[DarlingKeyLayoutMaxStates];
            for (unsigned s = 0; s < stateCount; s++) {
                uint32_t composed = base == 0x20 ? states[s]->spacing
                                                 : source->compose(source->context, base, states[s]->combining);
                if (composed == 0)
                    continue;
                entryState[entryCount] = (uint16_t) (s + 1);
                entryChars[entryCount++] = DarlingEncodeCharacter(&sequences, composed);
            }
            uint16_t zero = DarlingEncodeCharacter(&sequences, base);
            DarlingLayoutSet32(&out, recordOffsetsAt + 4 * (stateCount + b), (uint32_t) out.length);
            DarlingLayoutPut16(&out, zero);
            DarlingLayoutPut16(&out, 0);
            DarlingLayoutPut16(&out, entryCount);
            DarlingLayoutPut16(&out, DarlingKeyStateEntryTerminalFormat);
            for (uint16_t e = 0; e < entryCount; e++) {
                DarlingLayoutPut16(&out, entryState[e]);
                DarlingLayoutPut16(&out, entryChars[e]);
            }
        }
        DarlingLayoutAlign4(&out);
    }

    size_t terminatorsAt = 0;
    if (stateCount > 0) {
        terminatorsAt = out.length;
        DarlingLayoutPut16(&out, kUCKeyStateTerminatorsFormat);
        DarlingLayoutPut16(&out, (uint16_t) stateCount);
        for (unsigned s = 0; s < stateCount; s++)
            DarlingLayoutPut16(&out, DarlingEncodeCharacter(&sequences, states[s]->spacing));
        DarlingLayoutAlign4(&out);
    }

    // The key tables.
    for (unsigned table = 0; table < DarlingKeyLayoutTableCount; table++) {
        DarlingLayoutSet32(&out, tableOffsetsAt + 4 * table,
                           (uint32_t) (tablesAt + (size_t) table * DarlingKeyLayoutKeyCount * 2));
        for (int key = 0; key < DarlingKeyLayoutKeyCount; key++) {
            DarlingKeyCell cell = CELL(table, key);
            uint16_t value = 0xFFFE;
            if (cell.kind == 2)
                value = (uint16_t) (kUCKeyOutputStateIndexMask | (cell.value - 1));
            else if (cell.kind == 1) {
                size_t b = 0;
                while (b < recordBaseCount && recordBases[b] != cell.value)
                    b++;
                if (b < recordBaseCount)
                    value = (uint16_t) (kUCKeyOutputStateIndexMask | (stateCount + b));
                else
                    value = DarlingEncodeCharacter(&sequences, cell.value);
            }
            if (!out.failed)
                memcpy(out.bytes + tablesAt + ((size_t) table * DarlingKeyLayoutKeyCount + key) * 2, &value, 2);
        }
    }

    // The sequence data: a count, count+1 byte offsets from its start, then the strings.
    size_t sequencesAt = 0;
    if (sequences.count > 0) {
        sequencesAt = out.length;
        DarlingLayoutPut16(&out, kUCKeySequenceDataIndexFormat);
        DarlingLayoutPut16(&out, (uint16_t) sequences.count);
        size_t dataStart = 4 + 2 * (sequences.count + 1);
        for (size_t i = 0; i <= sequences.count; i++) {
            size_t unitOffset = i < sequences.count ? sequences.starts[i] : sequences.unitCount;
            DarlingLayoutPut16(&out, (uint16_t) (dataStart + 2 * unitOffset));
        }
        DarlingLayoutAppend(&out, sequences.units, 2 * sequences.unitCount);
        DarlingLayoutAlign4(&out);
    }

    // The keyboard type header, now that the offsets are known.
    if (!out.failed) {
        UCKeyboardTypeHeader header;
        memset(&header, 0, sizeof header);
        header.keyboardTypeFirst = 0;
        header.keyboardTypeLast = 0;
        header.keyModifiersToTableNumOffset = (uint32_t) modifiersAt;
        header.keyToCharTableIndexOffset = (uint32_t) tableIndexAt;
        header.keyStateRecordsIndexOffset = (uint32_t) recordsAt;
        header.keyStateTerminatorsOffset = (uint32_t) terminatorsAt;
        header.keySequenceDataIndexOffset = (uint32_t) sequencesAt;
        memcpy(out.bytes + typeHeader, &header, sizeof header);
    }
#undef CELL

    free(cells);
    free(recordBases);
    free(sequences.units);
    free(sequences.starts);
    if (out.failed) {
        free(out.bytes);
        return NULL;
    }
    if (byteLength != NULL)
        *byteLength = (uint32_t) out.length;
    return (UCKeyboardLayout *) out.bytes;
}

#endif
