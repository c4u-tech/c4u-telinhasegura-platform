import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../auth/provider_sign_in.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../shell/routes.dart';
import '../shell/services.dart';
import 'submission.dart';

const providerTokenRefused =
    'Não conseguimos confirmar esse login agora. Tente de novo.';

/// Routes a provider answer: a stored session lets the router take the
/// guardian home; a confirmation waits in memory for its screen.
void followProviderResult(BuildContext context, ProviderSignInResult result) {
  final services = AppScope.of(context);
  switch (result) {
    case SignedIn():
      services.pending.value = null;
    case SignupRequired():
      services.pending.value = result;
      context.go(Routes.providerSignup);
    case LinkRequired():
      services.pending.value = result;
      context.go(Routes.linkAccount);
  }
}

/// Offers [idToken] to the API under [submission], then follows the
/// answer.
Future<void> offerProviderToken(
  BuildContext context,
  Submission submission,
  IdentityProvider provider,
  String idToken,
) async {
  final services = AppScope.of(context);
  ProviderSignInResult? result;
  await submission.run(
    () async => result = await services.auth.signInWithProvider(
      provider,
      idToken,
      deviceLabel: await services.deviceLabel.read(),
    ),
    overrides: const {'invalid_token': providerTokenRefused},
  );
  if (result != null && context.mounted) {
    followProviderResult(context, result!);
  }
}

/// Asks the platform for a token; a cancelled sheet ends quietly.
Future<void> signInWithProvider(
  BuildContext context,
  Submission submission,
  IdentityProvider provider,
) async {
  final services = AppScope.of(context);
  String? token;
  final asked = await submission.run(
    () async => token = await services.providers.idToken(provider),
  );
  if (!asked || token == null || !context.mounted) return;
  await offerProviderToken(context, submission, provider, token!);
}

const _webProviderHeight = 48.0;

/// Whether [services] offers any provider button.
bool offersProviders(AppServices services) =>
    services.googleWeb != null ||
    services.settings.googleEnabled ||
    services.settings.appleEnabled;

/// The Google and Apple rows the settings enable, stacked. On the web,
/// Google's own rendered button stands in for the native one and its
/// tokens arrive on `GoogleWebSignIn.idTokens`, which the screen holds.
class ProviderChoices extends StatelessWidget {
  const ProviderChoices({super.key, required this.onPressed});

  /// Null while a request runs: the native buttons disable.
  final void Function(IdentityProvider provider)? onPressed;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final googleWeb = services.googleWeb;
    final onPressed = this.onPressed;
    final buttons = <Widget>[
      // Google's rendered web button is a fixed 40 px tall, so on the
      // web both provider rows share one 48 dp height (the touch-target
      // floor) instead of stepping from 40 to 56.
      if (googleWeb != null)
        SizedBox(
          height: _webProviderHeight,
          child: Center(
            child: FutureBuilder(
              future: googleWeb.ready,
              builder: (context, ready) =>
                  ready.connectionState == ConnectionState.done
                  ? LayoutBuilder(
                      builder: (context, box) =>
                          googleWeb.button(width: box.maxWidth),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        )
      else if (services.settings.googleEnabled)
        ProviderButton(
          provider: IdentityProvider.google,
          onPressed: onPressed == null
              ? null
              : () => onPressed(IdentityProvider.google),
        ),
      if (services.settings.appleEnabled)
        ProviderButton(
          provider: IdentityProvider.apple,
          height: googleWeb != null ? _webProviderHeight : null,
          onPressed: onPressed == null
              ? null
              : () => onPressed(IdentityProvider.apple),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, button) in buttons.indexed) ...[
          if (i > 0) controlGap,
          button,
        ],
      ],
    );
  }
}

/// The provider's own button, drawn to its brand rules: Google's G on a
/// neutral outline, Apple's mark on solid black (white in dark mode).
class ProviderButton extends StatelessWidget {
  const ProviderButton({
    super.key,
    required this.provider,
    required this.onPressed,
    this.height,
  });

  final IdentityProvider provider;
  final VoidCallback? onPressed;

  /// Overrides the theme's 56 dp, to match Google's web button row.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = p.brightness == Brightness.dark;
    switch (provider) {
      case IdentityProvider.google:
        return OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(backgroundColor: p.input).copyWith(
            side: focusRing(p, BorderSide(color: p.outline, width: 1.5)),
          ),
          icon: SvgPicture.asset(
            'assets/brand/google-g.svg',
            width: 20,
            height: 20,
            excludeFromSemantics: true,
          ),
          label: const Text('Continuar com o Google'),
        );
      case IdentityProvider.apple:
        final fg = dark ? Colors.black : Colors.white;
        return FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: dark ? Colors.white : Colors.black,
            foregroundColor: fg,
            disabledBackgroundColor: (dark ? Colors.white : Colors.black)
                .withValues(alpha: 0.4),
            minimumSize: height == null ? null : Size(64, height!),
          ),
          icon: SvgPicture.asset(
            'assets/brand/apple-logo.svg',
            width: 17,
            height: 20,
            colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
            excludeFromSemantics: true,
          ),
          label: const Text('Continuar com a Apple'),
        );
    }
  }
}

/// The gap between stacked full-width controls.
const controlGap = SizedBox(height: Space.md);
