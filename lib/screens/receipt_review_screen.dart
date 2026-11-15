import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database.dart';
import '../models/models.dart';
import '../reader/croatian_words.dart';
import '../reader/ocr_rules_reader.dart';
import '../reader/receipt_reader.dart';
import '../reader/receipt_rules.dart';

class ReceiptReviewScreen extends StatefulWidget {
  final Session session;
  final List<Person> persons;
  final ImageSource source;
  const ReceiptReviewScreen(
      {super.key, required this.session, required this.persons, this.source = ImageSource.camera});

  @override
  State<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends State<ReceiptReviewScreen> {
  final List<_ItemDraft> _drafts = [];
  bool _picking = true;
  bool _reading = false;
  bool _showErrors = false;   // after a Save attempt with bad rows
  String _status = '';
  String? _store;
  double? _total;
  String? _stopped;
  String? _readerName;
  StreamSubscription<ReaderEvent>? _sub;
  final _clock = Stopwatch();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final d in _drafts) {
      d.dispose();
    }
    _deletePhoto();
    super.dispose();
  }

  /// The picker's resized copy in the app cache isn't needed once the items are read (the original stays
  /// in the gallery / camera roll if the phone keeps one).
  void _deletePhoto() {
    final path = _path;
    if (path == null || !path.contains('/cache/')) return;
    Future.delayed(const Duration(seconds: 5), () async {   // let a reader that's still running finish
      try {
        final f = File(path);
        await f.delete();
        await f.parent.delete();   // the picker's own folder; fails harmlessly if not empty
      } catch (_) {}
    });
  }

  String? _path;

  Future<void> _scan() async {
    final image = await ImagePicker()
        .pickImage(source: widget.source, maxWidth: 2000, maxHeight: 2000, imageQuality: 92);
    if (!mounted) return;
    if (image == null) {
      Navigator.pop(context);
      return;
    }
    _path = image.path;
    setState(() => _picking = false);
    _read(OcrRulesReader(), image.path);
  }

  int _run = 0;

  /// [onFailed] runs if the reader errors before the first item, [onDone] when it finishes normally.
  void _read(ReceiptReader reader, String path, {VoidCallback? onFailed, VoidCallback? onDone}) {
    final run = ++_run;
    bool current() => mounted && run == _run;
    var gotItems = false;
    setState(() {
      _reading = true;
      _readerName = reader.name;
      _status = 'Starting…';
    });
    _clock
      ..reset()
      ..start();
    _sub = reader.read(path).listen(
      (e) {
        if (!current()) return;
        setState(() {
          switch (e) {
            case ReaderProgress(:final message):
              _status = message;
            case ReaderStore(:final name):
              _store = name;
            case ReaderItem(:final item):
              gotItems = true;
              final fixed = ReceiptRules.clean(item);
              final prices = ReceiptRules.rowPrices(fixed);
              for (final price in prices) {
                _addDraft(fixed.name, price, note: _note(fixed, prices.length));
              }
            case ReaderDiscount(:final name, :final amount):
              _addDraft(CroatianWords.fix(name), amount, note: 'discount');
            case ReaderTotal(:final total):
              _total = total;
            case ReaderStopped(:final reason):
              _stopped = reason;
          }
        });
      },
      onError: (Object err, StackTrace st) {
        debugPrint('reader ${reader.name} failed: $err\n$st');
        if (!mounted || run != _run) return;
        if (onFailed != null && !gotItems) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('${reader.name} failed ($err), trying another reader')));
          setState(() => _reading = false);
          onFailed();
        } else {
          setState(() => _reading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan failed: $err')));
        }
      },
      onDone: () {
        if (!current()) return;
        _clock.stop();
        setState(() {
          _reading = false;
          _status = 'Read in ${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';
        });
        onDone?.call();
      },
    );
  }

  String? _note(ParsedItem it, int rows) {
    final parts = <String>[];
    if (rows > 1) parts.add('1 of ${it.qty.toInt()}');
    if (rows == 1 && it.qty != 1) parts.add('${_qty(it.qty)} × ${it.unitPrice.toStringAsFixed(2)}');
    if (it.qtyFixed) parts.add('qty corrected');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  void _stop() {
    _sub?.cancel();
    _run++;
    setState(() {
      _reading = false;
      _status = 'Stopped';
    });
  }

  void _addDraft(String name, double price, {String? note}) {
    final d = _ItemDraft(
      nameController: TextEditingController(text: name),
      priceController: TextEditingController(text: price.toStringAsFixed(2)),
      note: note,
    );
    d.priceController.addListener(_onPriceEdited);
    _drafts.add(d);
  }

  void _onPriceEdited() => setState(() {});

  void _addManual() => setState(() => _addDraft('', 0));

  void _remove(int index) {
    setState(() => _drafts.removeAt(index).dispose());
  }

  static double? _price(_ItemDraft d) => parsePrice(d.priceController.text);

  /// A row the user started filling in but that can't be saved as it is.
  static bool _invalid(_ItemDraft d) {
    final name = d.nameController.text.trim(), price = d.priceController.text.trim();
    if (name.isEmpty && (price.isEmpty || _price(d) == 0)) return false;   // empty row: skipped
    return name.isEmpty || _price(d) == null;
  }

  double get _sum => _drafts.fold(0.0, (s, d) => s + (_price(d) ?? 0));

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;   // a double tap would save every item twice
    final bad = _drafts.where(_invalid).length;
    if (bad > 0) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(bad == 1
              ? '1 item needs a name and a price like 12,50.'
              : '$bad items need a name and a price like 12,50.')));
      return;
    }
    setState(() => _saving = true);
    for (final d in _drafts) {
      final name = d.nameController.text.trim();
      final price = _price(d);
      if (name.isEmpty || price == null) continue;
      await AppDatabase.addItem(ReceiptItem(
        sessionId: widget.session.id!,
        personId: d.selectedPersonId,
        name: name,
        price: price,
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_picking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final waiting = _reading && _drafts.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_store ?? 'Review Items'),
        actions: [
          if (_reading) IconButton(icon: const Icon(Icons.stop), tooltip: 'Stop reading', onPressed: _stop),
        ],
      ),
      body: Column(
        children: [
          if (_reading) const LinearProgressIndicator(),
          _banner(context),
          Expanded(
            child: waiting
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_status),
                      if (_readerName != null)
                        Text(_readerName!, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  )
                : _drafts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('No items detected.'),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add manually'),
                              onPressed: _addManual,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        itemCount: _drafts.length + 1,
                        itemBuilder: (_, i) {
                          if (i == _drafts.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: _reading
                                  ? Center(child: Text(_status, style: Theme.of(context).textTheme.bodySmall))
                                  : OutlinedButton.icon(
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add item'),
                                      onPressed: _addManual,
                                    ),
                            );
                          }
                          final d = _drafts[i];
                          return _ItemRow(
                            key: ObjectKey(d),
                            draft: d,
                            showErrors: _showErrors,
                            persons: widget.persons,
                            onRemove: () => _remove(i),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.save),
            label: Text('Save Items  (${_sum.toStringAsFixed(2)} €)'),
            onPressed: _drafts.isEmpty || _reading || _saving ? null : _save,
          ),
        ),
      ),
    );
  }

  /// Sum check: items (after edits) against the receipt total the reader found.
  Widget _banner(BuildContext context) {
    if (_total == null && _stopped == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final lines = <String>[];
    var ok = false;
    if (_total != null) {
      final diff = double.parse((_sum - _total!).toStringAsFixed(2));
      ok = diff.abs() < 0.011;
      lines.add(ok
          ? 'Adds up to the receipt total ${_total!.toStringAsFixed(2)} €'
          : "Doesn't add up: items ${_sum.toStringAsFixed(2)} €, receipt total ${_total!.toStringAsFixed(2)} € "
              '(${diff > 0 ? '+' : ''}${diff.toStringAsFixed(2)}). Check the items.');
    }
    if (_stopped != null) lines.add('Reading stopped early ($_stopped) – some items may be missing.');
    ok = ok && _stopped == null;
    return Material(
      color: ok ? scheme.primaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber,
              color: ok ? scheme.onPrimaryContainer : scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(lines.join('\n'),
                style: TextStyle(color: ok ? scheme.onPrimaryContainer : scheme.onErrorContainer)),
          ),
        ]),
      ),
    );
  }
}

class _ItemDraft {
  final TextEditingController nameController;
  final TextEditingController priceController;
  final String? note;
  int? selectedPersonId;

  _ItemDraft({required this.nameController, required this.priceController, this.note});

  void dispose() {
    nameController.dispose();
    priceController.dispose();
  }
}

class _ItemRow extends StatefulWidget {
  final _ItemDraft draft;
  final List<Person> persons;
  final VoidCallback onRemove;
  final bool showErrors;

  const _ItemRow(
      {super.key, required this.draft, required this.persons, required this.onRemove, this.showErrors = false});

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  @override
  Widget build(BuildContext context) {
    final note = widget.draft.note;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: widget.draft.nameController,
                    decoration: InputDecoration(
                      labelText: 'Item',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: widget.showErrors &&
                              widget.draft.nameController.text.trim().isEmpty &&
                              _ReceiptReviewScreenState._invalid(widget.draft)
                          ? 'Name?'
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: widget.draft.priceController,
                    decoration: InputDecoration(
                      labelText: 'Price',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: widget.showErrors && _ReceiptReviewScreenState._price(widget.draft) == null &&
                              _ReceiptReviewScreenState._invalid(widget.draft)
                          ? 'e.g. 12,50'
                          : null,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            if (note != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Text(note, style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: widget.draft.selectedPersonId,
              decoration: const InputDecoration(
                labelText: 'Assign to',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('— unassigned —')),
                ...widget.persons.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))),
              ],
              onChanged: (v) => setState(() => widget.draft.selectedPersonId = v),
            ),
          ],
        ),
      ),
    );
  }
}
