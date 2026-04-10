import 'package:flutter/material.dart';

/// The built-in "Hello World" plugin page — registered by the hello plugin
/// manifest. Demonstrates the native Flutter plugin page type.
class HelloPluginPage extends StatelessWidget {
  const HelloPluginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hello')),
      body: const Center(
        child: Text(
          'Hello, World!',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
