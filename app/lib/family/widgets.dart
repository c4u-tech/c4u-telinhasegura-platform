import 'package:flutter/material.dart';

import '../access/copy.dart';
import '../access/widgets.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'family_model.dart';

/// A bounded set shown as the mark's own modules: one per place, filled
/// when taken, hollow when free, with [words] on their own line under
/// them stating the same count. One layout at every width and text
/// size, so the doors' rows read alike. Assistive technology reads the
/// words only.
class CapacityRow extends StatelessWidget {
  const CapacityRow({
    super.key,
    required this.filled,
    required this.total,
    required this.words,
  });

  final int filled;
  final int total;
  final String words;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: words,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: Space.xs),
                StateModule(filled: i < filled),
              ],
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            words,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.palette.muted),
          ),
        ],
      ),
    ),
  );
}

/// A door of the family home: a full-width row on the ground with its
/// [title], optional content below it, and a chevron; an optional
/// [leading] mark (a child's avatar) sits before the title. The whole row
/// is the target. Its content is visual only, so [semanticsLabel] (the title by
/// default) must say what the content shows. While [busy] (a write on
/// what the row names) it shows progress in place of the chevron and
/// waits. Without [onTap] it is a row nobody acts on: the same height and
/// rhythm, no chevron, and no target. With [errorText] the row is a
/// field in error: its title and chevron in clay (ember on dark), the
/// words in body-small clay under its content, read with the row and
/// announced. [titleMaxLines] caps a long title (a video's), ending it
/// with an ellipsis; the semantics label still says it whole.
class DoorRow extends StatefulWidget {
  const DoorRow({
    super.key,
    required this.title,
    required this.onTap,
    this.semanticsLabel,
    this.leading,
    this.child,
    this.busy = false,
    this.errorText,
    this.titleMaxLines,
    this.link = false,
  });

  final String title;

  /// Whether [onTap] opens a page outside the app: the row then reads as
  /// a link rather than a button.
  final bool link;
  final int? titleMaxLines;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final Widget? leading;
  final Widget? child;
  final bool busy;
  final String? errorText;

  @override
  State<DoorRow> createState() => _DoorRowState();
}

class _DoorRowState extends State<DoorRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.small),
    );
    final ring = _focused ? focusRing(p).resolve({WidgetState.focused}) : null;
    final onTap = widget.onTap;
    final error = widget.errorText;
    final label = [widget.semanticsLabel ?? widget.title, ?error].join(', ');
    final row = ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.lg),
          child: Row(
            children: [
              if (widget.leading case final leading?) ...[
                leading,
                const SizedBox(width: Space.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: widget.titleMaxLines,
                      overflow: widget.titleMaxLines == null
                          ? null
                          : TextOverflow.ellipsis,
                      style: error == null
                          ? text.titleMedium
                          : text.titleMedium?.copyWith(color: p.error),
                    ),
                    if (widget.child case final child?) ...[
                      const SizedBox(height: Space.sm),
                      child,
                    ],
                    if (error != null) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        error,
                        style: text.bodySmall?.copyWith(color: p.error),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: Space.md),
                if (widget.busy)
                  SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: p.text,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: error == null ? p.muted : p.error,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (onTap == null) {
      return Semantics(
        container: true,
        liveRegion: error != null,
        label: label,
        child: row,
      );
    }
    return Semantics(
      container: true,
      button: !widget.link,
      link: widget.link,
      enabled: !widget.busy,
      liveRegion: error != null,
      label: label,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape.copyWith(side: ring ?? BorderSide.none),
        ),
        child: InkWell(
          onTap: widget.busy ? null : onTap,
          onFocusChange: (focused) => setState(() => _focused = focused),
          customBorder: shape,
          focusColor: Colors.transparent,
          hoverColor: p.outline.withValues(alpha: .08),
          highlightColor: p.outline.withValues(alpha: .12),
          splashColor: p.outline.withValues(alpha: .12),
          child: row,
        ),
      ),
    );
  }
}

/// The home's doors, divided by hairlines above, between and below.
class Doors extends StatelessWidget {
  const Doors({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final hairline = Divider(
      height: 1,
      thickness: 1,
      color: context.palette.outline.withValues(alpha: .5),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hairline,
        for (final door in children) ...[door, hairline],
      ],
    );
  }
}

/// A read row ending on a figure:
/// [label] in body-large on the left, [figure] on the right in
/// tabular figures, at least 48 dp with 12 px above and below, between
/// the door rows' hairlines. Where the two cannot share the line (200 %
/// text), the figure goes under its label. Read as one line, "‹label›,
/// ‹figure›"; never a target.
class FigureRow extends StatelessWidget {
  const FigureRow({super.key, required this.label, required this.figure});

  final String label;
  final String figure;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyLarge;
    return Semantics(
      container: true,
      label: '$label, $figure',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Space.md,
                runSpacing: Space.xs,
                children: [
                  Text(label, style: body),
                  Text(
                    figure,
                    style: body?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a family screen shows until its family is ready: the placeholder
/// rows, or a failed read with "Tentar de novo".
List<Widget> familyPending(FamilyModel model) => switch (model.state) {
  FamilyFailed() => [
    const ErrorNote(Copy.genericRetry),
    const SizedBox(height: Space.lg),
    PrimaryButton(label: 'Tentar de novo', onPressed: model.refresh),
  ],
  _ => const [FamilyPlaceholder()],
};

/// Two doors' worth of quiet bars while the family loads: the page keeps
/// its shape instead of spinning.
class FamilyPlaceholder extends StatelessWidget {
  const FamilyPlaceholder({super.key, this.label = 'Carregando sua família'});

  /// What assistive technology hears while the bars show.
  final String label;

  @override
  Widget build(BuildContext context) {
    final fill = context.palette.outline.withValues(alpha: .24);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(height * Radii.screenRatio),
      ),
    );
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Doors(
          key: const Key('family-placeholder'),
          children: [
            for (final width in [96.0, 136.0])
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(width, 18),
                      const SizedBox(height: Space.sm),
                      bar(176, 10),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
