import 'package:flutter/material.dart';

import 'tokens.dart';

/// A bounded value moved in steps: its [label] in title-medium, then
/// outlined 56 dp − and + keys at the control corner with the value in
/// [words] between them in headline. A key waits once a step would pass
/// [min] or [max]; without [onChanged] both wait. Assistive technology
/// reads the value as adjustable, with its increase and decrease, and
/// each key by the step it takes ("Mais 15 min").
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.words,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int value) words;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final onChanged = this.onChanged;
    final down = onChanged != null && value - step >= min
        ? () => onChanged(value - step)
        : null;
    final up = onChanged != null && value + step <= max
        ? () => onChanged(value + step)
        : null;
    final stepWords = words(step);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: Text(label, style: text.titleMedium)),
        const SizedBox(height: Space.md),
        Row(
          children: [
            _Key(
              icon: Icons.remove_rounded,
              label: 'Menos $stepWords',
              onPressed: down,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Semantics(
                container: true,
                label: label,
                value: words(value),
                increasedValue: up == null ? null : words(value + step),
                decreasedValue: down == null ? null : words(value - step),
                onIncrease: up,
                onDecrease: down,
                child: ExcludeSemantics(
                  child: Text(
                    words(value),
                    textAlign: TextAlign.center,
                    style: text.headlineSmall,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            _Key(
              icon: Icons.add_rounded,
              label: 'Mais $stepWords',
              onPressed: up,
            ),
          ],
        ),
      ],
    );
  }
}

/// One outlined 56 dp key, read by the step it takes.
class _Key extends StatelessWidget {
  const _Key({required this.icon, required this.label, this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 56,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.square(56),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
      child: Icon(icon, semanticLabel: label, size: 28),
    ),
  );
}
