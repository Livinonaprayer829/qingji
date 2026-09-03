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
}
