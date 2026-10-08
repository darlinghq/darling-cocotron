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
        switch (attr) {
        case NSLayoutAttributeLeft: return kiwi::Term(g.x);
        case NSLayoutAttributeRight: return g.x + g.width;
        case NSLayoutAttributeTop: return [root isFlipped] ? kiwi::Expression(kiwi::Term(g.y)) : g.y + g.height;
        case NSLayoutAttributeBottom: return [root isFlipped] ? g.y + g.height : kiwi::Expression(kiwi::Term(g.y));
        case NSLayoutAttributeWidth: return kiwi::Term(g.width);
        case NSLayoutAttributeHeight: return kiwi::Term(g.height);
        case NSLayoutAttributeCenterX: return g.x + g.width * 0.5;
        case NSLayoutAttributeCenterY: return g.y + g.height * 0.5;
        default:
            [NSException raise:NSInvalidArgumentException format:@"Unsupported layout attribute: %ld", (long)attr];
            return kiwi::Expression();
        }
    }

    void add(const kiwi::Constraint &constraint) {
        if (constraint.strength() == kiwi::strength::required)
            solver.addConstraint(constraint);
        else
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
        kiwi::Variable dimensions[] = {g.width, g.height};
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
    explicit Layout(NSView *view) : root(view), constraints([[NSMutableArray alloc] init]) {}
    ~Layout() { [constraints release]; }
    void run() {
        collect(root);
        if ([constraints count] == 0) return;
        for (auto &entry : geometry) {
            NSView *view = entry.first;
            Geometry &g = entry.second;
            NSRect frame = view == root ? [root bounds] : [view convertRect:[view bounds] toView:root];
            add(g.width >= 0.0); add(g.height >= 0.0);
            if (view == root || [view translatesAutoresizingMaskIntoConstraints]) {
                add(g.x == frame.origin.x); add(g.y == frame.origin.y);
                add(g.width == frame.size.width); add(g.height == frame.size.height);
            } else {
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
            case NSLayoutRelationEqual: add((expression == 0.0) | strength); break;
            case NSLayoutRelationLessThanOrEqual: add((expression <= 0.0) | strength); break;
            case NSLayoutRelationGreaterThanOrEqual: add((expression >= 0.0) | strength); break;
            default: [NSException raise:NSInvalidArgumentException format:@"Invalid constraint relation: %@", constraint];
            }
        }
        solvePriorities();
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

void DarlingLayoutSubtree(NSView *root) {
    try { Layout(root).run(); }
    catch (const std::exception &error) {
        [NSException raise:NSInternalInconsistencyException format:@"Constraint solver failed: %s", error.what()];
    }
}
