import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/inventory_intake_screen.dart';
import 'screens/login_screen.dart';
import 'screens/invite_password_screen.dart';

class YoaronApp extends StatefulWidget {
  const YoaronApp({super.key, this.openedFromInvite = false});

  final bool openedFromInvite;

  @override
  State<YoaronApp> createState() => _YoaronAppState();
}

class _YoaronAppState extends State<YoaronApp> {
  late bool _mustChangeInvitePassword = widget.openedFromInvite;

  @override
  Widget build(BuildContext context) {
    // print("YOARON BUILD2");
    return MaterialApp(
      title: 'Inventory Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),

      // --- THE AUTH GATE ---
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final currentSession = Supabase.instance.client.auth.currentSession;

          if (currentSession != null) {
            if (_mustChangeInvitePassword) {
              return InvitePasswordScreen(
                onPasswordChanged: () {
                  if (mounted) {
                    setState(() => _mustChangeInvitePassword = false);
                  }
                },
              );
            }
            // Logged IN -> Show the main camera/intake screen
            return const InventoryScreen();
          } else {
            // Logged OUT -> Force them to the login screen
            return const LoginScreen();
          }
        },
      ),
    );
  }
}
