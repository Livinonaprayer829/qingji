import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'repository.dart';

final repositoryProvider = Provider((ref) => DataRepository());

/// 用户是否选择了"离线模式"(未登录但进入主页)
final offlineModeProvider = StateProvider<bool>((ref) => false);

final appDataProvider =
    NotifierProvider<AppDataNotifier, AppData>(AppDataNotifier.new);

class AppDataNotifier extends Notifier<AppData> {
  late final DataRepository _repo;
  bool _syncing = false;

  @override
  AppData build() {
    _repo = ref.read(repositoryProvider);
    _init();
    Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.session != null) {
        _syncFromCloud();
      } else {
        _onSignedOut();
      }
    });
    return AppData.empty();
  }

  Future<void> _init() async {
    state = await _repo.loadLocal();
    state = await _repo.migrateIdsToUuid(state);
    state = await _repo.ensureBuiltInAccounts(state);
    state = await _repo.ensureBuiltInCategories(state);
    if (_repo.isSignedIn) await _syncFromCloud();
  }

  Future<void> _tryPush(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      // 自动同步失败只记录,不阻断本地流程;用户可在同步页看到手动同步的错误详情。
      debugPrint('auto sync push failed: $e');
    }
  }

  /// 退出登录:仅清掉离线模式标记与 session,本地数据保留(可在离线模式继续使用)
  Future<void> _onSignedOut() async {
    ref.read(offlineModeProvider.notifier).state = false;
  }

  /// 登录后从云端拉取;新用户云端为空则 seed 并上传
  Future<void> _syncFromCloud() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final cloud = await _repo.fetchCloud();
      if (cloud == null) return;
      if (cloud.isEmpty) {
        if (state.isEmpty) state = _repo.seed();
        await _repo.pushAll(state);
        final refreshed = await _repo.fetchCloud();
        if (refreshed != null) state = refreshed;
      } else {
        state = cloud;
      }
      state = await _repo.ensureBuiltInAccounts(state);
      state = await _repo.ensureBuiltInCategories(state);
      await _repo.saveLocal(state);
    } finally {
      _syncing = false;
    }
  }

  /// 写入时刷新 updatedAt,用于 last-write-wins
  Txn _bump(Txn tx) => Txn(
        id: tx.id,
        amount: tx.amount,
        type: tx.type,
        categoryId: tx.categoryId,
        accountId: tx.accountId,
        date: tx.date,
        note: tx.note,
        updatedAt: DateTime.now(),
      );

  Future<void> addTx(Txn tx) async {
    final bumped = _bump(tx);
    state = state.copyWith(transactions: [...state.transactions, bumped]);
    await _repo.saveLocal(state);
    await _tryPush(() => _repo.pushTxn(bumped));
  }

  Future<void> updateTx(Txn tx) async {
    final bumped = _bump(tx);
    state = state.copyWith(
      transactions:
          state.transactions.map((e) => e.id == tx.id ? bumped : e).toList(),
    );
    await _repo.saveLocal(state);
    await _tryPush(() => _repo.pushTxn(bumped));
  }

  Future<void> deleteTx(String id) async {
    state = state.copyWith(
      transactions: state.transactions.where((e) => e.id != id).toList(),
    );
    await _repo.saveLocal(state);
    await _tryPush(() => _repo.deleteTxn(id));
  }

  /// 写入时刷新 updatedAt,用于 last-write-wins
  Loan _bumpLoan(Loan l) => Loan(
        id: l.id,
        type: l.type,
        person: l.person,
        amount: l.amount,
        date: l.date,
        dueDate: l.dueDate,
        repaid: l.repaid,
        repaidDate: l.repaidDate,
        note: l.note,
        updatedAt: DateTime.now(),
      );

  Future<void> addLoan(Loan l) async {
    final bumped = _bumpLoan(l);
    state = state.copyWith(loans: [...state.loans, bumped]);
    await _repo.saveLocal(state);
    await _tryPush(() => _repo.pushLoan(bumped));
  }

  Future<void> updateLoan(Loan l) async {
    final bumped = _bumpLoan(l);
    state = state.copyWith(
      loans: state.loans.map((e) => e.id == l.id ? bumped : e).toList(),
    );
    await _repo.saveLocal(state);
    await _tryPush(() => _repo.pushLoan(bumped));
  }

  Future<void> deleteLoan(String id) async {
    state = state.copyWith(
      loans: state.loans.where((e) => e.id != id).toList(),
    );
    await _repo.saveLocal(state);
    await _tryPush(() => _repo.deleteLoan(id));
  }

  /// 增量双向同步:按 updatedAt 合并本地+云端,推送合并结果,写回本地
  Future<AppData?> syncIncremental() async {
    final merged = await _repo.syncIncremental(state);
    if (merged != null) state = merged;
    return merged;
  }

  /// 借还同步最近一次错误(用于同步页提示)。null 表示成功或尚未同步。
  String? get lastLoansError => _repo.lastLoansError;

  /// 强制覆盖上传:本地全量推云端
  Future<void> forceUpload() async => _repo.forceUpload(state);

  /// 从云端下载覆盖本地
  Future<void> downloadFromCloud() async {
    final cloud = await _repo.downloadFromCloud();
    if (cloud != null) state = cloud;
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    // onAuthStateChange 触发后,_onSignedOut 自动清掉离线标记
  }
}