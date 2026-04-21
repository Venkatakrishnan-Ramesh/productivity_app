import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart';
import '../services/sms_service.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  final db = DatabaseHelper.instance;
  List<FinanceTransaction> transactions = [];
  final fmt = NumberFormat('#,##0.00');
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final maps = await db.getTransactions();
    setState(() {
      transactions = maps
          .map((m) => FinanceTransaction(
                id: m['id'],
                title: m['title'],
                amount: m['amount'],
                category: m['category'],
                type: m['type'],
                date: m['date'],
              ))
          .toList();
    });
  }

  List<FinanceTransaction> get _filtered {
    return transactions.where((t) {
      final d = DateTime.parse(t.date);
      return d.year == _selectedMonth.year && d.month == _selectedMonth.month;
    }).toList();
  }

  double get totalIncome =>
      _filtered.where((t) => t.isIncome).fold(0, (s, t) => s + t.amount);
  double get totalExpense =>
      _filtered.where((t) => !t.isIncome).fold(0, (s, t) => s + t.amount);
  double get balance => totalIncome - totalExpense;

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
  }

  Future<void> _deleteTransaction(String id) async {
    await db.deleteTransaction(id);
    await _loadTransactions();
  }

  void _showTransactionDialog({FinanceTransaction? editing}) {
    final titleCtrl = TextEditingController(text: editing?.title ?? '');
    final amountCtrl = TextEditingController(
        text: editing != null ? editing.amount.toString() : '');
    String type = editing?.type ?? 'expense';
    String category = editing?.category ??
        (type == 'expense' ? expenseCategories.first : incomeCategories.first);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(editing == null ? 'Add Transaction' : 'Edit Transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Expense'),
                        selected: type == 'expense',
                        onSelected: (_) => setS(() {
                          type = 'expense';
                          category = expenseCategories.first;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Income'),
                        selected: type == 'income',
                        onSelected: (_) => setS(() {
                          type = 'income';
                          category = incomeCategories.first;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Title', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '\$ ',
                      border: OutlineInputBorder()),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(
                      labelText: 'Category', border: OutlineInputBorder()),
                  items: (type == 'expense'
                          ? expenseCategories
                          : incomeCategories)
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setS(() => category = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim());
                if (titleCtrl.text.trim().isEmpty || amount == null || amount <= 0) return;

                final txn = FinanceTransaction(
                  id: editing?.id ?? const Uuid().v4(),
                  title: titleCtrl.text.trim(),
                  amount: amount,
                  category: category,
                  type: type,
                  date: editing?.date ?? DateTime.now().toIso8601String(),
                );

                if (editing != null) {
                  await db.updateTransaction(txn.toMap());
                } else {
                  await db.insertTransaction(txn.toMap());
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadTransactions();
              },
              child: Text(editing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncGPay() async {
    final granted = await SmsService.requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS permission required to sync GPay')),
        );
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Reading GPay SMS...'),
            ],
          ),
        ),
      );
    }

    final found = await SmsService.fetchGPayTransactions();
    if (mounted) Navigator.pop(context);

    if (found.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No GPay / UPI transactions found in SMS')),
        );
      }
      return;
    }

    if (mounted) _showImportDialog(found);
  }

  void _showImportDialog(List<ParsedTransaction> found) {
    final selected = List<bool>.filled(found.length, true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (ctx, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Text('GPay Transactions',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${found.length} found',
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: found.length,
                    itemBuilder: (ctx, i) {
                      final t = found[i];
                      return CheckboxListTile(
                        value: selected[i],
                        onChanged: (v) => setS(() => selected[i] = v!),
                        title: Text(t.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${t.category} • ${DateFormat('d MMM y').format(t.date)}'),
                        secondary: Text(
                          '${t.type == 'expense' ? '-' : '+'}\$${fmt.format(t.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: t.type == 'expense'
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            int count = 0;
                            for (int i = 0; i < found.length; i++) {
                              if (!selected[i]) continue;
                              final t = found[i];
                              await db.insertTransaction(FinanceTransaction(
                                id: const Uuid().v4(),
                                title: t.title,
                                amount: t.amount,
                                category: t.category,
                                type: t.type,
                                date: t.date.toIso8601String(),
                              ).toMap());
                              count++;
                            }
                            await _loadTransactions();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        '$count transactions imported')),
                              );
                            }
                          },
                          icon: const Icon(Icons.download),
                          label: Text(
                              'Import ${selected.where((s) => s).length}'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: balance >= 0 ? Colors.green.shade100 : Colors.red.shade100,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Month selector
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeMonth(-1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(_selectedMonth),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: DateTime(_selectedMonth.year,
                                  _selectedMonth.month + 1)
                              .isAfter(DateTime.now())
                          ? null
                          : () => _changeMonth(1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.sync),
                      tooltip: 'Sync from GPay SMS',
                      onPressed: _syncGPay,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Balance',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '\$${fmt.format(balance)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: balance >= 0
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SummaryChip(
                      label: 'Income',
                      value: '\$${fmt.format(totalIncome)}',
                      color: Colors.green,
                      icon: Icons.arrow_downward,
                    ),
                    const SizedBox(width: 20),
                    _SummaryChip(
                      label: 'Expenses',
                      value: '\$${fmt.format(totalExpense)}',
                      color: Colors.red,
                      icon: Icons.arrow_upward,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Transaction list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long,
                            size: 64, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        const Text('No transactions this month.'),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          onPressed: _syncGPay,
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync from GPay'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final t = filtered[i];
                      final date = DateTime.parse(t.date);
                      return Dismissible(
                        key: Key(t.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) => showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete transaction?'),
                            content: Text('Remove "${t.title}"?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                        onDismissed: (_) => _deleteTransaction(t.id),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: t.isIncome
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                              child: Icon(
                                t.isIncome
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: t.isIncome ? Colors.green : Colors.red,
                              ),
                            ),
                            title: Text(t.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '${t.category} • ${DateFormat('d MMM').format(date)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${t.isIncome ? '+' : '-'}\$${fmt.format(t.amount)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: t.isIncome
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 20),
                                  color: scheme.primary,
                                  onPressed: () =>
                                      _showTransactionDialog(editing: t),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTransactionDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Transaction'),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 12)),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ],
        ),
      ],
    );
  }
}
