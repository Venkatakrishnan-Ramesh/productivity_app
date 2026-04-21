class FinanceTransaction {
  final String id;
  final String title;
  final double amount;
  final String category;
  final String type; // 'income' or 'expense'
  final String date;
  final bool isRecurring;
  final String recurrencePattern;
  final String? smsDate;

  FinanceTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.type,
    required this.date,
    this.isRecurring = false,
    this.recurrencePattern = '',
    this.smsDate,
  });

  bool get isIncome => type == 'income';

  factory FinanceTransaction.fromMap(Map<String, dynamic> map) {
    return FinanceTransaction(
      id: map['id'] as String,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String,
      type: map['type'] as String,
      date: map['date'] as String,
      isRecurring: ((map['is_recurring'] as int?) ?? 0) == 1,
      recurrencePattern: (map['recurrence_pattern'] as String?) ?? '',
      smsDate: map['sms_date'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'amount': amount,
        'category': category,
        'type': type,
        'date': date,
        'is_recurring': isRecurring ? 1 : 0,
        'recurrence_pattern': recurrencePattern,
        'sms_date': smsDate,
      };
}

const List<String> expenseCategories = [
  'Food', 'Transport', 'Shopping', 'Health',
  'Entertainment', 'Bills', 'Other'
];

const List<String> incomeCategories = [
  'Salary', 'Freelance', 'Business', 'Investment', 'Gift', 'Other'
];
