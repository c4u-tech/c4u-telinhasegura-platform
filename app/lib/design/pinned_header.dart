import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A sliver that keeps [child] at the top of its scroll view while the
/// content scrolls beneath it, as long as the child takes at most half the
/// view's height; taller (a short window, large text) it scrolls with the
/// content, so the content always keeps at least half the height. The
/// child paints its own ground, since content passes beneath it. While
/// content is under it, a one-pixel line in [edge] marks its lower edge.
class PinnedHeader extends SingleChildRenderObjectWidget {
  const PinnedHeader({super.key, required this.edge, required super.child});

  final Color edge;

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

class RenderPinnedHeader extends RenderSliverSingleBoxAdapter {
  RenderPinnedHeader({required this._edge});

  Color _edge;
  set edge(Color value) {
    if (value == _edge) return;
    _edge = value;
    markNeedsPaint();
  }

  /// Whether the child stays at the top, decided at each layout from the
  /// child's height and the view's.
  bool get pinned => _pinned;
  bool _pinned = false;

  /// Whether content is scrolled under the pinned child.
  bool get _covering => _pinned && constraints.scrollOffset > 0;

  @override
  double childMainAxisPosition(covariant RenderObject child) =>
      _pinned ? 0 : -constraints.scrollOffset;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      geometry = SliverGeometry.zero;
      return;
    }
    final constraints = this.constraints;
    child.layout(constraints.asBoxConstraints(), parentUsesSize: true);
    final extent = child.size.height;
    _pinned = extent <= constraints.viewportMainAxisExtent / 2;
    if (_pinned) {
      final paintExtent = math.min(
        extent,
        constraints.remainingPaintExtent - constraints.overlap,
      );
      geometry = SliverGeometry(
        scrollExtent: extent,
        paintOrigin: constraints.overlap,
        paintExtent: paintExtent,
        layoutExtent: clampDouble(
          extent - constraints.scrollOffset,
          0,
          constraints.remainingPaintExtent,
        ),
        maxPaintExtent: extent,
        // A widget brought into view is placed below the child, not under.
        maxScrollObstructionExtent: extent,
        cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
        hasVisualOverflow: true,
      );
      (child.parentData! as SliverPhysicalParentData).paintOffset = Offset.zero;
      return;
    }
    final painted = calculatePaintOffset(constraints, from: 0, to: extent);
    geometry = SliverGeometry(
      scrollExtent: extent,
      paintExtent: painted,
      maxPaintExtent: extent,
      hitTestExtent: painted,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: extent),
      hasVisualOverflow:
          extent > constraints.remainingPaintExtent ||
          constraints.scrollOffset > 0,
    );
    setChildParentData(child, constraints, geometry!);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final geometry = this.geometry;
    if (!_covering || geometry == null || geometry.paintExtent <= 0) return;
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
    // Pinned over content, it is not part of what scrolls.
    if (_covering) {
      config.addTagForChildren(RenderViewport.excludeFromScrolling);
    }
  }
}
