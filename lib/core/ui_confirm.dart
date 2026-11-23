import 'package:flutter/material.dart';

// 되돌릴 수 없는 동작 전에 한 번 더 묻는다. 취소하거나 바깥을 누르면 false다
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
