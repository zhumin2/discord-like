import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../server_version.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// 登录/注册页：可设置服务器地址（手机真机连局域网 IP 用）。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isRegister = false;
  bool _busy = false;
  bool _showServer = false;
  String? _err;

  final _usernameCtl = TextEditingController();
  final _passwordCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 演示账号快捷填充
    _usernameCtl.text = '';
  }

  @override
  void dispose() {
    _usernameCtl.dispose();
    _passwordCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameCtl.text.trim();
    final password = _passwordCtl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _err = '请输入用户名和密码');
      return;
    }
    setState(() { _busy = true; _err = null; });
    try {
      final api = ApiClient(
        base: ref.read(serverBaseProvider),
        token: null,
      );
      final (token, _) = _isRegister
          ? await api.register(username, password)
          : await api.login(username, password);
      if (!mounted) return;
      await ref.read(tokenProvider.notifier).set(token);
      // chatProvider 监听 token 变化会自动引导加载
    } on ApiException catch (e) {
      setState(() => _err = e.message);
    } catch (e) {
      setState(() => _err = '连接失败，请检查服务器地址');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fillDemo() {
    setState(() {
      _isRegister = false;
      _usernameCtl.text = 'alice';
      _passwordCtl.text = '123456';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChordColors.bgDarkest,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: ChordColors.bgDarker,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 20)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('assets/logo.png', width: 84, height: 84),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRegister ? '创建一个账号' : '欢迎回来！',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, color: ChordColors.textBright),
                ),
                const SizedBox(height: 6),
                Text(
                  _isRegister ? '加入 Chord，开始畅聊' : '我们很高兴又见到你！',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: ChordColors.textMuted),
                ),
                const SizedBox(height: 24),
                // 登录/注册切换
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('登录')),
                    ButtonSegment(value: true, label: Text('注册')),
                  ],
                  selected: {_isRegister},
                  onSelectionChanged: (s) => setState(() {
                    _isRegister = s.first;
                    _err = null;
                  }),
                ),
                const SizedBox(height: 20),
                const Text('用户名',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: ChordColors.textMuted)),
                const SizedBox(height: 8),
                TextField(
                  controller: _usernameCtl,
                  decoration: const InputDecoration(hintText: '用户名'),
                ),
                const SizedBox(height: 16),
                const Text('密码',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: ChordColors.textMuted)),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordCtl,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(hintText: '密码'),
                ),
                // 服务器地址（折叠）
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => _showServer = !_showServer),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          _showServer ? Icons.expand_less : Icons.expand_more,
                          size: 16, color: ChordColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        const Text('服务器地址',
                            style: TextStyle(fontSize: 12, color: ChordColors.textMuted)),
                      ],
                    ),
                  ),
                ),
                if (_showServer)
                  _ServerField(),
                if (_err != null) ...[
                  const SizedBox(height: 10),
                  Text(_err!, style: const TextStyle(color: ChordColors.red, fontSize: 13)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ChordColors.blurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isRegister ? '注册并进入' : '登录',
                          style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _fillDemo,
                  child: const Text('使用演示账号 (alice / 123456)',
                      style: TextStyle(fontSize: 13, color: ChordColors.textMuted)),
                ),
                const SizedBox(height: 2),
                const VersionText(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerField extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ServerField> createState() => _ServerFieldState();
}

class _ServerFieldState extends ConsumerState<_ServerField> {
  late final TextEditingController _ctl =
      TextEditingController(text: ref.read(serverBaseProvider));

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: TextField(
        controller: _ctl,
        decoration: const InputDecoration(
          hintText: 'http://192.168.x.x:8080（手机端填电脑局域网 IP）',
          helperStyle: TextStyle(fontSize: 11),
        ),
        onChanged: (v) => ref.read(serverBaseProvider.notifier).set(v),
      ),
    );
  }
}
