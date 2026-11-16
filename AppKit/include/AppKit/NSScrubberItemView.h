/*
 * This file is part of Darling.
 *
 * Copyright (C) 2024 Darling Developers
 *
 * Darling is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Darling is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Darling.  If not, see <http://www.gnu.org/licenses/>.
 */

#import <AppKit/NSView.h>
#import <AppKit/AppKitIvarLayout.h>

@interface NSScrubberArrangedView : NSView {
    NS_LEGACY_IVAR_PAD(_NSScrubberArrangedViewReserved, 20)
}
@end

@interface NSScrubberItemView : NSScrubberArrangedView {
    NS_LEGACY_IVAR_PAD(_NSScrubberItemViewReserved, 32)
}
@end

@interface NSScrubberTextItemView : NSScrubberItemView {
    NS_LEGACY_IVAR_PAD(_NSScrubberTextItemViewReserved, 20)
}
@end

@interface NSScrubberImageItemView : NSScrubberItemView {
    NS_LEGACY_IVAR_PAD(_NSScrubberImageItemViewReserved, 24)
}
@end
