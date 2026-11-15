import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../db/database.dart';
import '../live/live_server.dart';
import '../live/table_wifi.dart';
import '../models/models.dart';
import '../widgets/name_dialog.dart';
import 'receipt_review_screen.dart';
import 'live_screen.dart';
import 'tally_screen.dart';

class SessionScreen extends StatefulWidget {
  final Session session;
  final List<Person> persons;
  const SessionScreen(
      {super.key, required this.session, required this.persons});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late List<Person> _persons;
  List<ReceiptItem> _items = [];
  final _live = LiveServer.instance;

  @override
  void initState() {
    super.initState();
    _persons = List.from(widget.persons);
    _live.addListener(_liveChanged);
    _live.setHost(widget.session.mePersonId);
    _loadItems();
  }

  @override
  void dispose() {
    _live.removeListener(_liveChanged);
    if (_live.running) {
      _live.stop();
      WakelockPlus.disable();
    }
    if (TableWifi.hotspot != null) TableWifi.stopHotspot();
    _live.setHost(null);
    super.dispose();
  }

  void _liveChanged() {
    if (mounted) setState(() {});
  }

  /// People come from the database too, never only from the list we were opened with: a stale list
  /// (e.g. back to "Who's in?" and Continue again) hid a person added here and showed their items as "?".
  Future<void> _loadItems() async {
    final items = await AppDatabase.getItems(widget.session.id!);
    final persons = await AppDatabase.getPersons(widget.session.id!);
    if (!mounted) return;
    setState(() {
      _items = items;
      _persons
        ..clear()
        ..addAll(persons); // same list object: the live screen holds it
    });
    _live.update(_persons, _items);
  }

  Future<void> _openLive() async {
    if (!_live.running) {
      try {
        await _live.start();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start sharing: $e')));
        return;
      }
      WakelockPlus.enable(); // a dozing phone stops answering the guests
      _live.update(_persons, _items);
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LiveScreen(persons: _persons)));
  }

  Future<void> _stopLive() async {
    await _live.stop();
    if (TableWifi.hotspot != null) await TableWifi.stopHotspot();
    WakelockPlus.disable();
  }

  Future<void> _pickMe() async {
    final me = widget.session.mePersonId;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text('Which one is you?', style: Theme.of(context).textTheme.titleMedium)),
          const Divider(),
          for (final p in _persons)
            ListTile(
              leading: Icon(p.id == me ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(p.name),
              onTap: () => Navigator.pop(context, p.id),
            ),
          ListTile(
            leading: Icon(me == null ? Icons.radio_button_checked : Icons.radio_button_off),
            title: const Text('— not set —'),
            onTap: () => Navigator.pop(context, -1),
          ),
        ]),
      ),
    );
    if (picked == null) return;
    final id = picked == -1 ? null : picked;
    widget.session.mePersonId = id;
    await AppDatabase.setMe(widget.session.id!, id);
    _live.setHost(id);
    if (mounted) setState(() {});
  }

  Widget _meBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = _persons.where((p) => p.id == widget.session.mePersonId).firstOrNull;
    final owe = me == null ? 0.0 : _items.where((i) => i.personId == me.id).fold(0.0, (s, i) => s + i.price);
    return Material(
      color: me == null ? scheme.surfaceContainerHighest : scheme.primaryContainer,
      child: ListTile(
        leading: Icon(me == null ? Icons.person_search : Icons.star),
        title: Text(me == null ? 'Which one is you?' : '${me.name} (you) owe €${owe.toStringAsFixed(2)}'),
        subtitle: Text(me == null ? 'Tap to pick — your name is then reserved for this phone' : 'Tap to change'),
        onTap: _pickMe,
      ),
    );
  }

  Future<void> _assign(ReceiptItem item) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            title: Text(item.name, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text('€${item.price.toStringAsFixed(2)}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit), tooltip: 'Edit', onPressed: () => Navigator.pop(context, -2)),
              IconButton(
                  icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: () => Navigator.pop(context, -3)),
            ]),
          ),
          const Divider(),
          for (final p in _persons)
            ListTile(
              leading: Icon(p.id == item.personId ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(p.name),
              onTap: () => Navigator.pop(context, p.id),
            ),
          ListTile(
            leading: Icon(item.personId == null ? Icons.radio_button_checked : Icons.radio_button_off),
            title: const Text('— unassigned —'),
            onTap: () => Navigator.pop(context, -1),
          ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == -2) return _editItem(item);
    if (picked == -3) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Delete ${item.name}?'),
          content: Text('€${item.price.toStringAsFixed(2)} is taken off the bill.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true) return;
      await AppDatabase.deleteItem(item.id!);
      await _loadItems();
      return;
    }
    item.personId = picked == -1 ? null : picked;
    await AppDatabase.updateItem(item);
    await _loadItems();
  }

  Future<void> _editItem(ReceiptItem item) async {
    final name = TextEditingController(text: item.name);
    final price = TextEditingController(text: item.price.toStringAsFixed(2).replaceAll('.', ','));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) {
          final valid = name.text.trim().isNotEmpty && parsePrice(price.text) != null;
          return AlertDialog(
            title: const Text('Edit item'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Item'),
                  onChanged: (_) => refresh(() {})),
              TextField(
                controller: price,
                decoration: InputDecoration(
                    labelText: 'Price', errorText: parsePrice(price.text) == null ? 'e.g. 12,50' : null),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                onChanged: (_) => refresh(() {}),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: valid ? () => Navigator.pop(c, true) : null, child: const Text('Save')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    await AppDatabase.updateItem(ReceiptItem(
        id: item.id,
        sessionId: item.sessionId,
        personId: item.personId,
        name: name.text.trim(),
        price: parsePrice(price.text)!));
    await _loadItems();
  }

  Future<void> _addPerson() async {
    final name = await showNameDialog(context, title: 'Add person', action: 'Add');
    if (name == null) return;
    final person = await AppDatabase.addPerson(widget.session.id!, name);
    setState(() => _persons.add(person));
    _live.update(_persons, _items);
  }

  Future<void> _renamePerson(Person p) async {
    final name = await showNameDialog(context, title: 'Rename', action: 'Save', initial: p.name);
    if (name == null || name == p.name) return;
    await AppDatabase.renamePerson(p.id!, name);
    final i = _persons.indexWhere((x) => x.id == p.id);
    setState(() => _persons[i] = p.withName(name));
    _live.update(_persons, _items);
  }

  Future<void> _deletePerson(Person p) async {
    final theirs = _items.where((i) => i.personId == p.id).toList();
    final ok = await confirmDeletePerson(context, p.name,
        items: theirs.length, amount: theirs.fold(0.0, (s, i) => s + i.price));
    if (!ok) return;
    await AppDatabase.deletePerson(widget.session.id!, p.id!);
    if (widget.session.mePersonId == p.id) {
      widget.session.mePersonId = null;
      _live.setHost(null);
    }
    await _loadItems(); // reloads people + items and updates the live bill
  }

  /// Everyone at the table: tap a name to fix it, or add someone who was missed.
  Future<void> _people() => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: StatefulBuilder(
            builder: (ctx, refresh) => ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('People'), subtitle: Text('Tap a name to change it')),
              for (final p in _persons)
                ListTile(
                  leading: Icon(p.id == widget.session.mePersonId ? Icons.star : Icons.person),
                  title: Text(p.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete ${p.name}',
                    onPressed: () async {
                      await _deletePerson(p);
                      refresh(() {});
                    },
                  ),
                  onTap: () async {
                    await _renamePerson(p);
                    refresh(() {});
                  },
                ),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Add person'),
                onTap: () async {
                  await _addPerson();
                  refresh(() {});
                },
              ),
            ]),
          ),
        ),
      );

  void _scanReceipt([ImageSource source = ImageSource.camera]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptReviewScreen(
          session: widget.session,
          persons: _persons,
          source: source,
        ),
      ),
    );
    await _loadItems();
  }

  void _endSession() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TallyScreen(
          persons: _persons,
          items: _items,
        ),
      ),
    );
  }

  String _personName(int? personId) {
    if (personId == null) return 'Unassigned';
    final name = _persons.firstWhere((p) => p.id == personId,
        orElse: () => Person(sessionId: 0, name: '?')).name;
    return personId == widget.session.mePersonId ? '$name (you)' : name;
  }

  @override
  Widget build(BuildContext context) {
    final unassigned = _items.where((i) => i.personId == null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          if (_live.running)
            IconButton(
              icon: const Icon(Icons.portable_wifi_off),
              tooltip: 'Stop sharing',
              onPressed: _stopLive,
            ),
          IconButton(
            icon: Icon(_live.running ? Icons.wifi_tethering : Icons.qr_code_2),
            color: _live.running ? (Theme.of(context).brightness == Brightness.dark ? Colors.green[300] : Colors.green[700]) : null,
            tooltip: _live.running ? 'Live: ${_live.guestCount} connected' : 'Share live with the table',
            onPressed: _openLive,
          ),
          IconButton(
            icon: const Icon(Icons.group),
            tooltip: 'People',
            onPressed: _people,
          ),
        ],
      ),
      body: Column(
        children: [
          _meBar(context),
          if (_items.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final item = _items[i];
                  return ListTile(
                    onTap: () => _assign(item),
                    title: Text(item.name),
                    subtitle: Text(_personName(item.personId)),
                    trailing: Text(
                      '€${item.price.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            )
          else
            const Expanded(
              child: Center(child: Text('No receipts scanned yet.')),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (unassigned > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '$unassigned item(s) not yet assigned',
                        style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.orange[300] : Colors.orange[700]),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.document_scanner),
                        label: const Text('Scan Receipt'),
                        onPressed: _scanReceipt,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.photo_library),
                      tooltip: 'Receipt from gallery',
                      onPressed: () => _scanReceipt(ImageSource.gallery),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calculate),
                    label: const Text('End Night & Tally'),
                    onPressed: _items.isEmpty ? null : _endSession,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
