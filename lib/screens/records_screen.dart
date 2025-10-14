import 'package:flutter/material.dart';

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      body: const Center(
        child: Text(
          'Records Screen',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
