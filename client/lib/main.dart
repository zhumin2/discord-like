import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

/// 托盘未读角标：把未读总数同步给原生层（仅 Windows 桌面有效）。
/// Web/Android 上该通道不存在，静默忽略。
int _lastTrayBadge = -1;
Future<void> _syncTrayBadge(int total) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  if (total == _lastTrayBadge) return;
  _lastTrayBadge = total;
  try {
    await const MethodChannel('chord/app').invokeMethod('setBadge', total);
  } catch (_) {
    // 原生通道未注册（例如 flutter run 调试早期）时忽略
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 恢复持久化的登录态与服务器地址
  await ServerBaseNotifier.restore();
  await TokenNotifier.restore();
  runApp(const ProviderScope(child: ChordApp()));
}

class ChordApp extends ConsumerWidget {
  const ChordApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.watch(tokenProvider);
    final chat = ref.watch(chatProvider);

    // 未读总数变化 → 更新托盘角标（服务器频道 + 私信都计入 summary）
    ref.listen<int>(
      chatProvider.select((s) =>
          s.summary.values.fold<int>(0, (a, x) => a + x.unread)),
      (_, total) => _syncTrayBadge(total),
    );

    return MaterialApp(
      title: 'Chord',
      debugShowCheckedModeBanner: false,
      theme: buildChordTheme(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: token == null
            ? const LoginScreen(key: ValueKey('login'))
            : _HomeGate(loading: chat.loading, error: chat.error),
      ),
      // 全局错误 toast：state.error 变化时弹出
      builder: (context, child) => _ErrorToast(child: child),
    );
  }
}

/// 登录后的加载门（等待 bootstrap 完成）。
class _HomeGate extends ConsumerWidget {
  final bool loading;
  final String? error;
  const _HomeGate({required this.loading, this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loading) {
      return Scaffold(
        backgroundColor: ChordColors.bgDarkest,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.forum, size: 56, color: ChordColors.blurple),
              SizedBox(height: 24),
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 12),
              Text('正在连接 Chord…', style: TextStyle(color: ChordColors.textMuted)),
            ],
          ),
        ),
      );
    }
    return const HomeShell();
  }
}

/// 监听 chatProvider.error，弹 SnackBar。
class _ErrorToast extends ConsumerStatefulWidget {
  final Widget? child;
  const _ErrorToast({this.child});

  @override
  ConsumerState<_ErrorToast> createState() => _ErrorToastState();
}

class _ErrorToastState extends ConsumerState<_ErrorToast> {
  String? _last;

  @override
  Widget build(BuildContext context) {
    ref.listen(chatProvider.select((s) => s.error), (_, next) {
      if (next != null && next != _last) {
        _last = next;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next),
            behavior: SnackBarBehavior.floating,
            backgroundColor: ChordColors.red,
          ),
        );
        Future.delayed(const Duration(seconds: 3), () {
          ref.read(chatProvider.notifier).clearError();
        });
      }
      if (next == null) _last = null;
    });
    return widget.child ?? const SizedBox.shrink();
  }
}
