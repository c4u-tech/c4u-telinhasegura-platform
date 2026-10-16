import 'dart:convert';

/// The keys of an environment's define file (`config/<env>.json`), read by
/// `--dart-define-from-file`.
const appEnvKeys = [
  'API_BASE_URL',
  'GOOGLE_CLIENT_ID',
  'GOOGLE_SERVER_CLIENT_ID',
  'APPLE_SERVICES_ID',
  'APPLE_REDIRECT_URI',
];

/// What is wrong with an environment file's [text]; empty when nothing.
List<String> appEnvProblems(String text) {
  Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return ['not a JSON object'];
  }
  if (json is! Map<String, Object?>) return ['not a JSON object'];
  final problems = <String>[
    for (final key in appEnvKeys)
      if (!json.containsKey(key))
        'missing $key'
      else if (json[key] is! String)
        '$key is not a string',
  ];
  final api = json['API_BASE_URL'];
  if (api is String) {
    final url = Uri.tryParse(api);
    if (url == null || !url.isScheme('https') || !url.hasAuthority) {
      problems.add('API_BASE_URL must be an https:// URL');
    }
  }
  return problems;
}
