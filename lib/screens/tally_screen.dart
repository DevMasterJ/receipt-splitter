import 'package:flutter/material.dart';
import '../models/models.dart';

class TallyScreen extends StatelessWidget {
  final List<Person> persons;
  final List<ReceiptItem> items;

  const TallyScreen({super.key, required this.persons, required this.items});

  @override
  Widget build(BuildContext context) {
    final totals = <int, double>{};
    double unassignedTotal = 0;

    for (final item in items) {
      if (item.personId == null) {
        unassignedTotal += item.price;
      } else {
        totals[item.personId!] = (totals[item.personId!] ?? 0) + item.price;
      }
    }

    final sorted = persons
        .where((p) => totals.containsKey(p.id))
        .toList()
      ..sort((a, b) => (totals[b.id!] ?? 0).compareTo(totals[a.id!] ?? 0));

    return Scaffold(
      appBar: AppBar(title: const Text('Final Tally')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
        children: [
          ...sorted.map((p) => _TallyRow(
                name: p.name,
                amount: totals[p.id!]!,
              )),
          if (unassignedTotal.abs() >= 0.005) ...[
            const Divider(),
            _TallyRow(
              name: 'Unassigned',
              amount: unassignedTotal,
              isWarning: true,
            ),
          ],
          const Divider(),
          _TallyRow(
            name: 'Total',
            amount: items.fold(0, (sum, i) => sum + i.price),
            isBold: true,
          ),
        ],
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  final String name;
  final double amount;
  final bool isBold;
  final bool isWarning;

  const _TallyRow({
    required this.name,
    required this.amount,
    this.isBold = false,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontSize: isBold ? 18 : 16,
      color: isWarning ? (Theme.of(context).brightness == Brightness.dark ? Colors.orange[300] : Colors.orange[700]) : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: style),
          Text('€${amount.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
