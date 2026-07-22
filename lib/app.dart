import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/inventory_intake_screen.dart';
import 'screens/login_screen.dart'; 

class YoaronApp extends StatelessWidget {
  const YoaronApp({super.key});

  @override
  Widget build(BuildContext context) {
    print("YOARON BUILD");
    return MaterialApp(
      title: 'Inventory Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
      
      // --- THE AUTH GATE ---
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {

          final currentSession = Supabase.instance.client.auth.currentSession;

          print("Session: $currentSession");
          print("User: ${currentSession?.user.id}");

          if (currentSession != null) {
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