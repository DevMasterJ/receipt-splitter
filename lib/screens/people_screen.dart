import 'package:flutter/material.dart';
import '../db/database.dart';
import '../models/models.dart';
import '../widgets/name_dialog.dart';
import 'session_screen.dart';

class PeopleScreen extends StatefulWidget {
  final Session session;
  const PeopleScreen({super.key, required this.session});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _controller = TextEditingController();
  List<Person> _persons = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final persons = await AppDatabase.getPersons(widget.session.id!);
    setState(() => _persons = persons);
  }

  Future<void> _add() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    await AppDatabase.addPerson(widget.session.id!, name);
    _controller.clear();
    await _load();
  }

  Future<void> _rename(Person p) async {
    final name = await showNameDialog(context, title: 'Rename', action: 'Save', initial: p.name);
    if (name == null || name == p.name) return;
    await AppDatabase.renamePerson(p.id!, name);
    await _load();
  }

  Future<void> _delete(Person p) async {
    final items = (await AppDatabase.getItems(widget.session.id!)).where((i) => i.personId == p.id).toList();
    if (!mounted) return;
    final ok = await confirmDeletePerson(context, p.name,
        items: items.length, amount: items.fold(0.0, (s, i) => s + i.price));
    if (!ok) return;
    await AppDatabase.deletePerson(widget.session.id!, p.id!);
    if (widget.session.mePersonId == p.id) widget.session.mePersonId = null;
    await _load();
  }

  void _continue() {
    if (_persons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one person.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SessionScreen(session: widget.session, persons: _persons),
      ),
    ).then((_) => _load()); // names may have been changed or added in the session
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Who\'s in?')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _add(),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _add, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _persons.length,
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.person),
                  subtitle: const Text('Tap to rename'),
                  title: Text(_persons[i].name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete ${_persons[i].name}',
                    onPressed: () => _delete(_persons[i]),
                  ),
                  onTap: () => _rename(_persons[i]),
                ),
              ),
            ),
            SafeArea(
              child: FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue'),
                onPressed: _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
