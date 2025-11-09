import 'package:flutter/material.dart';
import 'dart:async';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      Navigator.pushReplacementNamed(context, '/scan');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF071029), Color(0xFF000000)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bluetooth, size: 96, color: Colors.tealAccent),
              const SizedBox(height: 16),
              Text(
                'ResQNetBLE',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'Initializing Bluetooth Modules...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
