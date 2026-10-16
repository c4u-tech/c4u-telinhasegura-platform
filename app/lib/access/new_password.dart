import 'package:flutter/material.dart';

import '../auth/api_error.dart';
import 'copy.dart';
import 'widgets.dart';

/// The server's floor. Counted in code points; the
/// server's NFKC check stays the authority.
const minPasswordLength = 15;

bool longEnough(String password) => password.runes.length >= minPasswordLength;

/// A new-password field with the length guidance as a state module that
/// fills as the guardian types, and the server's reasons on
/// the field.
class NewPasswordField extends StatelessWidget {
  const NewPasswordField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.label = 'Senha',
    this.errorText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String label;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => PasswordField(
    controller: controller,
    isNew: true,
    label: label,
    errorText: errorText,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    helper: errorText == null
        ? Guidance(
            text: Copy.passwordGuidance,
            met: longEnough(controller.text),
          )
        : null,
  );
}

/// The field message for a `weak_password` answer, or null for any other
/// error (which then stays form-level).
String? passwordFieldError(ApiError e) =>
    e.code == 'weak_password' ? Copy.forError(e) : null;

final tooShortMessage = Copy.forError(
  const ApiError(status: 422, code: 'weak_password', reasons: ['too_short']),
);
