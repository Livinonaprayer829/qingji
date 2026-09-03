import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class AppData {
  final List<Account> accounts;
  final List<Category> categories;
  final List<Txn> transactions;

  AppData(
      {required this.accounts,
      required this.categories,
      required this.transactions});

  AppData.empty()
      : accounts = [],
        categories = [],
        transactions = [];

  bool get isEmpty =>
      accounts.isEmpty && categories.isEmpty && transactions.isEmpty;

  AppData copyWith({
    List<Account>? accounts,
    List<Category>? categories,
    List<Txn>? transactions,
  }) =>
      AppData(
        accounts: accounts ?? this.accounts,
        categories: categories ?? this.categories,
        transactions: transactions ?? this.transactions,
      );
}

class DataRepository {
  /// v2: 主键升级为 uuid 以对齐云端 schema(v1 的 a_cash 之类非 uuid 无法写入云端)
  static const _key = 'daka_data_v2';

  SupabaseClient get _sb => Supabase.instance.client;
  String? get userId => _sb.auth.currentUser?.id;
  bool get isSignedIn => userId != null;

  // ---------------- 本地缓存 ----------------
  Future<AppData> loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return AppData.empty();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AppData(
        accounts: (map['accounts'] as List)
            .map((e) => Account.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        categories: (map['categories'] as List)
            .map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        transactions: (map['transactions'] as List)
            .map((e) => Txn.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    } catch (_) {
      return AppData.empty();
    }
  }

  Future<void> saveLocal(AppData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'accounts': data.accounts.map((e) => e.toJson()).toList(),
        'categories': data.categories.map((e) => e.toJson()).toList(),
        'transactions': data.transactions.map((e) => e.toJson()).toList(),
      }),
    );
  }

  // ---------------- 云端读写 ----------------
  /// 从云端拉取当前用户全部数据(RLS 保证只能读到自己的)
  Future<AppData?> fetchCloud() async {
    if (!isSignedIn) return null;
    try {
      final acc = await _sb.from('accounts').select();
      final cat = await _sb.from('categories').select();
      final tx = await _sb.from('transactions').select();
      return AppData(
        accounts: (acc as List)
            .map((e) => Account.fromCloud(Map<String, dynamic>.from(e as Map)))
            .toList(),
        categories: (cat as List)
            .map((e) => Category.fromCloud(Map<String, dynamic>.from(e as Map)))
            .toList(),
        transactions: (tx as List)
            .map((e) => Txn.fromCloud(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> pushAccount(Account a) async {
    final uid = userId;
    if (uid == null) return;
    await _sb.from('accounts').upsert(a.toCloud(uid));
  }

  Future<void> pushCategory(Category c) async {
    final uid = userId;
    if (uid == null) return;
    await _sb.from('categories').upsert(c.toCloud(uid));
  }

  Future<void> pushTxn(Txn t) async {
    final uid = userId;
    if (uid == null) return;
    await _sb.from('transactions').upsert(t.toCloud(uid));
  }

  Future<void> deleteTxn(String id) async {
    final uid = userId;
    if (uid == null) return;
    await _sb.from('transactions').delete().eq('id', id);
  }

  /// 全量推送(新用户首次把本地示例数据上传到云端)
  Future<void> pushAll(AppData data) async {
    for (final a in data.accounts) {
      await pushAccount(a);
    }
    for (final c in data.categories) {
      await pushCategory(c);
    }
    for (final t in data.transactions) {
      await pushTxn(t);
    }
  }

  // ---------------- 示例数据 ----------------
  /// id 由 uuid 自动生成;交易通过对象引用账户/分类,保证外键有效
  AppData seed() {
    final cash = Account(name: '现金');
    final bank = Account(name: '银行卡');
    final alipay = Account(name: '支付宝');
    final accounts = [cash, bank, alipay];

    final food = Category(name: '餐饮', icon: '🍔', type: TxType.expense);
    final transport = Category(name: '交通', icon: '🚌', type: TxType.expense);
    final shop = Category(name: '购物', icon: '🛍️', type: TxType.expense);
    final fun = Category(name: '娱乐', icon: '🎮', type: TxType.expense);
    final home = Category(name: '居家', icon: '🏠', type: TxType.expense);
    final salary = Category(name: '工资', icon: '💰', type: TxType.income);
    final bonus = Category(name: '奖金', icon: '🎁', type: TxType.income);
    final otherIn = Category(name: '其他收入', icon: '✨', type: TxType.income);
    final categories = [
      food,
      transport,
      shop,
      fun,
      home,
      salary,
      bonus,
      otherIn,
    ];

    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    Txn mk(int dayOffset, double amt, TxType t, Category cat, Account acc,
            String note) =>
        Txn(
          amount: amt,
          type: t,
          categoryId: cat.id,
          accountId: acc.id,
          date: base.subtract(Duration(days: dayOffset)),
          note: note,
        );

    final transactions = [
      mk(0, 38.5, TxType.expense, food, alipay, '午餐'),
      mk(0, 12, TxType.expense, transport, cash, '地铁'),
      mk(1, 8000, TxType.income, salary, bank, '本月工资'),
      mk(1, 56, TxType.expense, food, alipay, '晚餐'),
      mk(2, 199, TxType.expense, shop, bank, 'T恤'),
      mk(3, 30, TxType.expense, fun, alipay, '游戏充值'),
      mk(4, 45, TxType.expense, food, cash, '早餐'),
      mk(5, 120, TxType.expense, home, bank, '日用品'),
      mk(6, 500, TxType.income, bonus, alipay, '兼职'),
      mk(8, 28, TxType.expense, food, alipay, '外卖'),
      mk(10, 60, TxType.expense, transport, cash, '打车'),
      mk(12, 88, TxType.expense, shop, bank, '零食'),
    ];

    return AppData(
      accounts: accounts,
      categories: categories,
      transactions: transactions,
    );
  }

  // ---------------- 同步工具(多设备 last-write-wins) ----------------
  /// 按 updatedAt 合并本地与云端(需触发器保留客户端 updatedAt 才严格生效)
  AppData mergeWithCloud(AppData local, AppData cloud) {
    // accounts
    final localAcc = {for (final a in local.accounts) a.id: a};
    final merged = <Account>[];
    final seenAcc = <String>{};
    for (final c in cloud.accounts) {
      seenAcc.add(c.id);
      final l = localAcc[c.id];
      if (l == null || c.updatedAt.isAfter(l.updatedAt)) {
        merged.add(c);
      } else {
        merged.add(l);
      }
    }
    for (final a in local.accounts) {
      if (!seenAcc.contains(a.id)) merged.add(a);
    }
    // categories
    final localCat = {for (final c in local.categories) c.id: c};
    final mergedCat = <Category>[];
    final seenCat = <String>{};
    for (final c in cloud.categories) {
      seenCat.add(c.id);
      final l = localCat[c.id];
      if (l == null || c.updatedAt.isAfter(l.updatedAt)) {
        mergedCat.add(c);
      } else {
        mergedCat.add(l);
      }
    }
    for (final c in local.categories) {
      if (!seenCat.contains(c.id)) mergedCat.add(c);
    }
    // transactions
    final localTx = {for (final t in local.transactions) t.id: t};
    final mergedTx = <Txn>[];
    final seenTx = <String>{};
    for (final c in cloud.transactions) {
      seenTx.add(c.id);
      final l = localTx[c.id];
      if (l == null || c.updatedAt.isAfter(l.updatedAt)) {
        mergedTx.add(c);
      } else {
        mergedTx.add(l);
      }
    }
    for (final t in local.transactions) {
      if (!seenTx.contains(t.id)) mergedTx.add(t);
    }
    return AppData(
      accounts: merged,
      categories: mergedCat,
      transactions: mergedTx,
    );
  }

  /// 增量双向同步:拉云端 → 按 updatedAt 合并 → 推送 → 写回本地
  Future<AppData?> syncIncremental(AppData local) async {
    if (!isSignedIn) return null;
    final cloud = await fetchCloud();
    if (cloud == null) return null;
    final merged = mergeWithCloud(local, cloud);
    await pushAll(merged);
    await saveLocal(merged);
    return merged;
  }

  /// 强制覆盖上传:本地全量推云端
  Future<void> forceUpload(AppData local) async {
    if (!isSignedIn) return;
    await pushAll(local);
  }

  /// 从云端下载覆盖本地
  Future<AppData?> downloadFromCloud() async {
    if (!isSignedIn) return null;
    final cloud = await fetchCloud();
    if (cloud == null) return null;
    await saveLocal(cloud);
    return cloud;
  }
}
