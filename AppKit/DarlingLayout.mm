#import "DarlingLayout.h"
#import <AppKit/NSLayoutConstraint.h>
#import <AppKit/NSLayoutGuide.h>
#import "NSViewLayoutInternal.h"
#import <Foundation/NSException.h>
#import <objc/runtime.h>
#include "third_party/kiwi/kiwi.h"
#include <map>
#include <set>
#include <vector>
#include <cmath>

// Layout guides take part as rectangles without a view. The solved frame
// is set on the guide, measured from its owning view's own origin.
@interface NSLayoutGuide (DarlingLayout)
- (void) setFrame: (NSRect) frame;
@end

static uint64_t layoutGeneration = 1;
static NSView *viewBeingPlaced;

void DarlingLayoutInputsChanged(void) {
    __atomic_add_fetch(&layoutGeneration, 1, __ATOMIC_RELAXED);
}

uint64_t DarlingLayoutGeneration(void) {
    return __atomic_load_n(&layoutGeneration, __ATOMIC_RELAXED);
}

BOOL DarlingLayoutIsPlacing(NSView *view) {
    return viewBeingPlaced != nil && view != nil && (view == viewBeingPlaced || [view isDescendantOf:viewBeingPlaced]);
}

namespace {
struct Geometry { kiwi::Variable x, y, width, height; };

// Identifies a required constraint from one pass to the next: the NSLayoutConstraint it stands
// for, or the item a generated constraint (frame, autoresizing, size floor) belongs to and its
// place among that item's generated constraints.
struct Key {
    void *owner;
    int ordinal;
    bool operator<(const Key &other) const {
        return owner != other.owner ? owner < other.owner : ordinal < other.ordinal;
    }
};

// kiwi reduces expressions to one term per variable, ordered by variable, so equal constraints
// have equal term lists.
bool sameConstraint(const kiwi::Constraint &a, const kiwi::Constraint &b) {
    if (a.op() != b.op() || a.strength() != b.strength())
        return false;
    const kiwi::Expression &first = a.expression(), &second = b.expression();
    if (first.constant() != second.constant() || first.terms().size() != second.terms().size())
        return false;
    for (size_t i = 0; i < first.terms().size(); ++i) {
        const kiwi::Term &one = first.terms()[i], &other = second.terms()[i];
        if (!one.variable().equals(other.variable()) || one.coefficient() != other.coefficient())
            return false;
    }
    return true;
}

// The root's size follows its bounds through edit variables; they are as strong as an optional
// constraint can be, so only a required constraint can move the root, and a pass that sees the root
// moved knows the required constraints conflict with its frame.
const double rootSizeStrength = kiwi::strength::create(999.0, 1000.0, 1000.0);

// Whether an optional constraint is met by the solver's current values.
bool satisfied(const kiwi::Constraint &constraint) {
    double residual = constraint.expression().value();
    return kiwi::impl::nearZero(residual) ||
        (constraint.op() == kiwi::OP_LE && residual < 0) ||
        (constraint.op() == kiwi::OP_GE && residual > 0);
}

// A constraint solver for one view's subtree that is kept from one pass to the next. Each pass
// derives all constraints from the views again, but only the ones that changed are removed from
// and added to the solver, and the root's size is suggested to its edit variables.
//
// Optional constraints are meant to be met by priority: a lower priority never at the expense of
// a higher one. The kept solver weighs them by their priority instead, which gives the same
// result whenever it leaves only constraints of the lowest priority unmet (every higher priority
// is then met completely, and the lowest one is unmet as little as possible). Otherwise the pass
// is solved again from scratch one priority after the other.
//
// The vertical axis runs downwards from the root's top edge whatever the root's flippedness,
// so that a change of the root's height leaves the constraints of its subtree as they are.
class Engine {
public:
    enum Mode { LayoutMode, FitMode };

    explicit Engine(Mode mode) : mode(mode) {}

    bool busy = false;

    // Solves with the root held at its bounds and sets the frames of the views laid out with
    // constraints, and of layout guides.
    void layout(NSView *view) {
        Pass pass(*this, view);
        if ([constraints count] == 0) { pass.done = true; return; }
        solve();
        applyResults();
        removeFrozen();
        pass.done = true;
    }

    // The root's size when it is pulled towards target at the given priority instead of being
    // held at its bounds. No view is changed. Returns false when the subtree has no constraints
    // and onlyWithConstraints is set.
    bool fit(NSView *view, NSSize target, double priority, bool onlyWithConstraints, NSSize *result) {
        Pass pass(*this, view);
        if (onlyWithConstraints && [constraints count] == 0) { pass.done = true; return false; }
        this->target = target;
        targetPriority = priority;
        solve();
        Geometry &g = geometry.at(root);
        *result = NSMakeSize(g.width.value(), g.height.value());
        removeFrozen();
        pass.done = true;
        return true;
    }

private:
    Mode mode;
    kiwi::Solver solver;
    // The views and layout guides of the subtree, each a rectangle in the solver's coordinates.
    std::map<id, Geometry> geometry;
    // The constraints in the solver.
    std::map<Key, kiwi::Constraint> installed;
    int passesFromScratch = 0; // after a pass that needed it, the next ones start from scratch
    bool editing = false;     // the root's size edit variables are in the solver
    bool rebuilt = false;     // the solver holds a full rebuild, not the incremental state
    bool conflicted = false;  // the last pass had to break a required constraint
    size_t retired = 0;       // items dropped since the solver was made

    // Per pass.
    NSView *root = nil;
    std::vector<NSView *> traversal;
    std::vector<NSLayoutGuide *> guides;
    std::set<id> seen;
    NSMutableArray *constraints = nil;
    struct Item { Key key; kiwi::Constraint constraint; NSLayoutConstraint *source; };
    std::vector<Item> required, soft;
    std::vector<kiwi::Constraint> rootSize;
    std::map<double, std::vector<kiwi::Constraint>, std::greater<double>> optional;
    std::vector<kiwi::Constraint> frozen;
    id generatedOwner = nil;
    int generatedOrdinal = 0;
    NSSize target = NSZeroSize;
    double targetPriority = 0;

    // Sets up and tears down one pass. A pass that ends with an exception leaves the solver in an
    // unknown state, so it is made again from scratch the next time.
    struct Pass {
        Engine &engine;
        bool done = false;
        Pass(Engine &engine, NSView *view) : engine(engine) {
            engine.busy = true;
            engine.begin(view);
        }
        ~Pass() {
            if (!done)
                engine.reset();
            engine.end();
            engine.busy = false;
        }
    };

    void begin(NSView *view) {
        root = view;
        constraints = [[NSMutableArray alloc] init];
        collect(root);
    }

    void end() {
        // Items that left the subtree take nothing in the solver any more: every constraint that
        // mentions them was derived from the subtree, and has been removed.
        for (auto entry = geometry.begin(); entry != geometry.end();) {
            if (seen.count(entry->first)) { ++entry; continue; }
            entry = geometry.erase(entry);
            ++retired;
        }
        [constraints release];
        constraints = nil;
        root = nil;
        traversal.clear(); guides.clear(); seen.clear();
        required.clear(); soft.clear(); rootSize.clear(); optional.clear();
    }

    void reset() {
        solver.reset();
        installed.clear();
        frozen.clear();
        editing = false;
        rebuilt = false;
    }

    void collect(NSView *view) {
        geometry.emplace(view, Geometry());
        seen.insert(view);
        traversal.push_back(view);
        [constraints addObjectsFromArray:[view constraints]];
        for (NSLayoutGuide *guide in [view layoutGuides]) {
            geometry.emplace(guide, Geometry());
            seen.insert(guide);
            guides.push_back(guide);
        }
        for (NSView *child in [view subviews]) collect(child);
    }

    // Maps a rectangle in the root's coordinates to the solver's.
    NSRect solverRect(NSRect rect) const {
        if (![root isFlipped])
            rect.origin.y = NSMaxY([root bounds]) - NSMaxY(rect);
        return rect;
    }

    // The edges and sizes layout constraints refer to are those of the view's
    // alignment rectangle: the frame less the alignment insets.
    kiwi::Expression attribute(id item, NSInteger attr) {
        auto found = geometry.find(item);
        if (found == geometry.end() || !seen.count(item))
            [NSException raise:NSInvalidArgumentException format:@"Layout item is outside the view tree: %@", item];
        Geometry &g = found->second;
        bool isGuide = [item isKindOfClass:[NSLayoutGuide class]];
        NSView *view = isGuide ? [(NSLayoutGuide *)item owningView] : (NSView *)item;
        if (attr == NSLayoutAttributeLeading || attr == NSLayoutAttributeTrailing) {
            bool rtl = [view userInterfaceLayoutDirection] == NSUserInterfaceLayoutDirectionRightToLeft;
            if (attr == NSLayoutAttributeLeading)
                attr = rtl ? NSLayoutAttributeRight : NSLayoutAttributeLeft;
            else
                attr = rtl ? NSLayoutAttributeLeft : NSLayoutAttributeRight;
        }
        NSEdgeInsets insets = isGuide ? NSEdgeInsetsMake(0, 0, 0, 0) : [view alignmentRectInsets];
        // Insets name the visual sides; y runs downwards in the solver.
        kiwi::Expression left = g.x + insets.left;
        kiwi::Expression right = g.x + g.width - insets.right;
        kiwi::Expression above = g.y + insets.top;
        kiwi::Expression below = g.y + g.height - insets.bottom;
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
            if (isGuide) break;
            return above + [view firstBaselineOffsetFromTop];
        case NSLayoutAttributeLastBaseline:
            if (isGuide) break;
            return below - [view lastBaselineOffsetFromBottom];
        default:
            break;
        }
        [NSException raise:NSInvalidArgumentException format:@"Unsupported layout attribute: %ld", (long)attr];
        return kiwi::Expression();
    }

    // Records a constraint of the pass; an optional one has its priority as strength. `source`
    // is the constraint it stands for, nil for a generated one.
    void add(const kiwi::Constraint &constraint, NSLayoutConstraint *source = nil) {
        Key key = source ? Key{source, 0} : Key{generatedOwner, generatedOrdinal++};
        if (constraint.strength() == kiwi::strength::required) {
            required.push_back(Item{key, constraint, source});
        } else {
            optional[constraint.strength()].push_back(constraint);
            soft.push_back(Item{key, constraint, source});
        }
    }

    void intrinsic(NSView *view, Geometry &g) {
        NSSize size = [view _intrinsicContentSizeForLayout];
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
        // The solver's y axis runs downwards; an unflipped superview sees its margins swapped.
        if ([parent isFlipped])
            autoresizingAxis(g.y, g.height, p.y, p.height, nearY, frame.size.height, farY,
                             mask & NSViewMinYMargin, mask & NSViewHeightSizable, mask & NSViewMaxYMargin);
        else
            autoresizingAxis(g.y, g.height, p.y, p.height, farY, frame.size.height, nearY,
                             mask & NSViewMaxYMargin, mask & NSViewHeightSizable, mask & NSViewMinYMargin);
    }

    void build() {
        for (NSView *view : traversal) {
            Geometry &g = geometry.at(view);
            generatedOwner = view;
            generatedOrdinal = 0;
            if (view == root) {
                if (mode == FitMode) {
                    add(g.x == 0.0); add(g.y == 0.0);
                    add(g.width >= 0.0); add(g.height >= 0.0);
                    intrinsic(view, g);
                } else {
                    NSRect bounds = [root bounds];
                    add(g.x == bounds.origin.x); add(g.y == ([root isFlipped] ? bounds.origin.y : 0.0));
                    rootSize.push_back(g.width == bounds.size.width);
                    rootSize.push_back(g.height == bounds.size.height);
                }
            } else if ([view translatesAutoresizingMaskIntoConstraints] && [view superview] &&
                       seen.count([view superview])) {
                autoresizing(view, g);
            } else if ([view translatesAutoresizingMaskIntoConstraints]) {
                NSRect frame = solverRect([view convertRect:[view bounds] toView:root]);
                add(g.x == frame.origin.x); add(g.y == frame.origin.y);
                add(g.width == frame.size.width); add(g.height == frame.size.height);
            } else {
                add(g.width >= 0.0); add(g.height >= 0.0);
                intrinsic(view, g);
            }
        }
        for (NSLayoutGuide *guide : guides) {
            Geometry &g = geometry.at(guide);
            generatedOwner = guide;
            generatedOrdinal = 0;
            add(g.width >= 0.0); add(g.height >= 0.0);
        }
        generatedOwner = nil;
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
        if (mode == FitMode) {
            Geometry &g = geometry.at(root);
            generatedOwner = root;
            generatedOrdinal = 1000;
            add((g.width == (double)target.width) | targetPriority);
            add((g.height == (double)target.height) | targetPriority);
        }
    }

    void solve() {
        build();
        // A conflict is resolved by the full rebuild, which breaks the constraints that come
        // last, as long as the conflict lasts.
        if (conflicted || passesFromScratch > 0) {
            if (passesFromScratch > 0) --passesFromScratch;
            solveFromScratch();
        } else if (!solveIncrementally()) {
            solveFromScratch();
        }
    }

    // Brings the solver's required constraints and root size up to date with this pass's and
    // solves. Returns false, with the solver in an unknown state, when the required
    // constraints conflict.
    bool solveIncrementally() {
        // Variables of dropped items stay in the solver; make it again once they add up.
        if (rebuilt || retired > 256 + geometry.size()) {
            reset();
            retired = 0;
        }
        std::map<Key, const kiwi::Constraint *> wanted;
        for (const Item &item : required) wanted.emplace(item.key, &item.constraint);
        for (const Item &item : soft) wanted.emplace(item.key, &item.constraint);
        for (auto entry = installed.begin(); entry != installed.end();) {
            auto found = wanted.find(entry->first);
            if (found != wanted.end() && sameConstraint(*found->second, entry->second)) {
                ++entry;
                continue;
            }
            solver.removeConstraint(entry->second);
            entry = installed.erase(entry);
        }
        try {
            for (const std::vector<Item> *items : {&required, &soft}) {
                for (const Item &item : *items) {
                    if (installed.count(item.key)) continue;
                    solver.addConstraint(item.constraint);
                    installed.emplace(item.key, item.constraint);
                }
            }
        } catch (const kiwi::UnsatisfiableConstraint &) {
            return false;
        }
        if (mode == LayoutMode) {
            Geometry &g = geometry.at(root);
            if (!editing) {
                solver.addEditVariable(g.width, rootSizeStrength);
                solver.addEditVariable(g.height, rootSizeStrength);
                editing = true;
            }
            NSSize size = [root bounds].size;
            solver.suggestValue(g.width, size.width);
            solver.suggestValue(g.height, size.height);
        }
        solver.updateVariables();
        if (!optional.empty()) {
            double lowest = optional.rbegin()->first;
            for (const auto &tier : optional) {
                if (tier.first == lowest) break;
                for (const auto &constraint : tier.second) {
                    if (!satisfied(constraint)) {
                        passesFromScratch = 8;
                        return false;
                    }
                }
            }
        }
        if (mode == LayoutMode) {
            Geometry &g = geometry.at(root);
            NSSize size = [root bounds].size;
            if (std::fabs(g.width.value() - size.width) > 1e-6 * std::fmax(1.0, std::fabs(size.width)) ||
                std::fabs(g.height.value() - size.height) > 1e-6 * std::fmax(1.0, std::fabs(size.height)))
                return false;
        }
        return true;
    }

    // Adds every constraint to an empty solver in order. A required constraint that conflicts
    // with the ones added before it is broken: the layout goes on without it and the conflict is
    // logged, rather than the whole layout being abandoned.
    void solveFromScratch() {
        reset();
        retired = 0;
        rebuilt = true;
        conflicted = false;
        auto addRequired = [&](const kiwi::Constraint &constraint, NSLayoutConstraint *source) {
            try {
                solver.addConstraint(constraint);
            } catch (const kiwi::UnsatisfiableConstraint &) {
                conflicted = true;
                NSLog(@"Unable to simultaneously satisfy constraints. Will attempt to recover by breaking constraint %@",
                      source ? [source description] : @"(a view frame)");
            }
        };
        for (const kiwi::Constraint &constraint : rootSize)
            addRequired(constraint, nil);
        for (const Item &item : required)
            addRequired(item.constraint, item.source);
        solvePriorities();
    }

    // Solves the optional constraints from the highest priority down. Each priority is solved
    // with the higher ones fixed at what they reached: satisfied ones become required, and
    // unsatisfied ones keep the residual they were left with. Those fixes stay until removeFrozen.
    void solvePriorities() {
        for (auto &tier : optional) {
            std::vector<kiwi::Constraint> soft;
            soft.reserve(tier.second.size());
            for (const auto &constraint : tier.second) {
                soft.push_back(constraint | 1.0);
                solver.addConstraint(soft.back());
            }
            solver.updateVariables();
            size_t firstFrozen = frozen.size();
            for (const auto &constraint : tier.second) {
                if (satisfied(constraint))
                    frozen.push_back(constraint | kiwi::strength::required);
                else
                    frozen.push_back(constraint.expression() == constraint.expression().value());
            }
            for (const auto &constraint : soft) solver.removeConstraint(constraint);
            for (size_t i = firstFrozen; i < frozen.size(); ++i) solver.addConstraint(frozen[i]);
        }
        solver.updateVariables();
    }

    void removeFrozen() {
        if (rebuilt) {
            // the next pass starts from scratch anyway
            frozen.clear();
            return;
        }
        for (const auto &constraint : frozen) solver.removeConstraint(constraint);
        frozen.clear();
    }

    void applyResults() {
        // Convert every result before changing any ancestor frame.
        std::vector<std::pair<NSView *, NSRect>> frames;
        for (NSView *view : traversal) {
            if (view == root || [view translatesAutoresizingMaskIntoConstraints]) continue;
            Geometry &g = geometry.at(view);
            NSView *parent = [view superview];
            Geometry &p = geometry.at(parent);
            NSRect relative = NSMakeRect(g.x.value() - p.x.value(), g.y.value() - p.y.value(),
                                         g.width.value(), g.height.value());
            if (![parent isFlipped])
                relative.origin.y = p.height.value() - relative.origin.y - relative.size.height;
            relative.origin.x += [parent bounds].origin.x;
            relative.origin.y += [parent bounds].origin.y;
            frames.push_back(std::make_pair(view, relative));
        }
        NSMutableArray *keep = [NSMutableArray arrayWithCapacity:frames.size()];
        for (auto &entry : frames) [keep addObject:entry.first];
        for (auto &entry : frames) {
            // The frames set here are the result of this pass, not new input to the next one.
            NSView *previous = viewBeingPlaced;
            viewBeingPlaced = entry.first;
            @try {
                [entry.first setFrame:entry.second];
            } @finally {
                viewBeingPlaced = previous;
            }
        }
        for (NSLayoutGuide *guide : guides) {
            NSView *owner = [guide owningView];
            if (owner == nil || !seen.count(owner)) continue;
            Geometry &g = geometry.at(guide), &p = geometry.at(owner);
            NSRect relative = NSMakeRect(g.x.value() - p.x.value(), g.y.value() - p.y.value(), g.width.value(), g.height.value());
            if (![owner isFlipped])
                relative.origin.y = p.height.value() - relative.origin.y - relative.size.height;
            [guide setFrame:relative];
        }
    }
};
}

@interface _NSViewLayoutEngines : NSObject {
@public
    Engine *layout;
    Engine *fit;
    uint64_t generations[2];
}
@end

@implementation _NSViewLayoutEngines
- (void) dealloc {
    delete layout;
    delete fit;
    [super dealloc];
}
@end

static char layoutEnginesKey;

static _NSViewLayoutEngines *layoutEngines(NSView *view, bool create) {
    _NSViewLayoutEngines *engines = objc_getAssociatedObject(view, &layoutEnginesKey);
    if (engines == nil && create) {
        engines = [[_NSViewLayoutEngines alloc] init];
        objc_setAssociatedObject(view, &layoutEnginesKey, engines, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [engines release];
    }
    return engines;
}

// The view's engine of the given kind, or a temporary one (deleted by the caller) when the
// persistent one is in the middle of a pass further up the stack.
static Engine *engineFor(NSView *view, Engine::Mode mode, bool *temporary) {
    _NSViewLayoutEngines *engines = layoutEngines(view, true);
    Engine *&engine = mode == Engine::LayoutMode ? engines->layout : engines->fit;
    if (engine == nullptr)
        engine = new Engine(mode);
    *temporary = engine->busy;
    return engine->busy ? new Engine(mode) : engine;
}

uint64_t DarlingLayoutLastGeneration(NSView *root, DarlingLayoutKind kind) {
    _NSViewLayoutEngines *engines = layoutEngines(root, false);
    return engines ? engines->generations[kind] : 0;
}

void DarlingLayoutSetLastGeneration(NSView *root, DarlingLayoutKind kind, uint64_t generation) {
    layoutEngines(root, true)->generations[kind] = generation;
}

NSSize DarlingLayoutFittingSize(NSView *root) {
    bool temporary;
    Engine *engine = engineFor(root, Engine::FitMode, &temporary);
    NSSize result = NSZeroSize;
    try { engine->fit(root, NSZeroSize, NSLayoutPriorityFittingSizeCompression, false, &result); }
    catch (const std::exception &error) {
        NSLog(@"Unable to simultaneously satisfy constraints: %s", error.what());
        result = NSZeroSize;
    }
    if (temporary) delete engine;
    return result;
}

void DarlingLayoutSubtree(NSView *root) {
    bool temporary;
    Engine *engine = engineFor(root, Engine::LayoutMode, &temporary);
    try { engine->layout(root); }
    catch (const std::exception &error) {
        NSLog(@"Unable to simultaneously satisfy constraints: %s", error.what());
    }
    if (temporary) delete engine;
}

NSSize DarlingLayoutPreferredSize(NSView *root, NSSize currentSize) {
    bool temporary;
    Engine *engine = engineFor(root, Engine::FitMode, &temporary);
    NSSize result = currentSize;
    try {
        if (!engine->fit(root, currentSize, NSLayoutPriorityWindowSizeStayPut, true, &result))
            result = currentSize;
    } catch (const std::exception &error) {
        // The layout pass that follows reports the unsatisfiable constraints.
        result = currentSize;
    }
    if (temporary) delete engine;
    return result;
}
