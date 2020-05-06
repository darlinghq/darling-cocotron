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

#import <Foundation/Foundation.h>
#import <QuartzCore/CABase.h>
#import <QuartzCore/CALayer.h>

CA_EXPORT NSString *const kCAAlignmentNatural;
CA_EXPORT NSString *const kCAAlignmentLeft;
CA_EXPORT NSString *const kCAAlignmentRight;
CA_EXPORT NSString *const kCAAlignmentCenter;
CA_EXPORT NSString *const kCAAlignmentJustified;

CA_EXPORT NSString *const kCATruncationNone;
CA_EXPORT NSString *const kCATruncationStart;
CA_EXPORT NSString *const kCATruncationEnd;
CA_EXPORT NSString *const kCATruncationMiddle;

@interface CATextLayer : CALayer

@end
