class FinanceTransaction {
  final String id;
  final String title;
  final double amount;
  final String category;
  final String type; // 'income' or 'expense'
  final String date;

  FinanceTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.type,
    required this.date,
  });

  bool get isIncome => type == 'income';

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'amount': amount,
        'category': category,
        'type': type,
        'date': date,
      };
}

const List<String> expenseCategories = [
  'Food', 'Transport', 'Shopping', 'Health',
  'Entertainment', 'Bills', 'Other'
];

const List<String> incomeCategories = [
  'Salary', 'Freelance', 'Business', 'Investment', 'Gift', 'Other'
];
