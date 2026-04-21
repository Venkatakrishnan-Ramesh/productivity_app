import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';

class WaterScreen extends StatefulWidget {
  const WaterScreen({super.key});

  @override
  State<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends State<WaterScreen> {
  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _logs = [];
  int _totalMl = 0;
  static const int _goalMl = 2000;

  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await db.getWaterLogs(_todayStr);
    final total = logs.fold(0, (sum, l) => sum + (l['amount_ml'] as int));
    setState(() {
      _logs = logs;
      _totalMl = total;
    });
  }

  Future<void> _addWater(int ml) async {
    await db.insertWaterLog({
      'id': const Uuid().v4(),
      'date': _todayStr,
      'logged_at': DateTime.now().toIso8601String(),
      'amount_ml': ml,
    });
    await _load();
  }

  Future<void> _deleteLog(String id) async {
    await db.deleteWaterLog(id);
    await _load();
  }

  double get _progress => (_totalMl / _goalMl).clamp(0.0, 1.0);
  int get _glasses => _totalMl ~/ 250;
  int get _goalGlasses => _goalMl ~/ 250;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = (_goalMl - _totalMl).clamp(0, _goalMl);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [

            // Main progress ring
            Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 18,
                        backgroundColor: Colors.blue.shade100,
                        color: _progress >= 1.0 ? Colors.green : Colors.blue,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('💧', style: TextStyle(fontSize: 32)),
                        Text('$_glasses / $_goalGlasses',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold, color: Colors.blue)),
                        Text('glasses',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        if (_progress >= 1.0)
                          const Text('🎉 Goal met!',
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            Center(
              child: Text(
                remaining > 0
                    ? '${remaining}ml (${remaining ~/ 250} glasses) to go'
                    : 'Perfectly hydrated today!',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),

            const SizedBox(height: 24),

            // Quick add buttons
            Text('Quick Add',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _QuickAddButton(label: '1 glass\n250ml', onTap: () => _addWater(250), color: Colors.blue.shade300),
                _QuickAddButton(label: 'Bottle\n500ml', onTap: () => _addWater(500), color: Colors.blue.shade500),
                _QuickAddButton(label: 'Large\n750ml', onTap: () => _addWater(750), color: Colors.blue.shade700),
                _QuickAddButton(
                  label: 'Custom',
                  onTap: _showCustomInput,
                  color: scheme.primary,
                  icon: Icons.edit,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Glasses visualization
            Text('Today\'s intake',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_goalGlasses, (i) {
                final filled = i < _glasses;
                return Icon(
                  filled ? Icons.water_drop : Icons.water_drop_outlined,
                  size: 36,
                  color: filled ? Colors.blue : Colors.blue.shade200,
                );
              }),
            ),

            const SizedBox(height: 24),

            // Log history
            if (_logs.isNotEmpty) ...[
              Text('Log',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._logs.reversed.map((log) {
                final time = DateTime.parse(log['logged_at'] as String);
                return Dismissible(
                  key: Key(log['id'] as String),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                        color: Colors.red, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => _deleteLog(log['id'] as String),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      leading: const Icon(Icons.water_drop, color: Colors.blue),
                      title: Text('${log['amount_ml']}ml'),
                      trailing: Text(
                        DateFormat('h:mm a').format(time),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _showCustomInput() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom amount'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Amount (ml)', border: OutlineInputBorder(), suffixText: 'ml'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final ml = int.tryParse(ctrl.text.trim());
              if (ml != null && ml > 0) {
                Navigator.pop(ctx);
                _addWater(ml);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _QuickAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  final IconData? icon;

  const _QuickAddButton({
    required this.label,
    required this.onTap,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, color: color, size: 20)
            else
              const Icon(Icons.add, size: 16),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
