// Refuses an environment file before a release build.
// Usage: dart run tool/check_app_env.dart config/prd.json
import 'dart:io';

import 'package:telinha_segura/config/app_env.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/check_app_env.dart <file>');
    exit(64);
  }
  final file = File(args.single);
  if (!file.existsSync()) {
    stderr.writeln('${args.single}: no such environment file');
    exit(1);
  }
  final problems = appEnvProblems(file.readAsStringSync());
  for (final p in problems) {
    stderr.writeln('${args.single}: $p');
  }
  if (problems.isNotEmpty) exit(1);
}
