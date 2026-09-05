import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

final _uuid = Uuid();

final _uuidRegExp = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool isUuid(String s) => _uuidRegExp.hasMatch(s);

class AppData {
  final List<Account> accounts;
  final List<Category> categories;
  final List<Txn> transactions;
  final List<Loan> loans;

  AppData(
      {required this.accounts,
      required this.categories,
      required this.transactions,
      this.loans = const []});

  AppData.empty()
      : accounts = [],
        categories = [],
        transactions = [],
        loans = [];

  bool get isEmpty =>
      accounts.isEmpty &&
      categories.isEmpty &&
      transactions.isEmpty &&
      loans.isEmpty;

  AppData copyWith({
    List<Account>? accounts,
    List<Category>? categories,
    List<Txn>? transactions,
    List<Loan>? loans,
  }) =>
      AppData(
        accounts: accounts ?? this.accounts,
        categories: categories ?? this.categories,
        transactions: transactions ?? this.transactions,
        loans: loans ?? this.loans,
      );
}

class DataRepository {
  /// v2: 主键升级为 uuid 以对齐云端 schema(v1 的 a_cash 之类非 uuid 无法写入云端)
  static const _key = 'daka_data_v2';

  SupabaseClient get _sb => Supabase.instance.client;
  String? get userId => _sb.auth.currentUser?.id;
  bool get isSignedIn => userId != null;

  /// 借还同步最近一次的错误(用于 UI 提示)。
  /// 借还表可能尚未在 Supabase 创建,此前错误被静默吞掉,用户无从排查。
  String? lastLoansError;

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
        loans: (map['loans'] as List? ?? [])
            .map((e) => Loan.fromJson(Map<String, dynamic>.from(e as Map)))
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
        'loans': data.loans.map((e) => e.toJson()).toList(),
      }),
    );
  }

  // ---------------- 本地数据迁移(v1 非 uuid 主键 → uuid) ----------------
  /// v1 遗留的 id 形如 a_cash、c_bank、t_1788608545705391 等,无法写入 Supabase 的 uuid 列。
  /// 该方法在加载本地数据后调用:
  /// 1. 内置账户/分类按名称对齐到固定 uuid(跨设备一致,避免重复)。
  /// 2. 自定义账户/分类/交易/借还的非 uuid id 重新生成 uuid。
  /// 3. 同步替换交易中的 accountId / categoryId 外键。
  /// 4. 将迁移后的数据写回本地。
  Future<AppData> migrateIdsToUuid(AppData data) async {
    final builtInAccMap = {for (final a in builtInAccounts()) a.name: a.id};
    final builtInCatMap = {for (final c in builtInCategories()) c.name: c.id};

    final accMap = <String, String>{};
    final catMap = <String, String>{};
    var changed = false;

    // accounts
    final accounts = data.accounts.map((a) {
      String newId = a.id;
      if (builtInAccMap.containsKey(a.name)) {
        newId = builtInAccMap[a.name]!;
      } else if (!isUuid(a.id)) {
        newId = _uuid.v4();
      }
      if (newId != a.id) {
        accMap[a.id] = newId;
        changed = true;
      }
      return Account(
        id: newId,
        name: a.name,
        currency: a.currency,
        updatedAt: a.updatedAt,
      );
    }).toList();

    // categories
    final categories = data.categories.map((c) {
      String newId = c.id;
      if (builtInCatMap.containsKey(c.name)) {
        newId = builtInCatMap[c.name]!;
      } else if (!isUuid(c.id)) {
        newId = _uuid.v4();
      }
      if (newId != c.id) {
        catMap[c.id] = newId;
        changed = true;
      }
      return Category(
        id: newId,
        name: c.name,
        icon: c.icon,
        type: c.type,
        updatedAt: c.updatedAt,
      );
    }).toList();

    // transactions: update id and foreign keys
    final txns = data.transactions.map((t) {
      final newAccId = accMap[t.accountId] ?? t.accountId;
      final newCatId = catMap[t.categoryId] ?? t.categoryId;
      final newId = isUuid(t.id) ? t.id : _uuid.v4();
      if (newId != t.id || newAccId != t.accountId || newCatId != t.categoryId) {
        changed = true;
        return Txn(
          id: newId,
          amount: t.amount,
          type: t.type,
          categoryId: newCatId,
          accountId: newAccId,
          date: t.date,
          note: t.note,
          updatedAt: t.updatedAt,
        );
      }
      return t;
    }).toList();

    // loans
    final loans = data.loans.map((l) {
      if (isUuid(l.id)) return l;
      changed = true;
      return Loan(
        id: _uuid.v4(),
        type: l.type,
        person: l.person,
        amount: l.amount,
        date: l.date,
        dueDate: l.dueDate,
        repaid: l.repaid,
        repaidDate: l.repaidDate,
        note: l.note,
        updatedAt: l.updatedAt,
      );
    }).toList();

    if (!changed) return data;
    final migrated = AppData(
      accounts: accounts,
      categories: categories,
      transactions: txns,
      loans: loans,
    );
    await saveLocal(migrated);
    return migrated;
  }

  // ---------------- 内置项识别 ----------------
  /// 判断是否为内置账户(固定 uuid,各用户本地一致,不应上传云端,避免多用户 RLS 冲突)
  bool _isBuiltInAccount(String id) =>
      builtInAccounts().any((a) => a.id == id);

  /// 判断是否为内置分类(固定 uuid,各用户本地一致,不应上传云端,避免多用户 RLS 冲突)
  bool _isBuiltInCategory(String id) =>
      builtInCategories().any((c) => c.id == id);

  // ---------------- 云端读写 ----------------
  /// 从云端拉取当前用户全部数据(RLS 保证只能读到自己的)
  Future<AppData?> fetchCloud() async {
    if (!isSignedIn) return null;
    try {
      final acc = await _sb.from('accounts').select();
      final cat = await _sb.from('categories').select();
      final tx = await _sb.from('transactions').select();
      // loans 表可能尚未在 Supabase 创建(用户未跑 schema.sql)。
      // 单独容错:拉不到就当空列表,绝不让借还表把记账主流程的同步整体拖成失败。
      List loan = const [];
      try {
        loan = (await _sb.from('loans').select()) as List;
      } catch (e) {
        lastLoansError = e.toString();
        loan = const [];
      }
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
        loans: (loan as List)
            .map((e) => Loan.fromCloud(Map<String, dynamic>.from(e as Map)))
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

  Future<void> pushCategories(List<Category> list) async {
    for (final c in list) {
      if (_isBuiltInCategory(c.id)) continue; // 内置分类不上云,避免多用户固定 id 冲突
      await pushCategory(c);
    }
  }

  Future<void> deleteCategory(String id) async {
    if (_isBuiltInCategory(id)) return; // 内置分类不存在于云端,无需删除
    final uid = userId;
    if (uid == null) return;
    try {
      await _sb.from('categories').delete().eq('id', id);
    } catch (_) {
      // 忽略(可能本地无云端)
    }
  }

  /// 内置标准分类集(使用固定 uuid,跨设备/调用一致,避免重复补齐)
  /// 支出:餐饮/交通/购物/娱乐/其他/早餐/午餐/晚餐/饮料饮食
  /// 收入:工资/奖金/其他收入/生活费
  static List<Category> builtInCategories() => [
        Category(id: 'a1111111-1111-4111-8111-111111111111', name: '餐饮', icon: '🍔', type: TxType.expense),
        Category(id: 'a2222222-2222-4222-8222-222222222222', name: '交通', icon: '🚌', type: TxType.expense),
        Category(id: 'a3333333-3333-4333-8333-333333333333', name: '购物', icon: '🛍️', type: TxType.expense),
        Category(id: 'a4444444-4444-4444-8444-444444444444', name: '娱乐', icon: '🎮', type: TxType.expense),
        Category(id: 'a5555555-5555-4555-8555-555555555555', name: '其他', icon: '📦', type: TxType.expense),
        Category(id: 'a6666666-6666-4666-8666-666666666666', name: '早餐', icon: '🍳', type: TxType.expense),
        Category(id: 'a7777777-7777-4777-8777-777777777777', name: '午餐', icon: '🍱', type: TxType.expense),
        Category(id: 'a8888888-8888-4888-8888-888888888888', name: '晚餐', icon: '🍲', type: TxType.expense),
        Category(id: 'a9999999-9999-4999-8999-999999999999', name: '饮料饮食', icon: '🥤', type: TxType.expense),
        Category(id: 'b1111111-1111-4111-8111-111111111111', name: '工资', icon: '💰', type: TxType.income),
        Category(id: 'b2222222-2222-4222-8222-222222222222', name: '奖金', icon: '🎁', type: TxType.income),
        Category(id: 'b3333333-3333-4333-8333-333333333333', name: '其他收入', icon: '✨', type: TxType.income),
        Category(id: 'b4444444-4444-4444-8444-444444444444', name: '生活费', icon: '💴', type: TxType.income),
      ];

  /// 内置标准账户集(固定 uuid,跨设备/调用一致)
  /// 现金 / 银行卡 / 支付宝 / 微信
  static List<Account> builtInAccounts() => [
        Account(id: 'c1111111-1111-4111-8111-111111111111', name: '现金', currency: '¥'),
        Account(id: 'c2222222-2222-4222-8222-222222222222', name: '银行卡', currency: '¥'),
        Account(id: 'c3333333-3333-4333-8333-333333333333', name: '支付宝', currency: '¥'),
        Account(id: 'c4444444-4444-4444-8444-444444444444', name: '微信', currency: '¥'),
      ];

  Future<void> pushAccounts(List<Account> list) async {
    for (final a in list) {
      if (_isBuiltInAccount(a.id)) continue; // 内置账户不上云,避免多用户固定 id 冲突
      await pushAccount(a);
    }
  }

  Future<void> deleteAccount(String id) async {
    if (_isBuiltInAccount(id)) return; // 内置账户不存在于云端,无需删除
    final uid = userId;
    if (uid == null) return;
    try {
      await _sb.from('accounts').delete().eq('id', id);
    } catch (_) {
      // 忽略(可能本地无云端)
    }
  }

  /// 补齐内置账户:缺失则补齐,同名重复则归并(保留内置固定 id,交易 accountId 一并迁移)
  Future<AppData> ensureBuiltInAccounts(AppData local) async {
    final builtIns = builtInAccounts();
    final builtInIds = {for (final a in builtIns) a.id};
    var accs = List<Account>.from(local.accounts);
    var txns = List<Txn>.from(local.transactions);
    final changedTxns = <Txn>[];
    var changed = false;

    final groups = <String, List<Account>>{};
    for (final a in accs) groups.putIfAbsent(a.name, () => []).add(a);
    final removedIds = <String>{};
    for (final list in groups.values) {
      if (list.length <= 1) continue;
      final keep =
          list.firstWhere((a) => builtInIds.contains(a.id), orElse: () => list.first);
      for (final dup in list) {
        if (dup.id == keep.id) continue;
        removedIds.add(dup.id);
        txns = txns.map((t) {
          if (t.accountId == dup.id) {
            final nt = t.copyWith(accountId: keep.id);
            changedTxns.add(nt);
            return nt;
          }
          return t;
        }).toList();
        changed = true;
      }
    }
    if (removedIds.isNotEmpty) {
      accs = accs.where((a) => !removedIds.contains(a.id)).toList();
    }

    final existing = {for (final a in accs) a.name};
    for (final b in builtIns) {
      if (!existing.contains(b.name)) {
        accs.add(b);
        changed = true;
      }
    }

    if (!changed) return local;
    final merged = local.copyWith(accounts: accs, transactions: txns);
    await saveLocal(merged);
    if (isSignedIn) {
      await pushAccounts(accs);
      for (final t in changedTxns) await pushTxn(t);
      for (final id in removedIds) await deleteAccount(id);
    }
    return merged;
  }

  /// 补齐内置分类:
  /// 1) 旧"居家"就地改名"其他"(保留 id,交易关联不断)
  /// 2) 清理同名重复分类(如曾出现的双"其他"):保留内置固定 id 的那条,其余把交易归并到保留条后删除
  /// 3) 把标准集中仍缺失的分类补齐
  /// 已登录时同步推云端。返回补齐后的数据。
  Future<AppData> ensureBuiltInCategories(AppData local) async {
    final builtIns = builtInCategories();
    final builtInIds = {for (final b in builtIns) b.id};
    var cats = List<Category>.from(local.categories);
    var txns = List<Txn>.from(local.transactions);
    final changedTxns = <Txn>[];
    var changed = false;

    // 1) 居家 -> 其他(保留 id)
    final hi = cats.indexWhere((c) => c.name == '居家');
    if (hi >= 0) {
      cats[hi] = cats[hi].copyWith(name: '其他', icon: '📦');
      changed = true;
    }

    // 2) 同名去重:保留 builtIn id 优先,其余交易归并到保留条并删除
    final groups = <String, List<Category>>{};
    for (final c in cats) groups.putIfAbsent(c.name, () => []).add(c);
    final removedIds = <String>{};
    for (final list in groups.values) {
      if (list.length <= 1) continue;
      final keep =
          list.firstWhere((c) => builtInIds.contains(c.id), orElse: () => list.first);
      for (final dup in list) {
        if (dup.id == keep.id) continue;
        removedIds.add(dup.id);
        txns = txns.map((t) {
          if (t.categoryId == dup.id) {
            final nt = t.copyWith(categoryId: keep.id);
            changedTxns.add(nt);
            return nt;
          }
          return t;
        }).toList();
        changed = true;
      }
    }
    if (removedIds.isNotEmpty) {
      cats = cats.where((c) => !removedIds.contains(c.id)).toList();
    }

    // 3) 补齐缺失的内置分类(基于去重/改名后的状态判断)
    final existing = {for (final c in cats) c.name};
    for (final b in builtIns) {
      if (!existing.contains(b.name)) {
        cats.add(b);
        changed = true;
      }
    }

    if (!changed) return local;
    final merged = local.copyWith(categories: cats, transactions: txns);
    await saveLocal(merged);
    if (isSignedIn) {
      await pushCategories(cats);
      for (final t in changedTxns) {
        await pushTxn(t);
      }
      for (final id in removedIds) {
        await deleteCategory(id);
      }
    }
    return merged;
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

  Future<void> pushLoan(Loan l) async {
    final uid = userId;
    if (uid == null) return;
    try {
      await _sb.from('loans').upsert(l.toCloud(uid));
      lastLoansError = null;
    } catch (e) {
      lastLoansError = e.toString();
      // 例外:loans 表可能尚未在云端创建,不能影响记账数据同步
    }
  }

  Future<void> deleteLoan(String id) async {
    final uid = userId;
    if (uid == null) return;
    try {
      await _sb.from('loans').delete().eq('id', id);
    } catch (_) {
      // 忽略(可能本地无云端)
    }
  }

  /// 全量推送(新用户首次把本地示例数据上传到云端)
  /// 注意:内置账户/分类不上云,避免多用户因固定 id 冲突触发 RLS 错误
  Future<void> pushAll(AppData data) async {
    for (final a in data.accounts) {
      if (_isBuiltInAccount(a.id)) continue;
      await pushAccount(a);
    }
    for (final c in data.categories) {
      if (_isBuiltInCategory(c.id)) continue;
      await pushCategory(c);
    }
    for (final t in data.transactions) {
      await pushTxn(t);
    }
    for (final l in data.loans) {
      await pushLoan(l);
    }
  }

  // ---------------- 示例数据 ----------------
  /// id 由 uuid 自动生成;交易通过对象引用账户/分类,保证外键有效
  AppData seed() {
    final accounts = builtInAccounts();
    Account byAcc(String n) => accounts.firstWhere((a) => a.name == n);
    final cash = byAcc('现金');
    final bank = byAcc('银行卡');
    final alipay = byAcc('支付宝');

    final categories = builtInCategories();
    Category byName(String n) =>
        categories.firstWhere((c) => c.name == n);
    final food = byName('餐饮');
    final transport = byName('交通');
    final shop = byName('购物');
    final fun = byName('娱乐');
    final other = byName('其他');
    final salary = byName('工资');
    final bonus = byName('奖金');

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
      mk(5, 120, TxType.expense, other, bank, '日用品'),
      mk(6, 500, TxType.income, bonus, alipay, '兼职'),
      mk(8, 28, TxType.expense, food, alipay, '外卖'),
      mk(10, 60, TxType.expense, transport, cash, '打车'),
      mk(12, 88, TxType.expense, shop, bank, '零食'),
    ];

    // 借入借出示例
    Loan mkLoan(LoanType t, String person, double amt, int dayOffset,
            int dueInDays, String note) =>
        Loan(
          type: t,
          person: person,
          amount: amt,
          date: base.subtract(Duration(days: dayOffset)),
          dueDate: base.add(Duration(days: dueInDays)),
          note: note,
        );
    final loans = [
      mkLoan(LoanType.borrowOut, '张三', 500, 5, 30, '周转一下'),
      mkLoan(LoanType.borrowIn, '李四', 200, 10, 15, '上次吃饭垫付'),
      mkLoan(LoanType.borrowOut, '王五', 1000, 20, 60, '借去交房租'),
    ];

    return AppData(
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      loans: loans,
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
    // loans
    final localLoan = {for (final l in local.loans) l.id: l};
    final mergedLoan = <Loan>[];
    final seenLoan = <String>{};
    for (final c in cloud.loans) {
      seenLoan.add(c.id);
      final l = localLoan[c.id];
      if (l == null || c.updatedAt.isAfter(l.updatedAt)) {
        mergedLoan.add(c);
      } else {
        mergedLoan.add(l);
      }
    }
    for (final l in local.loans) {
      if (!seenLoan.contains(l.id)) mergedLoan.add(l);
    }
    return AppData(
      accounts: merged,
      categories: mergedCat,
      transactions: mergedTx,
      loans: mergedLoan,
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
