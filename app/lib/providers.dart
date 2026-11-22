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

/// 全局默认记账账户(本地偏好,不参与云同步)。
/// 为空时记账页沿用原逻辑(取第一个账户)。
final defaultAccountProvider =
    NotifierProvider<DefaultAccountNotifier, String?>(
        DefaultAccountNotifier.new);

class DefaultAccountNotifier extends Notifier<String?> {
  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final id = await ref.read(repositoryProvider).loadDefaultAccountId();
    if (id != null) state = id;
  }

  /// 设为默认账户;传 null 表示取消默认
  Future<void> setAccount(String? id) async {
    state = id;
    await ref.read(repositoryProvider).saveDefaultAccountId(id);
  }
}

class AppDataNotifier extends Notifier<AppData> {
  late final DataRepository _repo;
  bool _syncing = false;

  @override
  AppData build() {
    _repo = ref.read(repositoryProvider);
    _init();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session == null) {
        _onSignedOut();
        return;
      }
      // 只在「真正登录 / 首次恢复会话」时向云端拉取。
      // ⚠️ tokenRefreshed 大约每小时触发一次（App 回到前台也可能触发），
      // 如果那时正在记账：刚保存的流水还没推上去，云端快照里没有它，
      // 一拉一覆盖 → 本地少一条、云端多一条，过一会儿又"冒出来"。
      final ev = data.event;
      if (ev == AuthChangeEvent.signedIn ||
          ev == AuthChangeEvent.initialSession) {
        _syncFromCloud();
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

  /// 登录后从云端拉取;新用户云端为空则 seed 并上传。
  ///
  /// 关键:所有"补齐内置账户/分类 + 旧 id 归一"都必须**在赋值给 state 之前**做完。
  /// 之前是 `state = cloud;` 再补内置账户——而内置账户(支付宝-余额/花呗等)不在云端,
  /// 于是存在一个**短暂的空窗**:列表里这些账户会突然消失。如果这时正好打开它们的
  /// 账户详情页,就会渲染出"该账户已不存在"(返回再进又好了)。
  /// 现在合并成一次赋值,中间态不再暴露给 UI。
  ///
  /// 关键 2:**不要用云端快照整体覆盖本地**,而是按 `updatedAt` 双向合并。
  /// 否则会出现:刚记的一笔已经进 state 并写进本地,但推送还没落地;
  /// 此刻来一次同步 → 云端快照里没有这笔 → 本地被覆盖 → 这笔"消失"
  /// (同步页显示"本地 196 / 云端 197"),等下一次同步才回来。
  Future<void> _syncFromCloud() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final cloud = await _repo.fetchCloud();
      if (cloud == null) return;

      // 全新账号 + 全新设备：造一份示例数据打底
      if (cloud.isEmpty && state.isEmpty) {
        state = _repo.seed();
        await _repo.saveLocal(state);
        await _repo.pushAll(state);
      }

      // 本地 + 云端按 updatedAt 合并（本地更新的留本地，云端特有的补进来），
      // 合并结果再整体推一次云端，保证两边一致。
      final mergedLocal = await _repo.syncIncremental(state);

      var next = mergedLocal ?? state;
      // 同步过程中（拉取/推送要几秒）用户可能又记了一笔——addTx 会先更新 state。
      // 这里把"当前 state"再合并进来，避免这几秒里的新记录被合并结果覆盖掉。
      next = _repo.mergeWithCloud(state, next);

      // ① 先交给界面：万一后面的归一出错，也不会出现"本地 0 条"的空列表
      state = next;

      // ② 归一(旧 id/旧名)→ 补齐内置账户、内置分类（失败不影响已拿到的数据）
      try {
        next = await _repo.migrateIdsToUuid(next);
        next = await _repo.ensureBuiltInAccounts(next);
        next = await _repo.ensureBuiltInCategories(next);
      } catch (e) {
        debugPrint('sync normalize failed: $e');
      }

      state = next;
      await _repo.saveLocal(state);
      lastSyncError = null;
    } catch (e) {
      // 登录后的自动同步失败：**不要静默**，把原文留在同步页
      lastSyncError = e.toString();
      debugPrint('login sync failed: $e');
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
    // 先记"墓碑"（本地持久化 + 云端 deleted_at）：这样即使另一台设备还留着这条，
    // 下次合并也不会把它并回来（删除优先，删了就不会复活）。
    await _repo.markTxnDeleted(id);
    state = state.copyWith(
      transactions: state.transactions.where((e) => e.id != id).toList(),
    );
    await _repo.saveLocal(state);
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
    await _repo.markLoanDeleted(id);
    state = state.copyWith(
      loans: state.loans.where((e) => e.id != id).toList(),
    );
    await _repo.saveLocal(state);
  }

  /// 增量双向同步:按 updatedAt 合并本地+云端,推送合并结果,写回本地
  Future<AppData?> syncIncremental() async {
    try {
      final merged = await _repo.syncIncremental(state);
      if (merged != null) state = merged;
      lastSyncError = null;
      return merged;
    } catch (e) {
      lastSyncError = e.toString();
      rethrow;
    }
  }

  /// 借还同步最近一次错误(用于同步页提示)。null 表示成功或尚未同步。
  String? get lastLoansError => _repo.lastLoansError;

  /// 最近一次"回推云端"的错误。null = 成功。
  /// 注意：即使它不为 null，本地数据也已经是最新合并结果（上传失败不影响本地）。
  String? get lastPushError => _repo.lastPushError;

  /// 最近一次同步流程本身的错误（拉取/合并/归一 任一步失败）。
  /// 会**常驻**显示在同步页，方便定位问题，不会像 Toast 一样一闪就没。
  String? lastSyncError;

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