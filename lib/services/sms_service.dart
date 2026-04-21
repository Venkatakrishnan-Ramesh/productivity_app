import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'notification_service.dart';

class ParsedTransaction {
  final String title;
  final double amount;
  final String type;
  final String category;
  final DateTime date;

  ParsedTransaction({
    required this.title,
    required this.amount,
    required this.type,
    required this.category,
    required this.date,
  });
}

class SmsService {
  static final _amountRe = RegExp(
    r'(?:Rs\.?|INR\s*)(\d+(?:,\d+)*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static final _upiRe = RegExp(
    r'\bupi\b|gpay|google\s*pay|phonepe|paytm|@[a-z0-9]+',
    caseSensitive: false,
  );

  static Future<bool> requestPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  static Future<List<ParsedTransaction>> fetchGPayTransactions() async {
    final query = SmsQuery();
    final messages = await query.querySms(kinds: [SmsQueryKind.inbox]);

    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final results = <ParsedTransaction>[];

    for (final msg in messages) {
      final body = msg.body ?? '';
      final date = msg.date ?? DateTime.now();
      if (date.isBefore(cutoff)) continue;
      if (!_upiRe.hasMatch(body)) continue;

      final parsed = _parse(body, date);
      if (parsed != null) {
        results.add(parsed);
        await NotificationService.instance.showTransactionDetected(
          title: parsed.title,
          amount: parsed.amount,
          type: parsed.type,
        );
      }
    }

    results.sort((a, b) => b.date.compareTo(a.date));
    return results;
  }

  static ParsedTransaction? _parse(String body, DateTime date) {
    final amountMatch = _amountRe.firstMatch(body);
    if (amountMatch == null) return null;

    final amountStr = amountMatch.group(1)!.replaceAll(',', '');
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) return null;

    final lower = body.toLowerCase();
    final isDebit = lower.contains('debited') || lower.contains('debit');
    final isCredit = lower.contains('credited') || lower.contains('credit');
    if (!isDebit && !isCredit) return null;

    final type = isDebit ? 'expense' : 'income';
    final title = _extractTitle(body);
    final category = isDebit ? _guessCategory(body) : 'UPI Income';

    return ParsedTransaction(
      title: title,
      amount: amount,
      type: type,
      category: category,
      date: date,
    );
  }

  static String _extractTitle(String body) {
    // "to VPA abc@bank"
    final vpaMatch = RegExp(
      r'(?:to\s+(?:VPA\s+)?)([\w.\-]+@[\w.\-]+)',
      caseSensitive: false,
    ).firstMatch(body);
    if (vpaMatch != null) {
      return vpaMatch.group(1)!.split('@').first
          .replaceAll(RegExp(r'[.\-_]'), ' ')
          .trim()
          .toUpperCase();
    }

    // "Info: UPI/MERCHANT"
    final infoMatch = RegExp(
      r'Info:\s*UPI[/-]([\w\s]+?)(?:\.|,|\s{2}|$)',
      caseSensitive: false,
    ).firstMatch(body);
    if (infoMatch != null) return infoMatch.group(1)!.trim();

    // "Merchant: NAME"
    final merchantMatch = RegExp(
      r'Merchant:\s*([\w\s]+?)(?:\.|,|$)',
      caseSensitive: false,
    ).firstMatch(body);
    if (merchantMatch != null) return merchantMatch.group(1)!.trim();

    return 'GPay Payment';
  }

  static String _guessCategory(String body) {
    final lower = body.toLowerCase();
    if (lower.contains('swiggy') || lower.contains('zomato') || lower.contains('food') || lower.contains('restaurant')) return 'Food';
    if (lower.contains('uber') || lower.contains('ola') || lower.contains('rapido') || lower.contains('metro') || lower.contains('petrol') || lower.contains('fuel')) return 'Transport';
    if (lower.contains('amazon') || lower.contains('flipkart') || lower.contains('myntra') || lower.contains('shop')) return 'Shopping';
    if (lower.contains('netflix') || lower.contains('spotify') || lower.contains('prime') || lower.contains('hotstar')) return 'Entertainment';
    if (lower.contains('electricity') || lower.contains('water') || lower.contains('gas') || lower.contains('rent') || lower.contains('broadband')) return 'Bills';
    if (lower.contains('hospital') || lower.contains('pharmacy') || lower.contains('medical') || lower.contains('doctor')) return 'Health';
    return 'UPI';
  }
}
