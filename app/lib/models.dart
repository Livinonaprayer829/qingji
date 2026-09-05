import 'package:uuid/uuid.dart';

final _uuid = Uuid();

enum TxType { expense, income }

extension TxTypeX on TxType {
  bool get isExpense => this == TxType.expense;
  String get label => isExpense ? '支出' : '收入';
  /// 云端存文本: 'expense' / 'income'
  String get cloud => name;
}

TxType txTypeFromCloud(String? v) =>
    TxType.values.firstWhere((e) => e.name == v, orElse: () => TxType.expense);

DateTime parseDate(dynamic v) =>
    DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

/// 取日期部分 YYYY-MM-DD,对应云端 date 列
String dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Account {
  final String id;
  final String name;
  final String currency;
  final DateTime updatedAt;

  Account({
    String? id,
    required this.name,
    this.currency = '¥',
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'currency': currency,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'],
        name: j['name'],
        currency: j['currency'] ?? '¥',
        updatedAt: parseDate(j['updatedAt']),
      );

  Map<String, dynamic> toCloud(String userId) => {
        'id': id,
        'user_id': userId,
        'name': name,
        'currency': currency,
        'type': 'cash',
        'icon': '💰',
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Account.fromCloud(Map<String, dynamic> j) => Account(
        id: j['id'],
        name: j['name'],
        currency: j['currency'] ?? '¥',
        updatedAt: parseDate(j['updated_at']),
      );
}

class Category {
  final String id;
  final String name;
  final String icon;
  final TxType type;
  final DateTime updatedAt;

  Category({
    String? id,
    required this.name,
    required this.icon,
    required this.type,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'type': type.index,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'],
        name: j['name'],
        icon: j['icon'],
        type: TxType.values[j['type'] ?? 0],
        updatedAt: parseDate(j['updatedAt']),
      );

  Map<String, dynamic> toCloud(String userId) => {
        'id': id,
        'user_id': userId,
        'name': name,
        'icon': icon,
        'type': type.cloud,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Category.fromCloud(Map<String, dynamic> j) => Category(
        id: j['id'],
        name: j['name'],
        icon: j['icon'] ?? '📦',
        type: txTypeFromCloud(j['type']?.toString()),
        updatedAt: parseDate(j['updated_at']),
      );

  Category copyWith({String? name, String? icon, TxType? type, DateTime? updatedAt}) =>
      Category(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        type: type ?? this.type,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class Txn {
  final String id;
  final double amount;
  final TxType type;
  final String categoryId;
  final String accountId;
  final DateTime date;
  final String? note;
  final DateTime updatedAt;

  Txn({
    String? id,
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.accountId,
    required this.date,
    this.note,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'type': type.index,
        'categoryId': categoryId,
        'accountId': accountId,
        'date': date.toIso8601String(),
        'note': note,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: j['id'],
        amount: (j['amount'] as num).toDouble(),
        type: TxType.values[j['type'] ?? 0],
        categoryId: j['categoryId'],
        accountId: j['accountId'],
        date: DateTime.parse(j['date']),
        note: j['note'],
        updatedAt: parseDate(j['updatedAt']),
      );

  Map<String, dynamic> toCloud(String userId) => {
        'id': id,
        'user_id': userId,
        'amount': amount,
        'type': type.cloud,
        'category_id': categoryId,
        'account_id': accountId,
        'txn_date': dateOnly(date),
        'note': note,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Txn.fromCloud(Map<String, dynamic> j) => Txn(
        id: j['id'],
        amount: (j['amount'] as num).toDouble(),
        type: txTypeFromCloud(j['type']?.toString()),
        categoryId: j['category_id'] ?? '',
        accountId: j['account_id'] ?? '',
        date: DateTime.tryParse(j['txn_date']?.toString() ?? '') ?? DateTime.now(),
        note: j['note'],
        updatedAt: parseDate(j['updated_at']),
      );

  Txn copyWith(
          {double? amount,
          TxType? type,
          String? categoryId,
          String? accountId,
          DateTime? date,
          String? note,
          DateTime? updatedAt}) =>
      Txn(
        id: id,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        categoryId: categoryId ?? this.categoryId,
        accountId: accountId ?? this.accountId,
        date: date ?? this.date,
        note: note ?? this.note,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

// =========================================================
// 借入借出(债务)
// =========================================================
enum LoanType { borrowIn, borrowOut } // borrowIn=借入(我欠别人) borrowOut=借出(别人欠我)

extension LoanTypeX on LoanType {
  bool get isBorrowIn => this == LoanType.borrowIn;
  String get label => isBorrowIn ? '借入' : '借出';
  String get cloud => isBorrowIn ? 'borrow_in' : 'borrow_out';
}

LoanType loanTypeFromCloud(String? v) =>
    v == 'borrow_out' ? LoanType.borrowOut : LoanType.borrowIn;

class Loan {
  final String id;
  final LoanType type;
  final String person; // 对方姓名/备注
  final double amount;
  final DateTime date; // 借入/借出日期
  final DateTime? dueDate; // 约定还款日
  final bool repaid; // 是否已还清
  final DateTime? repaidDate; // 还清日期
  final String? note;
  final DateTime updatedAt;

  Loan({
    String? id,
    required this.type,
    required this.person,
    required this.amount,
    required this.date,
    this.dueDate,
    this.repaid = false,
    this.repaidDate,
    this.note,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'person': person,
        'amount': amount,
        'date': date.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'repaid': repaid,
        'repaidDate': repaidDate?.toIso8601String(),
        'note': note,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Loan.fromJson(Map<String, dynamic> j) => Loan(
        id: j['id'],
        type: LoanType.values[j['type'] ?? 0],
        person: j['person'] ?? '',
        amount: (j['amount'] as num).toDouble(),
        date: DateTime.parse(j['date']),
        dueDate: j['dueDate'] == null ? null : DateTime.tryParse(j['dueDate']),
        repaid: j['repaid'] ?? false,
        repaidDate:
            j['repaidDate'] == null ? null : DateTime.tryParse(j['repaidDate']),
        note: j['note'],
        updatedAt: parseDate(j['updatedAt']),
      );

  Map<String, dynamic> toCloud(String userId) => {
        'id': id,
        'user_id': userId,
        'type': type.cloud,
        'person': person,
        'amount': amount,
        'loan_date': dateOnly(date),
        'due_date': dueDate == null ? null : dateOnly(dueDate!),
        'repaid': repaid,
        'repaid_date': repaidDate == null ? null : dateOnly(repaidDate!),
        'note': note,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Loan.fromCloud(Map<String, dynamic> j) => Loan(
        id: j['id'],
        type: loanTypeFromCloud(j['type']?.toString()),
        person: j['person'] ?? '',
        amount: (j['amount'] as num).toDouble(),
        date: DateTime.tryParse(j['loan_date']?.toString() ?? '') ?? DateTime.now(),
        dueDate: j['due_date'] == null ? null : DateTime.tryParse(j['due_date']),
        repaid: j['repaid'] ?? false,
        repaidDate:
            j['repaid_date'] == null ? null : DateTime.tryParse(j['repaid_date']),
        note: j['note'],
        updatedAt: parseDate(j['updated_at']),
      );

  Loan copyWith(
          {LoanType? type,
          String? person,
          double? amount,
          DateTime? date,
          DateTime? dueDate,
          bool? repaid,
          DateTime? repaidDate,
          String? note,
          DateTime? updatedAt}) =>
      Loan(
        id: id,
        type: type ?? this.type,
        person: person ?? this.person,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        dueDate: dueDate ?? this.dueDate,
        repaid: repaid ?? this.repaid,
        repaidDate: repaidDate ?? this.repaidDate,
        note: note ?? this.note,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
