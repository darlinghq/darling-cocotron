#import "DarlingLayout.h"
#import <AppKit/NSLayoutConstraint.h>
#import <Foundation/NSException.h>
#include "third_party/kiwi/kiwi.h"
#include <map>
#include <cmath>

namespace {
struct Geometry { kiwi::Variable x, y, width, height; };
class Layout {
    NSView *root;
    // Fitting solves for the root's own size instead of pinning it, with the
    // vertical axis running downwards whatever the root's flippedness is.
    bool fitting;
    kiwi::Solver solver;
    std::map<NSView *, Geometry> geometry;
    std::vector<NSView *> traversal;
    NSMutableArray *constraints;
    std::map<double, std::vector<kiwi::Constraint>, std::greater<double>> optional;

    void collect(NSView *view) {
        geometry.emplace(view, Geometry());
        traversal.push_back(view);
        [constraints addObjectsFromArray:[view constraints]];
        for (NSView *child in [view subviews]) collect(child);
    }

    bool rootFlipped() const { return fitting || [root isFlipped]; }

    // Maps a rectangle in the root's coordinates to the solver's, where y runs
    // downwards in fitting mode (the root's height is a variable there).
    NSRect solverRect(NSRect rect) const {
        if (fitting && ![root isFlipped])
            rect.origin.y = NSMaxY([root bounds]) - NSMaxY(rect);
        return rect;
    }

    // The edges and sizes layout constraints refer to are those of the view's
    // alignment rectangle: the frame less the alignment insets.
    kiwi::Expression attribute(NSView *view, NSInteger attr) {
        auto found = geometry.find(view);
        if (found == geometry.end())
            [NSException raise:NSInvalidArgumentException format:@"Layout item is outside the view tree: %@", view];
        Geometry &g = found->second;
        bool rtl = [view userInterfaceLayoutDirection] == NSUserInterfaceLayoutDirectionRightToLeft;
        switch (attr) {
        case NSLayoutAttributeLeading: attr = rtl ? NSLayoutAttributeRight : NSLayoutAttributeLeft; break;
        case NSLayoutAttributeTrailing: attr = rtl ? NSLayoutAttributeLeft : NSLayoutAttributeRight; break;
        }
        // Auto Layout y values increase downwards in AppKit too, so an unflipped
        // root's y is measured from its top edge.
        bool flipped = rootFlipped();
        double top = NSMaxY([root bounds]);
        NSEdgeInsets insets = [view alignmentRectInsets];
        // Insets name the visual sides, so top and bottom are the same in any
        // coordinate system.
        kiwi::Expression left = g.x + insets.left;
        kiwi::Expression right = g.x + g.width - insets.right;
        kiwi::Expression above = flipped ? g.y + insets.top : top - (g.y + g.height) + insets.top;
        kiwi::Expression below = flipped ? g.y + g.height - insets.bottom : top - g.y - insets.bottom;
        switch (attr) {
        case NSLayoutAttributeLeft: return left;
        case NSLayoutAttributeRight: return right;
        case NSLayoutAttributeTop: return above;
        case NSLayoutAttributeBottom: return below;
        case NSLayoutAttributeWidth: return g.width - (insets.left + insets.right);
        case NSLayoutAttributeHeight: return g.height - (insets.top + insets.bottom);
        case NSLayoutAttributeCenterX: return (left + right) * 0.5;
        case NSLayoutAttributeCenterY: return (above + below) * 0.5;
        case NSLayoutAttributeFirstBaseline:
            return above + [view firstBaselineOffsetFromTop];
        case NSLayoutAttributeLastBaseline:
            return below - [view lastBaselineOffsetFromBottom];
        default:
            [NSException raise:NSInvalidArgumentException format:@"Unsupported layout attribute: %ld", (long)attr];
            return kiwi::Expression();
        }
    }

    // A required constraint that conflicts with the ones added before it is broken: the layout
    // goes on without it and the conflict is logged, rather than the whole layout being abandoned.
    // `source` is the constraint it stands for, nil for a view's own frame.
    void add(const kiwi::Constraint &constraint, NSLayoutConstraint *source = nil) {
        if (constraint.strength() == kiwi::strength::required) {
            try {
                solver.addConstraint(constraint);
            } catch (const kiwi::UnsatisfiableConstraint &) {
                NSLog(@"Unable to simultaneously satisfy constraints. Will attempt to recover by breaking constraint %@",
                      source ? [source description] : @"(a view frame)");
            }
        } else
            optional[constraint.strength()].push_back(constraint);
    }

    void solvePriorities() {
        for (auto &tier : optional) {
            std::vector<kiwi::Constraint> soft, frozen;
            for (const auto &constraint : tier.second) {
                soft.push_back(constraint | 1.0);
                solver.addConstraint(soft.back());
            }
            solver.updateVariables();
            for (const auto &constraint : tier.second) {
                const auto &expression = constraint.expression();
                double residual = expression.value();
                bool satisfied = kiwi::impl::nearZero(residual) ||
                    (constraint.op() == kiwi::OP_LE && residual < 0) ||
                    (constraint.op() == kiwi::OP_GE && residual > 0);
                if (satisfied)
                    frozen.push_back(constraint | kiwi::strength::required);
                else
                    frozen.push_back(expression == residual);
            }
            for (const auto &constraint : soft) solver.removeConstraint(constraint);
            for (const auto &constraint : frozen) solver.addConstraint(constraint);
        }
        solver.updateVariables();
    }

    void intrinsic(NSView *view, Geometry &g) {
        NSSize size = [view intrinsicContentSize];
        NSEdgeInsets insets = [view alignmentRectInsets];
        // The intrinsic size is that of the alignment rectangle.
        kiwi::Expression dimensions[] = {g.width - (insets.left + insets.right),
                                         g.height - (insets.top + insets.bottom)};
        double values[] = {size.width, size.height};
        for (int axis = 0; axis < 2; ++axis) {
            if (values[axis] == NSViewNoIntrinsicMetric) continue;
            if (!std::isfinite(values[axis]) || values[axis] < 0)
                [NSException raise:NSInvalidArgumentException format:@"Invalid intrinsic size for %@", view];
            double hugging = [view contentHuggingPriorityForOrientation:(NSLayoutConstraintOrientation)axis];
            double compression = [view contentCompressionResistancePriorityForOrientation:(NSLayoutConstraintOrientation)axis];
            add((dimensions[axis] <= values[axis]) | hugging);
            add((dimensions[axis] >= values[axis]) | compression);
        }
    }

public:
    explicit Layout(NSView *view, bool fittingSolve = false)
        : root(view), fitting(fittingSolve), constraints([[NSMutableArray alloc] init]) {}
    ~Layout() { [constraints release]; }
    // The size of the root that satisfies the constraints of its subtree with
    // the least room: the root is not pinned to its frame and is pulled
    // towards zero size at NSLayoutPriorityFittingSizeCompression, so anything
    // of higher priority (required constraints, intrinsic sizes that resist
    // compression) keeps it open. No view is touched.
    NSSize fittingSize() {
        collect(root);
        buildConstraints();
        Geometry &g = geometry.at(root);
        add(g.x == 0.0);
        add(g.y == 0.0);
        add((g.width == 0.0) | (double)NSLayoutPriorityFittingSizeCompression);
        add((g.height == 0.0) | (double)NSLayoutPriorityFittingSizeCompression);
        solvePriorities();
        return NSMakeSize(g.width.value(), g.height.value());
    }

    // Like fittingSize, but the root is held at currentSize by a constraint of window-size priority
    // instead of being pulled towards zero. Returns false when there is nothing to solve.
    bool preferredSize(NSSize currentSize, NSSize *result) {
        collect(root);
        if ([constraints count] == 0) return false;
        buildConstraints();
        Geometry &g = geometry.at(root);
        add(g.x == 0.0);
        add(g.y == 0.0);
        add((g.width == currentSize.width) | (double)NSLayoutPriorityWindowSizeStayPut);
        add((g.height == currentSize.height) | (double)NSLayoutPriorityWindowSizeStayPut);
        solvePriorities();
        *result = NSMakeSize(g.width.value(), g.height.value());
        return true;
    }

    void run() {
        collect(root);
        if ([constraints count] == 0) return;
        buildConstraints();
        solvePriorities();
        applyResults();
    }

    // One axis of a view whose autoresizing mask is translated into constraints. The low margin,
    // the size and the high margin of the view's frame in its superview are each either fixed or
    // flexible; flexible ones share the superview's remaining extent in proportion to their size
    // when the layout started, as the autoresizing mask documentation describes.
    void autoresizingAxis(kiwi::Variable &position, kiwi::Variable &extent, kiwi::Variable &parentPosition,
                          kiwi::Variable &parentExtent, double low, double size, double high,
                          bool lowFlexible, bool sizeFlexible, bool highFlexible) {
        kiwi::Expression comps[3] = {position - parentPosition, kiwi::Expression(extent),
                                     parentPosition + parentExtent - position - extent};
        double original[3] = {low, size, high};
        bool flexible[3] = {lowFlexible, sizeFlexible, highFlexible};
        if (!lowFlexible && !sizeFlexible && !highFlexible) {
            // Nothing flexible: the view keeps its distance from the low edge and its size.
            add(comps[0] == low);
            add(comps[1] == size);
            return;
        }
        kiwi::Expression fixedSum;
        double total = 0;
        int flexibleCount = 0;
        for (int i = 0; i < 3; ++i) {
            if (flexible[i]) { total += original[i]; ++flexibleCount; }
            else { add(comps[i] == original[i]); fixedSum = fixedSum + comps[i]; }
        }
        if (flexibleCount == 0) return;
        kiwi::Expression remaining = parentExtent - fixedSum;
        for (int i = 0; i < 3; ++i) {
            if (!flexible[i]) continue;
            double share = total > 0 ? original[i] / total : 1.0 / flexibleCount;
            add(comps[i] == remaining * share);
        }
    }

    void autoresizing(NSView *view, Geometry &g) {
        NSView *parent = [view superview];
        Geometry &p = geometry.at(parent);
        NSRect frame = [view frame];
        NSRect bounds = [parent bounds];
        NSUInteger mask = [view autoresizingMask];
        double lowX = frame.origin.x - bounds.origin.x;
        autoresizingAxis(g.x, g.width, p.x, p.width, lowX, frame.size.width, bounds.size.width - lowX - frame.size.width,
                         mask & NSViewMinXMargin, mask & NSViewWidthSizable, mask & NSViewMaxXMargin);
        double nearY = frame.origin.y - bounds.origin.y;
        double farY = bounds.size.height - nearY - frame.size.height;
        // The solver's y axis follows the root; a superview flipped the other way sees its margins swapped.
        bool swapped = [parent isFlipped] != rootFlipped();
        if (!swapped)
            autoresizingAxis(g.y, g.height, p.y, p.height, nearY, frame.size.height, farY,
                             mask & NSViewMinYMargin, mask & NSViewHeightSizable, mask & NSViewMaxYMargin);
        else
            autoresizingAxis(g.y, g.height, p.y, p.height, farY, frame.size.height, nearY,
                             mask & NSViewMaxYMargin, mask & NSViewHeightSizable, mask & NSViewMinYMargin);
    }

private:
    void buildConstraints() {
        for (auto &entry : geometry) {
            NSView *view = entry.first;
            Geometry &g = entry.second;
            if (view == root && fitting) {
                add(g.width >= 0.0); add(g.height >= 0.0);
                intrinsic(view, g);
                continue;
            }
            NSRect frame = view == root ? [root bounds] : solverRect([view convertRect:[view bounds] toView:root]);
            if (view == root) {
                add(g.x == frame.origin.x); add(g.y == frame.origin.y);
                add(g.width == frame.size.width); add(g.height == frame.size.height);
            } else if ([view translatesAutoresizingMaskIntoConstraints] && [view superview] &&
                       geometry.count([view superview])) {
                autoresizing(view, g);
            } else if ([view translatesAutoresizingMaskIntoConstraints]) {
                add(g.x == frame.origin.x); add(g.y == frame.origin.y);
                add(g.width == frame.size.width); add(g.height == frame.size.height);
            } else {
                add(g.width >= 0.0); add(g.height >= 0.0);
                intrinsic(view, g);
            }
        }
        for (NSLayoutConstraint *constraint in constraints) {
            if (![constraint isActive]) continue;
            double priority = [constraint priority];
            if (!std::isfinite(priority) || priority <= 0 || priority > NSLayoutPriorityRequired)
                [NSException raise:NSInvalidArgumentException format:@"Invalid layout priority: %@", constraint];
            double strength = priority == NSLayoutPriorityRequired ? kiwi::strength::required : priority;
            kiwi::Expression expression = attribute([constraint firstItem], [constraint firstAttribute]);
            if ([constraint secondItem])
                expression = expression - attribute([constraint secondItem], [constraint secondAttribute]) * [constraint multiplier];
            expression = expression - [constraint constant];
            switch ([constraint relation]) {
            case NSLayoutRelationEqual: add((expression == 0.0) | strength, constraint); break;
            case NSLayoutRelationLessThanOrEqual: add((expression <= 0.0) | strength, constraint); break;
            case NSLayoutRelationGreaterThanOrEqual: add((expression >= 0.0) | strength, constraint); break;
            default: [NSException raise:NSInvalidArgumentException format:@"Invalid constraint relation: %@", constraint];
            }
        }
    }

    void applyResults() {
        // Convert every result before changing any ancestor frame.
        NSMutableArray *views = [NSMutableArray array];
        NSMutableArray *frames = [NSMutableArray array];
        for (NSView *view : traversal) {
            if (view == root || [view translatesAutoresizingMaskIntoConstraints]) continue;
            Geometry &g = geometry.at(view);
            NSRect absolute = NSMakeRect(g.x.value(), g.y.value(), g.width.value(), g.height.value());
            NSView *parent = [view superview];
            Geometry &p = geometry.at(parent);
            NSRect relative = NSMakeRect(absolute.origin.x - p.x.value(), absolute.origin.y - p.y.value(), absolute.size.width, absolute.size.height);
            if ([parent isFlipped] != [root isFlipped])
                relative.origin.y = p.height.value() - relative.origin.y - relative.size.height;
            relative.origin.x += [parent bounds].origin.x;
            relative.origin.y += [parent bounds].origin.y;
            [views addObject:view]; [frames addObject:[NSValue valueWithRect:relative]];
        }
        for (NSUInteger i = 0; i < [views count]; ++i)
            [[views objectAtIndex:i] setFrame:[[frames objectAtIndex:i] rectValue]];
    }
};
}

NSSize DarlingLayoutFittingSize(NSView *root) {
    try { return Layout(root, true).fittingSize(); }
    catch (const std::exception &error) {
        NSLog(@"Unable to simultaneously satisfy constraints: %s", error.what());
        return NSZeroSize;
    }
}

void DarlingLayoutSubtree(NSView *root) {
    try { Layout(root).run(); }
    catch (const std::exception &error) {
        NSLog(@"Unable to simultaneously satisfy constraints: %s", error.what());
    }
}

NSSize DarlingLayoutPreferredSize(NSView *root, NSSize currentSize) {
    NSSize result;
    try {
        if (Layout(root, true).preferredSize(currentSize, &result)) return result;
    } catch (const std::exception &error) {
        // The layout pass that follows reports the unsatisfiable constraints.
    }
    return currentSize;
}
