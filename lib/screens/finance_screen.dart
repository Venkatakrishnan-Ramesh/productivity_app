import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../db/database_helper.dart';
import '../models/transaction.dart';
import '../services/sms_service.dart';

// ── Category colour palette ──────────────────────────────────────────────────
const Map<String, Color> categoryColors = {
  'Food': Color(0xFFEF5350),
  'Transport': Color(0xFF42A5F5),
  'Shopping': Color(0xFFAB47BC),
  'Health': Color(0xFF26A69A),
  'Entertainment': Color(0xFFFFA726),
  'Bills': Color(0xFF78909C),
  'Other': Color(0xFF8D6E63),
  'Salary': Color(0xFF66BB6A),
  'Freelance': Color(0xFF29B6F6),
  'Business': Color(0xFFFFCA28),
  'Investment': Color(0xFF26C6DA),
  'Gift': Color(0xFFEC407A),
};

Color _catColor(String cat) => categoryColors[cat] ?? const Color(0xFF90A4AE);

// ── Main widget ──────────────────────────────────────────────────────────────

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

  // Search & filter state
  final _searchCtrl = TextEditingController();
  String _searchTerm = '';
  String _typeFilter = 'All'; // 'All' | 'Income' | 'Expense'

  // Previous-month expense for comparison
  double _prevMonthExpense = 0;

  // Expense-by-category data for pie chart
  List<Map<String, dynamic>> _categoryData = [];

  // Budget limits
  List<Map<String, dynamic>> _budgetLimits = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchTerm = _searchCtrl.text.trim().toLowerCase());
    });
    _loadTransactions();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadTransactions() async {
    final maps = await db.getTransactions();
    final list = maps
        .map((m) => FinanceTransaction(
              id: m['id'],
              title: m['title'],
              amount: m['amount'],
              category: m['category'],
              type: m['type'],
              date: m['date'],
              isRecurring: ((m['is_recurring'] as int?) ?? 0) == 1,
              recurrencePattern: (m['recurrence_pattern'] as String?) ?? '',
              smsDate: m['sms_date'] as String?,
            ))
        .toList();

    // Previous month expense (calculated from full list)
    final prevMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    final prevExpense = list.where((t) {
      final d = DateTime.parse(t.date);
      return d.year == prevMonth.year &&
          d.month == prevMonth.month &&
          !t.isIncome;
    }).fold<double>(0, (s, t) => s + t.amount);

    // Category breakdown for current month
    List<Map<String, dynamic>> catData = [];
    try {
      final from = DateFormat('yyyy-MM-dd')
          .format(DateTime(_selectedMonth.year, _selectedMonth.month, 1));
      final to = DateFormat('yyyy-MM-dd')
          .format(DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0));
      catData = (await db.getExpensesByCategory(from, to))
          .cast<Map<String, dynamic>>();
    } catch (_) {
      // Fallback: compute locally
      final monthExpenses = list.where((t) {
        final d = DateTime.parse(t.date);
        return d.year == _selectedMonth.year &&
            d.month == _selectedMonth.month &&
            !t.isIncome;
      });
      final Map<String, double> grouped = {};
      for (final t in monthExpenses) {
        grouped[t.category] = (grouped[t.category] ?? 0) + t.amount;
      }
      catData = grouped.entries
          .map((e) => {'category': e.key, 'total': e.value})
          .toList();
    }

    // Budget limits
    List<Map<String, dynamic>> limits = [];
    try {
      limits = (await db.getBudgetLimits()).cast<Map<String, dynamic>>();
    } catch (_) {}

    setState(() {
      transactions = list;
      _prevMonthExpense = prevExpense;
      _categoryData = catData;
      _budgetLimits = limits;
    });
  }

  // ── Filtering helpers ────────────────────────────────────────────────────

  List<FinanceTransaction> get _monthFiltered {
    return transactions.where((t) {
      final d = DateTime.parse(t.date);
      return d.year == _selectedMonth.year && d.month == _selectedMonth.month;
    }).toList();
  }

  List<FinanceTransaction> get _filtered {
    return _monthFiltered.where((t) {
      final matchesSearch =
          _searchTerm.isEmpty || t.title.toLowerCase().contains(_searchTerm);
      final matchesType = _typeFilter == 'All' ||
          (_typeFilter == 'Income' && t.isIncome) ||
          (_typeFilter == 'Expense' && !t.isIncome);
      return matchesSearch && matchesType;
    }).toList();
  }

  double get totalIncome =>
      _monthFiltered.where((t) => t.isIncome).fold(0, (s, t) => s + t.amount);
  double get totalExpense =>
      _monthFiltered.where((t) => !t.isIncome).fold(0, (s, t) => s + t.amount);
  double get balance => totalIncome - totalExpense;

  // ── Month navigation ─────────────────────────────────────────────────────

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    _loadTransactions();
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────

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
                if (titleCtrl.text.trim().isEmpty ||
                    amount == null ||
                    amount <= 0) return;

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

  // ── GPay SMS sync ────────────────────────────────────────────────────────

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
          const SnackBar(
              content: Text('No GPay / UPI transactions found in SMS')),
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
                            color:
                                t.type == 'expense' ? Colors.red : Colors.green,
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
                                id: t.stableId,
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
                                    content:
                                        Text('$count transactions imported')),
                              );
                            }
                          },
                          icon: const Icon(Icons.download),
                          label:
                              Text('Import ${selected.where((s) => s).length}'),
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

  // ── Feature 5: CSV Export ────────────────────────────────────────────────

  void _exportCsv() {
    final rows = _monthFiltered;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No transactions to export.')),
      );
      return;
    }

    final buf = StringBuffer('Date,Title,Amount,Type,Category\n');
    for (final t in rows) {
      final date = DateFormat('yyyy-MM-dd').format(DateTime.parse(t.date));
      final title = t.title.replaceAll('"', '""');
      final category = t.category.replaceAll('"', '""');
      buf.write(
          '$date,"$title",${t.amount.toStringAsFixed(2)},${t.type},"$category"\n');
    }
    final csv = buf.toString();

    Clipboard.setData(ClipboardData(text: csv));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export CSV'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'CSV for ${DateFormat('MMMM yyyy').format(_selectedMonth)} copied to clipboard.'),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SingleChildScrollView(
                child: Text(
                  csv,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csv));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CSV copied to clipboard!')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  // ── Feature 4: Budget bottom sheet ──────────────────────────────────────

  void _showBudgetSheet() {
    // Build a working copy keyed by category
    final Map<String, double> limits = {
      for (final b in _budgetLimits)
        b['category'] as String: (b['limit_amount'] as num).toDouble()
    };
    // Make sure all expense categories appear
    for (final cat in expenseCategories) {
      limits.putIfAbsent(cat, () => 0);
    }

    // Spent per category this month (from _categoryData, or compute locally)
    Map<String, double> spent = {};
    if (_categoryData.isNotEmpty) {
      for (final row in _categoryData) {
        spent[row['category'] as String] = (row['total'] as num).toDouble();
      }
    } else {
      for (final t in _monthFiltered.where((t) => !t.isIncome)) {
        spent[t.category] = (spent[t.category] ?? 0) + t.amount;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.70,
            maxChildSize: 0.95,
            builder: (ctx, scrollCtrl) => Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined),
                      const SizedBox(width: 8),
                      const Text('Budget Limits',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text(DateFormat('MMM yyyy').format(_selectedMonth),
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: expenseCategories.map((cat) {
                      final limitVal = limits[cat] ?? 0;
                      final spentVal = spent[cat] ?? 0;
                      final ratio = limitVal > 0
                          ? (spentVal / limitVal).clamp(0.0, 1.0)
                          : 0.0;
                      final pct =
                          limitVal > 0 ? (spentVal / limitVal * 100) : 0.0;
                      final barColor = ratio < 0.7
                          ? Colors.green
                          : ratio < 0.9
                              ? Colors.orange
                              : Colors.red;

                      final controller = TextEditingController(
                        text: limitVal > 0 ? limitVal.toStringAsFixed(0) : '',
                      );

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor:
                                        _catColor(cat).withOpacity(0.15),
                                    child: Icon(Icons.circle,
                                        color: _catColor(cat), size: 10),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(cat,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15)),
                                  const Spacer(),
                                  SizedBox(
                                    width: 90,
                                    child: TextField(
                                      controller: controller,
                                      decoration: const InputDecoration(
                                        prefixText: '\$ ',
                                        labelText: 'Limit',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      onSubmitted: (v) async {
                                        final val = double.tryParse(v) ?? 0;
                                        setS(() => limits[cat] = val);
                                        try {
                                          await db.setBudgetLimit(cat, val);
                                        } catch (_) {}
                                        await _loadTransactions();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Spent: \$${fmt.format(spentVal)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700),
                                  ),
                                  Text(
                                    limitVal > 0
                                        ? '${pct.toStringAsFixed(0)}% of \$${fmt.format(limitVal)}'
                                        : 'No limit set',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: limitVal > 0
                                            ? barColor
                                            : Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  minHeight: 8,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(barColor),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final scheme = Theme.of(context).colorScheme;

    // Monthly comparison text
    String comparisonText = '';
    Color comparisonColor = Colors.grey;
    if (_prevMonthExpense > 0) {
      final diff = totalExpense - _prevMonthExpense;
      final pct = (diff / _prevMonthExpense * 100).abs().toStringAsFixed(0);
      if (diff > 0) {
        comparisonText = '↑ $pct% vs last month';
        comparisonColor = Colors.red.shade700;
      } else if (diff < 0) {
        comparisonText = '↓ $pct% vs last month';
        comparisonColor = Colors.green.shade700;
      } else {
        comparisonText = '= same as last month';
        comparisonColor = Colors.grey.shade700;
      }
    } else if (totalExpense > 0) {
      comparisonText = 'First month of data';
      comparisonColor = Colors.grey.shade600;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync from GPay SMS',
            onPressed: _syncGPay,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              color: balance >= 0 ? Colors.green.shade100 : Colors.red.shade100,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Month selector row
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
                      onPressed: DateTime(
                                  _selectedMonth.year, _selectedMonth.month + 1)
                              .isAfter(DateTime.now())
                          ? null
                          : () => _changeMonth(1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const Spacer(),
                    // Budget button in header
                    IconButton(
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      tooltip: 'Budget Limits',
                      onPressed: _showBudgetSheet,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Balance', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '\$${fmt.format(balance)}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: balance >= 0
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                ),
                const SizedBox(height: 8),
                // Summary chips + monthly comparison
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
                    const Spacer(),
                    // Feature 3: monthly comparison badge
                    if (comparisonText.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: comparisonColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          comparisonText,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: comparisonColor),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── Feature 2: Pie chart ─────────────────────────────────────────
          if (_categoryData.isNotEmpty) _buildPieChart(),

          // ── Feature 1: Search + filter chips ────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search transactions...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchTerm.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchTerm = '');
                            },
                          )
                        : null,
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['All', 'Income', 'Expense'].map((f) {
                    final selected = _typeFilter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(f),
                        selected: selected,
                        onSelected: (_) => setState(() => _typeFilter = f),
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // ── Transaction list ─────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long,
                            size: 64, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(_searchTerm.isNotEmpty
                            ? 'No results for "$_searchTerm"'
                            : 'No transactions this month.'),
                        if (_searchTerm.isEmpty) ...[
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: _syncGPay,
                            icon: const Icon(Icons.sync),
                            label: const Text('Sync from GPay'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
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
                                    color:
                                        t.isIncome ? Colors.green : Colors.red,
                                  ),
                                ),
                                IconButton(
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 20),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Feature 4: Budget FAB
          FloatingActionButton.small(
            heroTag: 'budget_fab',
            onPressed: _showBudgetSheet,
            tooltip: 'Budget Limits',
            child: const Icon(Icons.account_balance_wallet),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'add_txn_fab',
            onPressed: () => _showTransactionDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add Transaction'),
          ),
        ],
      ),
    );
  }

  // ── Feature 2: Pie chart widget ──────────────────────────────────────────

  Widget _buildPieChart() {
    final total = _categoryData.fold<double>(
        0, (s, r) => s + (r['total'] as num).toDouble());
    if (total <= 0) return const SizedBox.shrink();

    final sections = _categoryData.asMap().entries.map((e) {
      final row = e.value;
      final cat = row['category'] as String;
      final amount = (row['total'] as num).toDouble();
      final pct = amount / total * 100;
      return PieChartSectionData(
        value: amount,
        color: _catColor(cat),
        radius: 52,
        title: '${pct.toStringAsFixed(0)}%',
        titleStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Expenses by Category',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              // Pie chart
              SizedBox(
                height: 140,
                width: 140,
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 28,
                    sectionsSpace: 2,
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Legend
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _categoryData.map((row) {
                    final cat = row['category'] as String;
                    final amount = (row['total'] as num).toDouble();
                    final pct = (amount / total * 100).toStringAsFixed(0);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _catColor(cat),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$cat  \$${fmt.format(amount)} ($pct%)',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Summary chip ─────────────────────────────────────────────────────────────

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
                    color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ],
    );
  }
}
