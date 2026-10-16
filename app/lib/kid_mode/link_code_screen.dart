import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../access/copy.dart';
import '../access/reauth_prompt.dart';
import '../access/widgets.dart';
import '../design/field_layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../family/family.dart';
import '../family/family_model.dart';
import '../family/family_write.dart';
import '../family/widgets.dart';
import '../parental/parental.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'hand_over_screen.dart';
import 'kid_mode_screen.dart';
import 'kid_mode_status.dart';
import 'link_qr.dart';

/// Said in place of the code once it expired.
const codeExpired =
    'Esse código expirou. Gere outro e use em até 10\u00A0minutos.';

const _choose =
    'Escolha de quem é o aparelho. Você recebe um código para digitar ou '
    'escanear nele, que vale por 10\u00A0minutos.';

/// What the family is full of, after a `limit_reached`.
enum _Full { devices, codes }

/// `/modo-crianca/vincular`: links a child's own device.
/// The children as a choice of one, then the code in two groups
/// of four, its QR and the minutes left, counted on the clock while the
/// screen is open. The code lives only in this state: never logged or
/// stored, and leaving does not cancel it (it simply expires).
class LinkCodeScreen extends StatefulWidget {
  const LinkCodeScreen({super.key});

  @override
  State<LinkCodeScreen> createState() => _LinkCodeScreenState();
}

class _LinkCodeScreenState extends State<LinkCodeScreen> {
  late final FamilyModel _model;
  late final FamilyWrite _write;
  bool _started = false;
  String? _chosen;
  LinkCode? _code;
  bool _expired = false;
  _Full? _full;
  Timer? _tick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _model = AppScope.of(context).familyModel;
    _write = FamilyWrite(family: _model, confirm: () => confirmItsYou(context));
    scheduleMicrotask(_model.load);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _write.dispose();
    super.dispose();
  }

  Duration get _left => _code!.expiresAt.difference(clock.now());

  Future<void> _generate(String minorId) async {
    final api = AppScope.of(context).parental;
    setState(() => _full = null);
    LinkCode? code;
    var limit = false;
    await _write.write(
      () async => code = await api.createLinkCode(minorId),
      overrides: const {'not_found': Copy.childGone},
      handle: (e) {
        switch (e.code) {
          case 'limit_reached':
            return limit = true;
          case 'not_found':
            // The child went meanwhile: back to the choice, refreshed.
            _stop();
            if (mounted) {
              setState(() {
                _chosen = null;
                _code = null;
              });
            }
            unawaited(_model.refresh());
        }
        return false;
      },
    );
    if (!mounted) return;
    if (code case final code?) {
      _stop();
      setState(() {
        _code = code;
        _expired = _left <= Duration.zero;
      });
      if (!_expired) {
        _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
      }
    } else if (limit) {
      final full = await _whichLimit(api.devices);
      if (mounted) setState(() => _full = full);
    }
  }

  /// The server answers `limit_reached` for 5 waiting codes and, at
  /// redemption, for 10 devices: the devices count tells which applies.
  Future<_Full> _whichLimit(
    Future<List<LinkedDevice>> Function() devices,
  ) async {
    try {
      return (await devices()).length >= kMaxDevices
          ? _Full.devices
          : _Full.codes;
    } on Object {
      return _Full.codes;
    }
  }

  void _onTick() {
    if (_left > Duration.zero) {
      setState(() {});
      return;
    }
    _stop();
    setState(() => _expired = true);
  }

  void _stop() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_model, _write]),
    builder: (context, _) => FieldLayout(
      title: 'Vincular o aparelho da criança',
      onBack: () => context.go(Routes.kidMode),
      children: switch (_model.state) {
        FamilyReady(:final family) when _code != null => [
          ..._problems(),
          ..._expired ? _expiredView() : _codeView(family, _code!),
        ],
        FamilyReady(:final family) when family.minors.isEmpty => _noChildren(),
        FamilyReady(:final family) => _chooseView(family.minors),
        _ => familyPending(_model),
      },
    ),
  );

  /// The write's message, or which limit the family reached.
  List<Widget> _problems() => [
    if (_write.message case final message?) ...[
      ErrorNote(message),
      const SizedBox(height: Space.lg),
    ] else if (_full case final full?) ...[
      ErrorNote(full == _Full.devices ? Copy.devicesFull : Copy.linkCodesFull),
      if (full == _Full.devices) ...[
        const SizedBox(height: Space.sm),
        QuietAction(
          label: 'Ver aparelhos vinculados',
          onPressed: () => context.go(Routes.devices),
        ),
      ],
      const SizedBox(height: Space.lg),
    ],
  ];

  List<Widget> _noChildren() => [
    Text(childFirst, style: Theme.of(context).textTheme.bodyLarge),
    const SizedBox(height: Space.xl),
    PrimaryButton(
      label: 'Cadastrar criança',
      onPressed: () => context.go(Routes.newChild),
    ),
  ];

  List<Widget> _chooseView(List<Minor> minors) {
    final chosen = minors.where((m) => m.id == _chosen).firstOrNull;
    final busy = _write.busy;
    return [
      Text(_choose, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: Space.xl),
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final minor in minors)
            ChildChoice(
              nickname: minor.nickname,
              avatar: minor.avatar,
              selected: minor.id == _chosen,
              onTap: busy
                  ? null
                  : () {
                      _write.clearMessage();
                      setState(() {
                        _chosen = minor.id;
                        _full = null;
                      });
                    },
            ),
        ],
      ),
      const SizedBox(height: Space.xl),
      ..._problems(),
      PrimaryButton(
        label: 'Gerar código',
        busy: busy,
        onPressed: chosen == null || _write.blocked
            ? null
            : () => _generate(chosen.id),
      ),
      // Its place stays once a child is chosen: nothing moves (fix round).
      SubmitHint(
        'Escolha uma criança acima.',
        visible: chosen == null,
        reserve: true,
      ),
    ];
  }

  List<Widget> _codeView(Family family, LinkCode code) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: context.palette.muted);
    final nickname = family.minors
        .where((m) => m.id == code.minorId)
        .firstOrNull
        ?.nickname;
    final (first, second) = codeGroups(code.code);
    final display = text.displaySmall?.copyWith(
      letterSpacing: 0.12 * (text.displaySmall?.fontSize ?? 36),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return [
      Text(
        nickname == null
            ? 'Código para o aparelho da criança'
            : 'Código para o aparelho de $nickname',
        style: text.titleMedium,
      ),
      const SizedBox(height: Space.lg),
      LinkQr(code: code.code),
      const SizedBox(height: Space.xl),
      Semantics(
        container: true,
        label: 'Código: ${spokenCode(code.code)}',
        child: ExcludeSemantics(
          child: Wrap(
            spacing: Space.xl,
            children: [
              Text(first, style: display),
              Text(second, style: display),
            ],
          ),
        ),
      ),
      const SizedBox(height: Space.sm),
      Text(KidModeWords.expiresIn(_left), style: muted),
      const SizedBox(height: Space.xl),
      for (final (i, step) in _steps.indexed) _Step(number: i + 1, text: step),
    ];
  }

  List<Widget> _expiredView() => [
    const Notice(codeExpired),
    const SizedBox(height: Space.xl),
    PrimaryButton(
      label: 'Gerar outro código',
      busy: _write.busy,
      onPressed: _write.blocked ? null : () => _generate(_code!.minorId),
    ),
  ];
}

/// The steps on the child's device, at most three short lines.
const _steps = [
  'Instale o Telinha Segura no aparelho da criança.',
  'Aponte a câmera dele para este código.',
  'Ou toque em “Este aparelho é de uma criança” e digite o código.',
];

/// One numbered step: the numbers in one column as wide as the widest
/// ("3.") at the current text size, then an 8 dp gap, so every line
/// starts at the same x and no number touches its line.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge
        ?.copyWith(color: context.palette.muted);
    final widest = TextPainter(
      text: TextSpan(text: '${_steps.length}.', style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final column = widest.width.ceilToDouble();
    widest.dispose();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: column,
              child: Text('$number.', softWrap: false, style: style),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}
