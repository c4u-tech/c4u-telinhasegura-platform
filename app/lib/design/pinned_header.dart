import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The places of a [PinnedHeader]: its lead and its child.
enum PinnedSlot { lead, child }

/// How much of a [PinnedHeader] stays at the top.
enum PinnedPart {
  /// The lead and the child.
  both,

  /// The child only: the lead scrolls away above it.
  child,

  /// Nothing: both scroll with the content.
  none,
}

/// A sliver that keeps [child] at the top of its scroll view while the
/// content scrolls beneath it, with an optional [lead] above it (a screen's
/// band over what is watched), so the content always keeps at least half
/// the view's height: the lead and the child stay when together they take
/// at most half; else the lead scrolls away and the child stays, when it
/// alone takes at most half; else both scroll with the content (a short
/// window, large text). Each paints its own ground, since content passes
/// beneath it. While content is under it, a one-pixel line in [edge] marks
/// its lower edge.
class PinnedHeader
    extends SlottedMultiChildRenderObjectWidget<PinnedSlot, RenderBox> {
  const PinnedHeader({
    super.key,
    required this.edge,
    this.lead,
    required this.child,
  });

  final Color edge;
  final Widget? lead;
  final Widget child;

  @override
  Iterable<PinnedSlot> get slots => PinnedSlot.values;

  @override
  Widget? childForSlot(PinnedSlot slot) => switch (slot) {
    PinnedSlot.lead => lead,
    PinnedSlot.child => child,
  };

  @override
  RenderPinnedHeader createRenderObject(BuildContext context) =>
      RenderPinnedHeader(edge: edge);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPinnedHeader renderObject,
  ) {
    renderObject.edge = edge;
  }
}

class RenderPinnedHeader extends RenderSliver
    with
        SlottedContainerRenderObjectMixin<PinnedSlot, RenderBox>,
        RenderSliverHelpers {
  RenderPinnedHeader({required this._edge});

  Color _edge;
  set edge(Color value) {
    if (value == _edge) return;
    _edge = value;
    markNeedsPaint();
  }

  RenderBox? get _lead => childForSlot(PinnedSlot.lead);
  RenderBox? get _child => childForSlot(PinnedSlot.child);

  /// What stays at the top, decided at each layout from the children's
  /// heights and the view's.
  PinnedPart get pinned => _pinned;
  PinnedPart _pinned = PinnedPart.none;

  double _leadExtent = 0;
  double _childExtent = 0;

  /// Whether content is scrolled under what stays.
  bool get _covering => switch (_pinned) {
    PinnedPart.both => constraints.scrollOffset > 0,
    PinnedPart.child => constraints.scrollOffset > _leadExtent,
    PinnedPart.none => false,
  };

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverPhysicalParentData) {
      child.parentData = SliverPhysicalParentData();
    }
  }

  @override
  double childMainAxisPosition(covariant RenderBox child) {
    final s = constraints.scrollOffset;
    if (child == _lead) return _pinned == PinnedPart.both ? 0 : -s;
    return switch (_pinned) {
      PinnedPart.both => _leadExtent,
      PinnedPart.child => math.max(_leadExtent - s, 0),
      PinnedPart.none => _leadExtent - s,
    };
  }

  @override
  double childCrossAxisPosition(covariant RenderBox child) => 0;

  @override
  double childScrollOffset(covariant RenderObject child) =>
      child == _lead ? 0 : _leadExtent;

  @override
  void performLayout() {
    final constraints = this.constraints;
    assert(constraints.axisDirection == AxisDirection.down);
    final box = constraints.asBoxConstraints();
    final lead = _lead;
    final child = _child;
    lead?.layout(box, parentUsesSize: true);
    child?.layout(box, parentUsesSize: true);
    _leadExtent = lead?.size.height ?? 0;
    _childExtent = child?.size.height ?? 0;
    final extent = _leadExtent + _childExtent;
    if (extent == 0) {
      _pinned = PinnedPart.none;
      geometry = SliverGeometry.zero;
      return;
    }
    final half = constraints.viewportMainAxisExtent / 2;
    _pinned = extent <= half
        ? PinnedPart.both
        : _childExtent <= half
        ? PinnedPart.child
        : PinnedPart.none;
    final s = constraints.scrollOffset;
    final cache = calculateCacheOffset(constraints, from: 0, to: extent);
    if (_pinned == PinnedPart.none) {
      final painted = calculatePaintOffset(constraints, from: 0, to: extent);
      geometry = SliverGeometry(
        scrollExtent: extent,
        paintExtent: painted,
        maxPaintExtent: extent,
        hitTestExtent: painted,
        cacheExtent: cache,
        hasVisualOverflow: extent > constraints.remainingPaintExtent || s > 0,
      );
      return;
    }
    // What stays: all of it, or the child under what is left of the lead.
    final kept = _pinned == PinnedPart.both
        ? extent
        : math.max(_leadExtent - s, 0) + _childExtent;
    final available = constraints.remainingPaintExtent - constraints.overlap;
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintOrigin: constraints.overlap,
      paintExtent: math.min(kept, available),
      layoutExtent: clampDouble(
        extent - s,
        0,
        math.min(kept, constraints.remainingPaintExtent),
      ),
      maxPaintExtent: extent,
      // A widget brought into view is placed below what stays, not under.
      maxScrollObstructionExtent: _pinned == PinnedPart.both
          ? extent
          : _childExtent,
      cacheExtent: cache,
      hasVisualOverflow: true,
    );
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) =>
      applyPaintTransformForBoxChild(child as RenderBox, transform);

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    final boxResult = BoxHitTestResult.wrap(result);
    for (final child in [?_child, ?_lead]) {
      if (hitTestBoxChild(
        boxResult,
        child,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
      )) {
        return true;
      }
    }
    return false;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final geometry = this.geometry;
    if (geometry == null || !geometry.visible) return;
    for (final child in [?_lead, ?_child]) {
      final y = childMainAxisPosition(child);
      if (y + child.size.height <= 0 || y >= geometry.paintExtent) continue;
      context.paintChild(child, offset + Offset(0, y));
    }
    if (!_covering || geometry.paintExtent <= 0) return;
    context.canvas.drawRect(
      Rect.fromLTWH(
        offset.dx,
        offset.dy + geometry.paintExtent - 1,
        constraints.crossAxisExtent,
        1,
      ),
      Paint()..color = _edge,
    );
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // What stays over content is not part of what scrolls.
    if (_covering) {
      config.addTagForChildren(RenderViewport.excludeFromScrolling);
    }
  }
}
