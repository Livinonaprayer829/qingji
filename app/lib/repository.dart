import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
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

  // ---------------- 删除墓碑（tombstone）----------------
  //
  // 合并是"并集"：A 删了一条，B 那边还在，B 一同步就会把它并回来（删除被撤销）。
  // 所以删除必须留个"这条已删除"的记录，且**保留一段时间**，让其他设备也能学到。
  // 规则：任一设备删除后，这条永远保持删除（删除优先，不再复活）。
  static const _tombstoneKey = 'deleted_ids_v1';
  static const _tombstoneTtlDays = 180;

  final Map<String, DateTime> _tombstones = {};
  bool _tombstonesLoaded = false;

  /// 云端"标记删除"失败的 id，下次同步重试
  final Set<String> _pendingDeletionPush = {};

  Future<void> _ensureTombstones() async {
    if (_tombstonesLoaded) return;
    _tombstonesLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tombstoneKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cutoff = DateTime.now().subtract(const Duration(days: _tombstoneTtlDays));
      map.forEach((id, v) {
        final t = DateTime.tryParse(v.toString());
        if (t != null && t.isAfter(cutoff)) _tombstones[id] = t;
      });
    } catch (_) {}
  }

  Future<void> _saveTombstones() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _tombstoneKey,
        jsonEncode(_tombstones.map((k, v) => MapEntry(k, v.toIso8601String()))),
      );
    } catch (_) {}
  }

  bool isTombstoned(String id) => _tombstones.containsKey(id);

  Future<void> _addTombstone(String id) async {
    await _ensureTombstones();
    _tombstones[id] = DateTime.now();
    await _saveTombstones();
  }

  /// 记账：标记删除（本地墓碑 + 云端标 deleted_at）
  Future<void> markTxnDeleted(String id) async {
    await _addTombstone(id);
    await _pushDeletionMark(id, 'transactions');
  }

  /// 借还：标记删除
  Future<void> markLoanDeleted(String id) async {
    await _addTombstone(id);
    await _pushDeletionMark(id, 'loans');
  }

  /// 云端把某行标成 deleted_at（不真删，其他设备才学得到）
  Future<void> _pushDeletionMark(String id, String table) async {
    final uid = userId;
    if (uid == null) return;
    try {
      await _sb.from(table).update(
          {'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
    } catch (_) {
      // 列还没加 / 网络问题：记下来，下次同步重试
      _pendingDeletionPush.add(id);
    }
  }

  // ---------------- 全局默认记账账户(本地偏好,不参与云同步) ----------------
  static const _keyDefaultAccount = 'default_account_id';

  Future<String?> loadDefaultAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDefaultAccount);
  }

  Future<void> saveDefaultAccountId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_keyDefaultAccount);
    } else {
      await prefs.setString(_keyDefaultAccount, id);
    }
  }

  // ---------------- 本地缓存 ----------------
  Future<AppData> loadLocal() async {
    await _ensureTombstones();
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
        // 墓碑过滤：删过的东西即使还残留在本地文件里也不再显示
        transactions: (map['transactions'] as List)
            .map((e) => Txn.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((t) => !isTombstoned(t.id))
            .toList(),
        loans: (map['loans'] as List? ?? [])
            .map((e) => Loan.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((l) => !isTombstoned(l.id))
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
    // 名称 → 内置 id。除当前内置名外还包含**改名前的旧名**,
    // 这样老数据/云端里叫「支付宝-余额」的账户也会被归一成内置 id,
    // 不会和新的「支付宝（余额）」并存成两条、也不会留下对不上的 id。
    final builtInAccMap = {
      for (final a in builtInAccounts()) a.name: a.id,
      ..._accountNameAliases,
    };
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
    await _ensureTombstones();
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

      // 云端 deleted_at 非空的行 = 在别的设备上删掉的。
      // 把它们记进本地墓碑（这样本机也会删掉），并且**不进 AppData**。
      final liveTx = <Txn>[];
      for (final e in (tx as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = (m['id'] ?? '').toString();
        if (m['deleted_at'] != null) {
          if (id.isNotEmpty) _tombstones[id] = DateTime.now();
          continue;
        }
        if (id.isNotEmpty && isTombstoned(id)) continue;
        liveTx.add(Txn.fromCloud(m));
      }

      final liveLoans = <Loan>[];
      for (final e in (loan as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = (m['id'] ?? '').toString();
        if (m['deleted_at'] != null) {
          if (id.isNotEmpty) _tombstones[id] = DateTime.now();
          continue;
        }
        if (id.isNotEmpty && isTombstoned(id)) continue;
        liveLoans.add(Loan.fromCloud(m));
      }

      if (_tombstones.isNotEmpty) await _saveTombstones();

      return AppData(
        accounts: (acc as List)
            .map((e) => Account.fromCloud(Map<String, dynamic>.from(e as Map)))
            .toList(),
        categories: (cat as List)
            .map((e) => Category.fromCloud(Map<String, dynamic>.from(e as Map)))
            .toList(),
        transactions: liveTx,
        loans: liveLoans,
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

  /// 内置账户的**旧名称** → 固定 id(改名/早期版本可能残留,老数据和云端里会遇到)
  static const _accountNameAliases = <String, String>{
    '支付宝-余额': AlipayAccounts.balanceId,
    '支付宝-花呗': AlipayAccounts.huabeiId,
  };

  /// 内置标准账户集(固定 uuid,跨设备/调用一致)
  /// 现金 / 银行卡 / 支付宝 / 支付宝（余额）/ 支付宝（花呗）/ 微信
  /// 两个支付宝渠道直接作为账户出现在下拉里,不再走二级弹窗。
  static List<Account> builtInAccounts() => [
        Account(id: 'c1111111-1111-4111-8111-111111111111', name: '现金', currency: '¥'),
        Account(id: 'c2222222-2222-4222-8222-222222222222', name: '银行卡', currency: '¥'),
        Account(id: AlipayAccounts.parentId, name: AlipayAccounts.parentName, currency: '¥'),
        Account(id: AlipayAccounts.balanceId, name: AlipayAccounts.balanceName, currency: '¥'),
        Account(id: AlipayAccounts.huabeiId, name: AlipayAccounts.huabeiName, currency: '¥'),
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

    // 0) 先按 **id** 去重:账户改名前后各留一条时,归一后 id 会相同,
    //    此时直接丢掉多余的一条(同 id 所以不用改交易的 accountId)。
    final byId = <String, Account>{};
    var dupById = false;
    for (final a in accs) {
      final prev = byId[a.id];
      if (prev == null) {
        byId[a.id] = a;
        continue;
      }
      dupById = true;
      // 两条里优先保留"名称等于内置名"的那条(即改名后的新名)
      String? builtInName;
      for (final b in builtIns) {
        if (b.id == a.id) builtInName = b.name;
      }
      if (builtInName != null && prev.name != builtInName) byId[a.id] = a;
    }
    if (dupById) {
      accs = byId.values.toList();
      changed = true;
    }

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

    // 内置账户以 id 为准同步名称(例如改过名的 支付宝-余额 → 支付宝（余额）)。
    // 必须放在下面「按名补齐」之前,否则同一 id 会因改名被再补一条出来。
    for (final b in builtIns) {
      final i = accs.indexWhere((a) => a.id == b.id);
      if (i >= 0 && accs[i].name != b.name) {
        accs[i] = Account(
          id: b.id,
          name: b.name,
          currency: accs[i].currency,
          updatedAt: DateTime.now(),
        );
        changed = true;
      }
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
    // 与分类一致：云端清理是尽力而为，不能因为它抛错而让归一结果丢失
    if (isSignedIn) {
      try {
        await pushAccounts(accs);
        for (final t in changedTxns) await pushTxn(t);
        for (final id in removedIds) await deleteAccount(id);
      } catch (e) {
        debugPrint('cleanup accounts on cloud failed: $e');
      }
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
    // 清理云端多余分类是"尽力而为"：删不掉也不能让整个同步/归一流程抛错，
    // 否则界面会停在"带重复分类"的旧状态上。
    if (isSignedIn) {
      try {
        await pushCategories(cats);
        for (final t in changedTxns) {
          await pushTxn(t);
        }
        for (final id in removedIds) {
          await deleteCategory(id);
        }
      } catch (e) {
        debugPrint('cleanup categories on cloud failed: $e');
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

  /// 最近一次全量推送的错误（供同步页展示；null = 成功）
  String? lastPushError;

  /// 全量推送(新用户首次把本地示例数据上传到云端)
  /// 注意:内置账户/分类不上云,避免多用户因固定 id 冲突触发 RLS 错误
  ///
  /// 单条失败**不再中断整批**：逐条记错、最后汇总抛一次，
  /// 这样几百条流水里坏了一条，不会让整个同步流程报废。
  /// 流水按 10 条并发推，避免 200+ 条串行导致代理层超时。
  Future<void> pushAll(AppData data) async {
    final errs = <String>[];

    for (final a in data.accounts) {
      if (_isBuiltInAccount(a.id)) continue;
      try {
        await pushAccount(a);
      } catch (e) {
        errs.add('账户「${a.name}」: $e');
      }
    }
    for (final c in data.categories) {
      if (_isBuiltInCategory(c.id)) continue;
      try {
        await pushCategory(c);
      } catch (e) {
        errs.add('分类「${c.name}」: $e');
      }
    }

    const batchSize = 10;
    for (var i = 0; i < data.transactions.length; i += batchSize) {
      final slice = data.transactions.skip(i).take(batchSize).toList();
      final results = await Future.wait(slice.map((t) async {
        try {
          await pushTxn(t);
          return null;
        } catch (e) {
          return '流水 ${t.date.year}/${t.date.month}/${t.date.day}: $e';
        }
      }));
      for (final r in results) {
        if (r != null) errs.add(r);
      }
    }

    for (final l in data.loans) {
      try {
        await pushLoan(l);
      } catch (e) {
        errs.add('借还「${l.person}」: $e');
      }
    }

    lastPushError = errs.isEmpty ? null : errs.first;

    // 重试之前"标记删除"失败的（列刚加好 / 当时网络抖动）
    if (_pendingDeletionPush.isNotEmpty) {
      final retry = List<String>.from(_pendingDeletionPush);
      for (final id in retry) {
        try {
          await _sb
              .from('transactions')
              .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
              .eq('id', id);
          _pendingDeletionPush.remove(id);
        } catch (_) {
          try {
            await _sb
                .from('loans')
                .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
                .eq('id', id);
            _pendingDeletionPush.remove(id);
          } catch (_) {}
        }
      }
    }

    if (errs.isNotEmpty) {
      throw Exception('共 ${errs.length} 条上传失败，例：${errs.first}');
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

    // ⚠️ 合并后必须**按名称收敛分类**：
    // 云端可能同时存在「购物(内置固定 id)」和「购物(早期旧 id)」两种记录，
    // 按 id 求并集会把它们都留下 ⇒ 记账页出现一堆重复分类。
    // 这里以"内置 id 优先"为准则合并同名分类，并把流水上的 categoryId 归并过去。
    final (dedupedCats, dedupedTx) = _dedupeCategoriesByName(mergedCat, mergedTx);

    return AppData(
      accounts: merged,
      categories: dedupedCats,
      // 墓碑过滤：删掉的东西**永远不参与合并**，否则会被另一台设备"复活"
      transactions: dedupedTx.where((t) => !isTombstoned(t.id)).toList(),
      loans: mergedLoan.where((l) => !isTombstoned(l.id)).toList(),
    );
  }

  /// 分类按**名称**去重（内置 id 优先），并把流水的 categoryId 归并到保留条。
  /// 返回 (去重后的分类, 归并后的流水)。
  (List<Category>, List<Txn>) _dedupeCategoriesByName(
      List<Category> cats, List<Txn> txns) {
    final builtInIds = {for (final b in builtInCategories()) b.id};
    final groups = <String, List<Category>>{};
    for (final c in cats) {
      groups.putIfAbsent(c.name, () => []).add(c);
    }

    final keepIdByDupId = <String, String>{};
    final kept = <Category>[];
    for (final list in groups.values) {
      final keep = list.firstWhere((c) => builtInIds.contains(c.id),
          orElse: () => list.first);
      kept.add(keep);
      for (final c in list) {
        if (c.id != keep.id) keepIdByDupId[c.id] = keep.id;
      }
    }
    if (keepIdByDupId.isEmpty) return (cats, txns);

    final fixedTx = txns.map((t) {
      final to = keepIdByDupId[t.categoryId];
      return to == null ? t : t.copyWith(categoryId: to);
    }).toList();
    return (kept, fixedTx);
  }

  /// 增量双向同步:拉云端 → 按 updatedAt 合并 → 推送 → 写回本地
  /// 增量同步：拉云端 → 与本地按 updatedAt 合并 → **先落地到本地** → 再尽力回推。
  ///
  /// 顺序很关键：之前是"合并→推送→写本地"，只要推送抛错（RLS/外键/超时），
  /// 本地就一条也拿不到（表现为同步页"本地 0 条 / 云端 249 条"，怎么点都同步不起来）。
  /// 现在**先 saveLocal 再推**，上传失败只记录 [lastPushError]，不影响本地数据。
  Future<AppData?> syncIncremental(AppData local) async {
    if (!isSignedIn) return null;
    final cloud = await fetchCloud();
    if (cloud == null) return null;
    final merged = mergeWithCloud(local, cloud);

    // ① 先把合并结果落地：这一步成功，本地就一定有数据
    await saveLocal(merged);

    // ② 再尽力回推到云端：失败不阻断，错误留给同步页展示
    try {
      await pushAll(merged);
    } catch (_) {
      // lastPushError 已在 pushAll 里记录
    }
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
