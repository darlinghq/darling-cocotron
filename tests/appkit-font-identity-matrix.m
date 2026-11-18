// CFLAGS: -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// NSFontIdentityMatrix is exported. Its value is either NULL (observed on macOS 26.7.3) or the
// identity matrix of the documentation; the program passes on macOS 26.7.3 and on Darling.
#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void)
{
	int ok = 1;
	const CGFloat *matrix = NSFontIdentityMatrix;
	if (matrix != NULL) {
		const CGFloat identity[6] = { 1, 0, 0, 1, 0, 0 };
		for (int i = 0; i < 6; i++)
			ok = ok && matrix[i] == identity[i];
	}
	printf(ok ? "PASS\n" : "FAIL: not the identity matrix\n");
	return !ok;
}
