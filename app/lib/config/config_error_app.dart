import 'package:flutter/material.dart';

/// Shown when the web app cannot load `/config.json`:
/// deliberately bare, since the app's theme and services never
/// started. It sends no request.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Text(
              'Não foi possível carregar a configuração. Tente de novo em alguns minutos.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
