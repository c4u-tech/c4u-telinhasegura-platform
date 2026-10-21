import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/widgets.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import 'avatars.dart';
import 'family.dart';
import 'labels.dart';

/// The nickname's limit, as the backend counts it (runes, after trimming).
const kMaxNickname = 20;

const nicknameGuidance = 'Use de 1 a $kMaxNickname caracteres.';

/// The nickname to send, trimmed, or null while it does not fit.
/// Counted in code points; the server's own check stays the authority.
String? nicknameOf(String text) {
  final nickname = text.trim();
  final length = nickname.runes.length;
  return length >= 1 && length <= kMaxNickname ? nickname : null;
}

/// The child's nickname, with its length as a state module that fills
/// once it fits. Nothing is suggested or learned from what is typed: the
/// profile holds this word and nothing more.
class NicknameField extends StatelessWidget {
  const NicknameField({
    super.key,
    required this.controller,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => TextField(
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      // Room to type past the limit and see the guidance empty, not a
      // field that silently stops.
      inputFormatters: [LengthLimitingTextInputFormatter(kMaxNickname * 2)],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Apelido',
        helper: Guidance(
          text: nicknameGuidance,
          met: nicknameOf(controller.text) != null,
        ),
      ),
    ),
  );
}

/// The twelve animals as a choice of one: four to a row, each a 48 dp+
/// target read by its animal's name. The chosen one takes a 3 px ring,
/// and assistive technology hears it checked.
class AvatarPicker extends StatelessWidget {
  const AvatarPicker({super.key, required this.value, required this.onChanged});

  /// Null while none is chosen, or when the stored one is unknown.
  final Avatar? value;
  final ValueChanged<Avatar>? onChanged;

  static const _perRow = 4;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = (box.maxWidth - Space.sm * (_perRow - 1)) / _perRow;
      final onChanged = this.onChanged;
      return Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final avatar in Avatar.values)
            if (avatar != Avatar.unknown)
              SizedBox(
                width: width,
                child: ChoiceTarget(
                  key: ValueKey(avatar),
                  label: avatar.label,
                  selected: avatar == value,
                  onTap: onChanged == null ? null : () => onChanged(avatar),
                  child: _AvatarTile(avatar, selected: avatar == value),
                ),
              ),
        ],
      );
    },
  );
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile(this.avatar, {required this.selected});

  final Avatar avatar;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Center(
        // The ring stands 2 px off the disc, so it reads against the
        // disc's own ink.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(2),
          decoration: ShapeDecoration(
            shape: CircleBorder(
              side: BorderSide(
                color: selected ? p.action : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: AvatarDisc(avatar, size: 48, excludeSemantics: true),
          ),
        ),
      ),
    );
  }
}

/// Under "2 a 4 anos" on a child's profile: what paediatricians advise,
/// said once, never a gate.
const underTwoAdvice = 'Pediatras recomendam nenhuma tela antes dos 2 anos.';

/// The three age bands as full-width rows, a choice of one. An
/// unknown stored band shows none chosen.
class AgeBandChoice extends StatefulWidget {
  const AgeBandChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.adviseUnderTwo = false,
    this.disabled = const {},
  });

  final AgeBand? value;
  final ValueChanged<AgeBand>? onChanged;

  /// On a child's profile, "2 a 4 anos" chosen shows [underTwoAdvice]
  /// under the rows. A curator choosing a video's band sees none.
  final bool adviseUnderTwo;

  /// Bands shown but not offered: a curator's video whose pace rules out
  /// the youngest.
  final Set<AgeBand> disabled;

  @override
  State<AgeBandChoice> createState() => _AgeBandChoiceState();
}

class _AgeBandChoiceState extends State<AgeBandChoice> {
  // The advice is announced only when the choice changes during the visit;
  // a profile opened already on "2 a 4 anos" shows it without a spoken alert.
  bool _changed = false;

  @override
  void didUpdateWidget(AgeBandChoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _changed = true;
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    final value = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final band in AgeBand.values)
          if (band != AgeBand.unknown) ...[
            if (band.index > 0) const SizedBox(height: Space.sm),
            SelectableRow(
              label: band.label,
              selected: band == value,
              onTap: onChanged == null || widget.disabled.contains(band)
                  ? null
                  : () => onChanged(band),
            ),
          ],
        if (widget.adviseUnderTwo && value == AgeBand.upTo4) ...[
          const SizedBox(height: Space.sm),
          Semantics(
            liveRegion: _changed,
            child: Text(
              underTwoAdvice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

/// One option of a choice of one, as a full-width 56 dp row: a state
/// module that fills when chosen, then its [label]. The chosen row's
/// stroke thickens in the action colour. It takes the palette of the
/// ground it sits on; on the child side it stands at the kid target's
/// [height], cornered at the screen ratio of it. As a key ([asKey]) it stands
/// as one of a row of choice keys, its module and words centred. A
/// [toggle] row is a mark of its own, set and taken back by a tap: it reads
/// as a checkbox, not as one of a group. Without [onTap] it waits
/// (disabled): the outline tone at 32% fill, its words at 60%.
class SelectableRow extends StatelessWidget {
  const SelectableRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.height = 56,
    this.text,
    this.detail,
    this.asKey = false,
    this.toggle = false,
  });

  /// What assistive technology reads, and the words shown unless [text]
  /// says them shorter ("15 min" read as "Mais 15 min").
  final String label;
  final String? text;

  /// A muted second line under the words, which then stand in
  /// title-medium: a choice that names who and until when (a pending
  /// invitation).
  final String? detail;

  /// A choice key: narrow, its content centred (the PIN door's times).
  final bool asKey;
  final bool toggle;
  final bool selected;
  final VoidCallback? onTap;

  /// The row's least height: 56 dp, or [KidSizes.target] on the child
  /// side.
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = height == 56 ? Radii.control : height * Radii.screenRatio;
    final off = onTap == null;
    final text = Theme.of(context).textTheme;
    final dim = p.text.withValues(alpha: .6);
    return ChoiceTarget(
      label: label,
      selected: selected,
      onTap: onTap,
      radius: radius,
      toggle: toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(minHeight: height),
        padding: EdgeInsets.symmetric(
          horizontal: asKey ? Space.sm : Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: off ? p.outline.withValues(alpha: .32) : p.input,
          borderRadius: BorderRadius.circular(radius),
        ),
        // Painted over the content, not as the box's border, which would
        // pad the content by its width: choosing moves nothing.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: selected ? p.action : p.outline,
            width: selected ? 2.5 : 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: asKey
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            StateModule(filled: selected),
            SizedBox(width: asKey ? Space.sm : Space.md),
            Flexible(
              fit: asKey ? FlexFit.loose : FlexFit.tight,
              child: switch (detail) {
                null => Text(
                  this.text ?? label,
                  style: off
                      ? text.bodyLarge?.copyWith(color: dim)
                      : text.bodyLarge,
                ),
                final detail => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      this.text ?? label,
                      style: off
                          ? text.titleMedium?.copyWith(color: dim)
                          : text.titleMedium,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      detail,
                      style: text.bodyMedium?.copyWith(
                        color: off ? dim : p.muted,
                      ),
                    ),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A choice-of-one target: read as a radio (its label, checked or not,
/// one of a group), with the 3 px focus ring outside it. A [toggle] target
/// stands alone and reads as a checkbox.
class ChoiceTarget extends StatefulWidget {
  const ChoiceTarget({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
    this.radius = Radii.small,
    this.toggle = false,
  });

  final bool toggle;

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final double radius;

  @override
  State<ChoiceTarget> createState() => _ChoiceTargetState();
}

class _ChoiceTargetState extends State<ChoiceTarget> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.radius),
    );
    final ring = _focused ? focusRing(p).resolve({WidgetState.focused}) : null;
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: !widget.toggle,
      checked: widget.selected,
      enabled: widget.onTap != null,
      label: widget.label,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape.copyWith(side: ring ?? BorderSide.none),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (focused) => setState(() => _focused = focused),
          customBorder: shape,
          focusColor: Colors.transparent,
          hoverColor: p.outline.withValues(alpha: .08),
          highlightColor: p.outline.withValues(alpha: .12),
          splashColor: p.outline.withValues(alpha: .12),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The child a screen is about: avatar, nickname and age band, read as
/// one line. An unknown avatar or band shows the neutral avatar and
/// "Faixa não informada".
class ChildSummary extends StatelessWidget {
  const ChildSummary({
    super.key,
    required this.nickname,
    required this.avatar,
    required this.ageBand,
  });

  final String nickname;
  final Avatar avatar;
  final AgeBand ageBand;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        children: [
          AvatarDisc(avatar, size: 56, excludeSemantics: true),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nickname, style: text.titleMedium),
                Text(
                  ageBand.label,
                  style: text.bodyMedium?.copyWith(
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
