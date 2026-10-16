import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/widgets.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/widgets.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'kid_mode_status.dart';

/// The family home's fourth door, "Modo criança": the
/// PIN and the linked devices as two state modules, each with its words
/// on its own line. It reads them itself, so the other doors never wait;
/// a failed read says so and the door still opens.
class KidModeDoor extends StatefulWidget {
  const KidModeDoor({super.key});

  @override
  State<KidModeDoor> createState() => _KidModeDoorState();
}

class _KidModeDoorState extends State<KidModeDoor> {
  late final Future<KidModeStatus> _status;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _status = KidModeStatus.read(AppScope.of(context).parental);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _status,
    builder: (context, read) {
      final status = read.data;
      final lines = switch (read) {
        AsyncSnapshot(hasError: true) => const [kidModeUnknown],
        _ when status != null => [
          KidModeWords.pin(status.pinSet),
          KidModeWords.devices(status.devices.length),
        ],
        _ => const <String>[],
      };
      return DoorRow(
        title: 'Modo criança',
        semanticsLabel: ['Modo criança', ...lines].join(', '),
        onTap: () => context.go(Routes.kidMode),
        child: switch (status) {
          final status? => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StateLine(filled: status.pinSet, words: lines[0]),
              const SizedBox(height: Space.xs),
              StateLine(filled: status.devices.isNotEmpty, words: lines[1]),
            ],
          ),
          null when read.hasError => _Words(kidModeUnknown),
          null => const _Pending(),
        },
      );
    },
  );
}

/// A state module with its words beside it, the module centred on the
/// first line when the words wrap.
class StateLine extends StatelessWidget {
  const StateLine({super.key, required this.filled, required this.words});

  final bool filled;
  final String words;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted);
    final line = MediaQuery.textScalerOf(context)
        .scale(style!.fontSize! * (style.height ?? 1));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: line,
          child: Center(child: StateModule(filled: filled)),
        ),
        const SizedBox(width: Space.sm),
        Expanded(child: Text(words, style: style)),
      ],
    );
  }
}

class _Words extends StatelessWidget {
  const _Words(this.words);

  final String words;

  @override
  Widget build(BuildContext context) => Text(
    words,
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: context.palette.muted),
  );
}

/// A quiet bar where the states will be, while they are read.
class _Pending extends StatelessWidget {
  const _Pending();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('kid-mode-door-pending'),
    width: 176,
    height: 10,
    decoration: BoxDecoration(
      color: context.palette.outline.withValues(alpha: .24),
      borderRadius: BorderRadius.circular(10 * Radii.screenRatio),
    ),
  );
}
