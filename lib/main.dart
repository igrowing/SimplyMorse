import 'dart:async';
import 'package:flutter/material.dart';
import 'package:simply_morse/app.dart';
import 'package:simply_morse/core/di/injection.dart';

/// Entry point for the SimplyMorse application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(
    configureDependencies().then((_) {
      runApp(const SimplyMorseApp());
    }),
  );
}
