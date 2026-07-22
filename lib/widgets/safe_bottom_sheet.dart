import 'package:flutter/material.dart';

Future<T?> showSafeBottomSheet<T>({
  required BuildContext context,
  required Widget child, 
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true, // Fixes the 50% height limit
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return SafeArea( // Protects against the system navigation bar
        child: Padding(
          // Protects against the keyboard covering input fields
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, 
            left: 20, 
            right: 20, 
            top: 20
          ),
          child: SingleChildScrollView( // Protects against overflow crashes
            child: child,
          ),
        ),
      );
    },
  );
}