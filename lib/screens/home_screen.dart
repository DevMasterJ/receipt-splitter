import 'package:flutter/material.dart';
import '../db/database.dart';
import 'join_screen.dart';
import 'people_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _startNewSession(BuildContext context) async {
    final last = await AppDatabase.getLatestSession();
    if (last != null) {
      final items = await AppDatabase.getItems(last.id!);
      final people = await AppDatabase.getPersons(last.id!);
      if ((items.isNotEmpty || people.isNotEmpty) && context.mounted) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Start a new night?'),
            content: Text('The current bill (${people.length} people, ${items.length} items) will be deleted.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete and start new')),
            ],
          ),
        );
        if (ok != true) return;
      }
    }
    await AppDatabase.deleteAllSessions();
    final session = await AppDatabase.createSession();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PeopleScreen(session: session)),
    );
  }

  Future<void> _continueSession(BuildContext context) async {
    final session = await AppDatabase.getLatestSession();
    if (session == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active session found.')),
      );
      return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PeopleScreen(session: session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Splitter')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Start New Night'),
              onPressed: () => _startNewSession(context),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Continue Session'),
              onPressed: () => _continueSession(context),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Join a table'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JoinScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
