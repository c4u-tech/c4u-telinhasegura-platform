import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'display_title.dart';
import 'espiadinha.dart';
import 'theme.dart';
import 'tokens.dart';

/// How much of the screen the ink field takes on a narrow screen.
enum FieldSize {
  /// The entry screen: lockup and the promise line.
  hero,

  /// Every task screen: a band with the lockup and, when given, a back
  /// control.
  band,
}

/// The field's one promise, on every screen: who curates is parents,
/// caregivers and professionals, and publishing takes approvals from any
/// of them, so it never says "only other parents" (2026-10-06).
const promiseLine =
    'Cada vídeo daqui passa pelo olhar de pais, cuidadores e profissionais '
    'antes de chegar a uma criança.';

/// The access surface's frame. The flat ink field is the Espiadinha's
/// screen, with the head peeking over its top edge; the task sits on the
/// ground beside it (wide) or below it (narrow). No cards: the field's
/// edge does the dividing.
class FieldLayout extends StatelessWidget {
  const FieldLayout({
    super.key,
    required this.title,
    required this.children,
    this.titleSemanticsLabel,
    this.size = FieldSize.band,
    this.onBack,
    this.rise = false,
    this.promise = promiseLine,
  });

  final String title;

  /// The promise line the field carries (wide, and under the title at large
  /// text). A surface whose reader is not a guardian says its own.
  final String promise;

  /// What assistive technology reads instead of [title], when the shown
  /// title carries an address's break marks.
  final String? titleSemanticsLabel;
  final List<Widget> children;
  final FieldSize size;
  final VoidCallback? onBack;

  /// Plays "o sol sobe" once: the confirmations.
  final bool rise;

  @override
  Widget build(BuildContext context) {
    // At large text sizes the hero would push the task below the fold:
    // the field shrinks to a band and the promise moves under the title.
    final largeText = MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
    final compact = size == FieldSize.hero && largeText;
    // The compact hero's promise reads under the title, wide or narrow.
    final task = _TaskColumn(
      title: title,
      titleSemanticsLabel: titleSemanticsLabel,
      lead: compact ? promise : null,
      children: children,
    );
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth >= FieldSizes.wideBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: box.maxWidth * 0.46,
                    child: Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: _Field(
                        unit: 4,
                        rise: rise,
                        expand: true,
                        // At large text the panel behaves as the narrow
                        // field: no promise for a band screen (the band
                        // carries none), the hero's under its title; a
                        // display-large promise would be clipped at the
                        // panel's foot.
                        child: _FieldContent(
                          size: FieldSize.hero,
                          onBack: onBack,
                          large: true,
                          promise: largeText ? null : promise,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.xl,
                          vertical: Space.xxxl,
                        ),
                        child: task,
                      ),
                    ),
                  ),
                ],
              );
            }
            final hero = size == FieldSize.hero && !compact;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.md,
                      Space.sm,
                      Space.md,
                      0,
                    ),
                    child: _Field(
                      unit: hero ? FieldSizes.heroUnit : FieldSizes.bandUnit,
                      rise: rise,
                      child: _FieldContent(
                        size: hero ? FieldSize.hero : FieldSize.band,
                        onBack: onBack,
                        promise: promise,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xl,
                      Space.xxl,
                      Space.xl,
                      Space.xxxl,
                    ),
                    child: Center(child: task),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TaskColumn extends StatelessWidget {
  const _TaskColumn({
    required this.title,
    required this.children,
    this.titleSemanticsLabel,
    this.lead,
  });

  final String title;
  final String? titleSemanticsLabel;
  final List<Widget> children;

  /// Body text under the title: the promise, when the field is a band.
  final String? lead;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: FieldSizes.columnMaxWidth),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: DisplayTitle(title, semanticsLabel: titleSemanticsLabel),
        ),
        if (lead case final lead?) ...[
          const SizedBox(height: Space.md),
          Text(lead, style: Theme.of(context).textTheme.bodyLarge),
        ],
        const SizedBox(height: Space.xl),
        ...children,
      ],
    ),
  );
}

/// The head strip above a rounded ink field cut with the mark's radius
/// (10 units on the same grid as the head).
class _Field extends StatelessWidget {
  const _Field({
    required this.unit,
    required this.child,
    this.rise = false,
    this.expand = false,
  });

  final double unit;
  final Widget child;
  final bool rise;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final field = DecoratedBox(
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(10 * unit),
      ),
      child: child,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Center(
            child: _Head(unit: unit, rise: rise),
          ),
        ),
        if (expand)
          // The field fills the panel; at large text sizes its content
          // scrolls inside it rather than overflowing.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => DecoratedBox(
                decoration: BoxDecoration(
                  color: p.field,
                  borderRadius: BorderRadius.circular(10 * unit),
                ),
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(child: child),
                  ),
                ),
              ),
            ),
          )
        else
          field,
      ],
    );
  }
}

class _Head extends StatefulWidget {
  const _Head({required this.unit, required this.rise});

  final double unit;
  final bool rise;

  @override
  State<_Head> createState() => _HeadState();
}

class _HeadState extends State<_Head> with SingleTickerProviderStateMixin {
  late final _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _play();
  }

  /// A confirmation on a screen already shown (the family just created)
  /// turns rise on in place.
  @override
  void didUpdateWidget(_Head old) {
    super.didUpdateWidget(old);
    if (!old.rise) _play();
  }

  void _play() {
    final still = MediaQuery.of(context).disableAnimations;
    if (widget.rise && !still && _rise.value == 1 && !_played) {
      _played = true;
      _rise.forward(from: 0);
    }
  }

  bool _played = false;

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: EspiadinhaPainter.width * widget.unit,
    height: EspiadinhaPainter.height * widget.unit,
    child: AnimatedBuilder(
      animation: _rise,
      builder: (context, _) => CustomPaint(
        painter: EspiadinhaPainter(palette: context.palette, rise: _rise.value),
      ),
    ),
  );
}

class _FieldContent extends StatelessWidget {
  const _FieldContent({
    required this.size,
    this.onBack,
    this.large = false,
    this.promise = promiseLine,
  });

  final FieldSize size;

  /// The promise at the field's foot; null leaves the field to the lockup.
  final String? promise;
  final VoidCallback? onBack;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lockup = SvgPicture.asset(
      'assets/brand/telinha-segura-lockup-reversed.svg',
      height: size == FieldSize.hero ? 32 : 24,
      semanticsLabel: 'Telinha Segura',
    );
    final back = onBack == null
        ? null
        : IconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            color: p.onField,
            icon: const Icon(Icons.arrow_back_rounded),
          );
    if (size == FieldSize.band) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.sm,
        ),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              back ?? const SizedBox(width: Space.md),
              const SizedBox(width: Space.xs),
              lockup,
            ],
          ),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        back == null ? Space.xl : Space.sm,
        Space.xl,
        large ? Space.xxxl : Space.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: large
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        children: [
          // Back and lockup stay one top group; only the promise goes to
          // the foot of the wide field.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (back != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Transform.translate(
                    offset: const Offset(-Space.md, 0),
                    child: back,
                  ),
                ),
              lockup,
            ],
          ),
          if (promise case final promise?) ...[
            SizedBox(height: large ? Space.xxxl : Space.xl),
            Text(
              promise,
              style: (large ? text.displayLarge : text.headlineSmall)?.copyWith(
                color: p.onField,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
