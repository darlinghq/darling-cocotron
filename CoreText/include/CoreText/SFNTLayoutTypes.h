/* Copyright (C) 2026 Lubos Dolezel */
/*
 * The AAT font feature types and selectors that apps pass in a font descriptor's feature settings, with the numbers of
 * the TrueType Font Feature Registry (kCTFontFeatureTypeIdentifierKey / kCTFontFeatureSelectorIdentifierKey values).
 * This is a subset of the registry; further types are added as needed.
 */
#ifndef CORETEXT_SFNTLAYOUTTYPES_H
#define CORETEXT_SFNTLAYOUTTYPES_H

enum {
	kNumberSpacingType = 6,
	kVerticalPositionType = 10,
	kFractionsType = 11,
	kNumberCaseType = 21,
	kTextSpacingType = 22,
	kLowerCaseType = 37,
	kUpperCaseType = 38,
};

/* kNumberSpacingType */
enum {
	kMonospacedNumbersSelector = 0,
	kProportionalNumbersSelector = 1,
	kThirdWidthNumbersSelector = 2,
	kQuarterWidthNumbersSelector = 3,
};

/* kVerticalPositionType */
enum {
	kNormalPositionSelector = 0,
	kSuperiorsSelector = 1,
	kInferiorsSelector = 2,
	kOrdinalsSelector = 3,
	kScientificInferiorsSelector = 4,
};

/* kFractionsType */
enum {
	kNoFractionsSelector = 0,
	kVerticalFractionsSelector = 1,
	kDiagonalFractionsSelector = 2,
};

/* kNumberCaseType */
enum {
	kLowerCaseNumbersSelector = 0,
	kUpperCaseNumbersSelector = 1,
};

/* kTextSpacingType */
enum {
	kProportionalTextSelector = 0,
	kMonospacedTextSelector = 1,
	kHalfWidthTextSelector = 2,
	kThirdWidthTextSelector = 3,
	kQuarterWidthTextSelector = 4,
	kAltProportionalTextSelector = 5,
	kAltHalfWidthTextSelector = 6,
};

/* kLowerCaseType */
enum {
	kDefaultLowerCaseSelector = 0,
	kLowerCaseSmallCapsSelector = 1,
	kLowerCasePetiteCapsSelector = 2,
};

/* kUpperCaseType */
enum {
	kDefaultUpperCaseSelector = 0,
	kUpperCaseSmallCapsSelector = 1,
	kUpperCasePetiteCapsSelector = 2,
};

#endif /* CORETEXT_SFNTLAYOUTTYPES_H */
