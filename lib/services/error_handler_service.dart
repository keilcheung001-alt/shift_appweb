// lib/services/error_handler_service.dart
import 'package:flutter/material.dart';

class ErrorHandlerService {
  static void handleError(String context, dynamic error, {BuildContext? ctx}) {
    debugPrint('❌ $context Error: $error');

    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('$context 錯誤：${error.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  static void handleLoginError(dynamic error, BuildContext context) {
    handleError('Login', error, ctx: context);
  }
}
