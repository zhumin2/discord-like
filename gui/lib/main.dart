import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() => runApp(const ChordConsoleApp());

// ============================================================
// 配置
// ============================================================
class Cfg {
  static const apiPort = 8081;
  static const webPort = 3000;
  static const mysqlPort = 3306;

  /// MySQL 便携版位置（按需修改）
  static const mysqlBin = r'F:\dev\runtimes\mysql\bin';
  static const mysqlData = r'F:\dev\runtimes\mysql\data';

  /// 项目根目录：优先从 exe 位置向上找（含 server\cmd 标记），找不到用默认值
  static late final String projectRoot = _findRoot();
  static String _findRoot() {
    var dir = File(Platform.resolvedExecutable).parent.path;
    for (var i = 0; i < 8; i++) {
      if (Directory('$dir\\server\\cmd').existsSync()) return dir;
      final up = Directory(dir).parent.path;
      if (up == dir) break;
      dir = up;
    }
    return r'F:\code\discord-like';
  }

  static String get serverExe => '$projectRoot\\server\\chord-server.exe';
  static String get webExe => '$projectRoot\\server\\serveweb.exe';
  static String get serverSrc => '$projectRoot\\server';
  static String get webRoot => '$projectRoot\\client\\build\\web';
  static String get clientDir => '$projectRoot\\client';
  static String get logsDir => '$projectRoot\\logs';
  static String get chatAppExe => '$projectRoot\\app\\Chord聊天.exe';
  static String logPath(String svc) => '$logsDir\\chord-$svc.log';
}

// ============================================================
// 服务控制核心
// ============================================================
enum SvcState { running, stopped, starting, stopping, building }

class Controllers {
  static Process? apiProc;
  static Process? webProc;
  static Process? mysqlProc;

  static String get now {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  }

  static IOSink? _sink(String svc) {
    try {
      Directory(Cfg.logsDir).createSync(recursive: true);
      return File(Cfg.logPath(svc)).openWrite(mode: FileMode.append);
    } catch (_) {
      return null;
    }
  }

  static void log(String svc, String line) {
    final s = _sink(svc);
    s?.writeln('[${now}] $line');
    s?.flush();
  }

  static Future<void> attach(Process p, String svc) async {
    final sink = _sink(svc);
    p.stdout.transform(systemEncoding.decoder).transform(const LineSplitter()).listen((l) {
      sink?.writeln(l);
      sink?.flush();
    });
    p.stderr.transform(systemEncoding.decoder).transform(const LineSplitter()).listen((l) {
      sink?.writeln(l);
      sink?.flush();
    });
  }

  // ---- 端口/健康探测 ----
  static Future<bool> portOpen(int port) async {
    try {
      final s = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 600));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> apiHealthy() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:${Cfg.apiPort}/api/health'));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      final body = await resp.transform(utf8.decoder).first;
      client.close();
      return body.contains('ok');
    } catch (_) {
      return false;
    }
  }

  static Future<int?> findPid(int port) async {
    final r = await Process.run('netstat', ['-ano']);
    for (final line in r.stdout.toString().split('\n')) {
      if ((line.contains(':$port ') || line.contains(':$port\t')) &&
          line.toUpperCase().contains('LISTENING')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        final pid = int.tryParse(parts.last);
        if (pid != null && pid != 0) return pid;
      }
    }
    return null;
  }

  static Future<void> killPid(int pid) async {
    await Process.run('taskkill', ['/F', '/PID', '$pid']);
  }

  static Future<void> openUrl(String url) async {
    await Process.run('cmd', ['/c', 'start', '', url], runInShell: false);
  }

  static Future<void> openFolder(String path) async {
    await Process.run('explorer.exe', [path]);
  }

  // ---- MySQL ----
  static Future<void> startMysql() async {
    if (!Directory(Cfg.mysqlData).existsSync()) {
      log('mysql', '初始化 MySQL 数据目录...');
      final init = await Process.run(
        '${Cfg.mysqlBin}\\mysqld.exe',
        ['--no-defaults', '--initialize-insecure', '--datadir=${Cfg.mysqlData}', '--character-set-server=utf8mb4'],
      );
      log('mysql', init.stdout.toString() + init.stderr.toString());
    }
    log('mysql', '启动 mysqld :${Cfg.mysqlPort}');
    final p = await Process.start(
      '${Cfg.mysqlBin}\\mysqld.exe',
      ['--no-defaults', '--datadir=${Cfg.mysqlData}', '--port=${Cfg.mysqlPort}', '--character-set-server=utf8mb4', '--console'],
    );
    mysqlProc = p;
    await attach(p, 'mysql');
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await portOpen(Cfg.mysqlPort)) break;
    }
    if (await portOpen(Cfg.mysqlPort)) {
      final r = await Process.run('${Cfg.mysqlBin}\\mysql.exe', [
        '--no-defaults', '-u', 'root', '-e',
        'CREATE DATABASE IF NOT EXISTS chord CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;',
      ]);
      final out = (r.stdout.toString() + r.stderr.toString()).trim();
      if (out.isNotEmpty) log('mysql', out);
      log('mysql', 'MySQL 就绪');
    } else {
      throw Exception('MySQL 端口未就绪，详见日志');
    }
  }

  static Future<void> stopMysql() async {
    log('mysql', '优雅关闭 (mysqladmin shutdown)');
    await Process.run('${Cfg.mysqlBin}\\mysqladmin.exe', ['--no-defaults', '-u', 'root', 'shutdown']);
    mysqlProc = null;
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!await portOpen(Cfg.mysqlPort)) return;
    }
    final pid = await findPid(Cfg.mysqlPort);
    if (pid != null) {
      log('mysql', '超时，强制结束 PID $pid');
      await killPid(pid);
    }
  }

  // ---- API ----
  static Map<String, String> _env(Map<String, String> extra) => {
        ...Platform.environment,
        ...extra,
      };

  static Future<void> ensureApiExe() async {
    if (File(Cfg.serverExe).existsSync()) return;
    log('api', '编译 chord-server.exe（首次较慢）...');
    final r = await Process.run('go', ['build', '-o', Cfg.serverExe, './cmd/server'],
        workingDirectory: Cfg.serverSrc,
        environment: _env({'GOPROXY': 'https://goproxy.cn,direct'}));
    final out = (r.stdout.toString() + r.stderr.toString()).trim();
    if (out.isNotEmpty) log('api', out);
    if (!File(Cfg.serverExe).existsSync()) throw Exception('go build 失败，详见日志');
  }

  static Future<void> startApi() async {
    await ensureApiExe();
    log('api', '启动 chord-server.exe :${Cfg.apiPort}');
    final p = await Process.start(Cfg.serverExe, [], workingDirectory: Cfg.serverSrc);
    apiProc = p;
    await attach(p, 'api');
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await apiHealthy()) break;
    }
    if (!await apiHealthy()) throw Exception('API 健康检查未通过，详见日志');
    log('api', 'API 就绪');
  }

  static Future<void> stopApi() async {
    final p = apiProc;
    if (p != null) {
      log('api', '停止 chord-server.exe');
      p.kill();
      apiProc = null;
      await Future.delayed(const Duration(milliseconds: 800));
    }
    if (await portOpen(Cfg.apiPort)) {
      final pid = await findPid(Cfg.apiPort);
      if (pid != null) {
        log('api', 'taskkill PID $pid');
        await killPid(pid);
      }
    }
  }

  // ---- Web ----
  static Future<void> ensureWebExe() async {
    if (File(Cfg.webExe).existsSync()) return;
    log('web', '编译 serveweb.exe ...');
    final r = await Process.run('go', ['build', '-o', Cfg.webExe, './cmd/serveweb'],
        workingDirectory: Cfg.serverSrc);
    final out = (r.stdout.toString() + r.stderr.toString()).trim();
    if (out.isNotEmpty) log('web', out);
    if (!File(Cfg.webExe).existsSync()) throw Exception('go build 失败，详见日志');
  }

  static Future<void> startWeb() async {
    if (!Directory(Cfg.webRoot).existsSync()) {
      log('web', '未找到前端构建产物，执行 flutter build web（首次约 1-3 分钟）...');
      final r = await Process.run(
        'flutter.bat',
        ['build', 'web', '--release'],
        workingDirectory: Cfg.clientDir,
        environment: _env({
          'PUB_HOSTED_URL': 'https://pub.flutter-io.cn',
          'FLUTTER_STORAGE_BASE_URL': 'https://storage.flutter-io.cn',
        }),
      );
      final out = (r.stdout.toString() + r.stderr.toString()).trim();
      log('web', out.length > 2000 ? '${out.substring(out.length - 2000)}' : out);
    }
    await ensureWebExe();
    log('web', '启动 serveweb.exe :${Cfg.webPort}');
    final p = await Process.start(Cfg.webExe, ['-dir', Cfg.webRoot, '-port', '${Cfg.webPort}']);
    webProc = p;
    await attach(p, 'web');
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await portOpen(Cfg.webPort)) break;
    }
    if (!await portOpen(Cfg.webPort)) throw Exception('Web 端口未就绪，详见日志');
    log('web', 'Web 就绪');
  }

  static Future<void> stopWeb() async {
    final p = webProc;
    if (p != null) {
      log('web', '停止 serveweb.exe');
      p.kill();
      webProc = null;
      await Future.delayed(const Duration(milliseconds: 800));
    }
    if (await portOpen(Cfg.webPort)) {
      final pid = await findPid(Cfg.webPort);
      if (pid != null) {
        log('web', 'taskkill PID $pid');
        await killPid(pid);
      }
    }
  }
}

// ============================================================
// UI
// ============================================================
class ChordConsoleApp extends StatelessWidget {
  const ChordConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chord 控制台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Microsoft YaHei UI',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5865F2),
          brightness: Brightness.dark,
          surface: const Color(0xFF2B2D31),
        ),
        scaffoldBackgroundColor: const Color(0xFF1E1F22),
      ),
      home: const ConsolePage(),
    );
  }
}

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});
  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  late final List<ServiceCtl> services;
  Timer? _statusTimer;
  Timer? _logTimer;
  String _logTab = 'api';
  String _logContent = '';
  final _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    services = [
      ServiceCtl(
        name: 'MySQL', port: Cfg.mysqlPort,
        onStart: Controllers.startMysql, onStop: Controllers.stopMysql,
      ),
      ServiceCtl(
        name: 'API', port: Cfg.apiPort,
        onStart: Controllers.startApi, onStop: Controllers.stopApi,
      ),
      ServiceCtl(
        name: 'Web', port: Cfg.webPort,
        onStart: Controllers.startWeb, onStop: Controllers.stopWeb,
      ),
    ];
    _refresh();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _logTimer = Timer.periodic(const Duration(milliseconds: 800), (_) => _refreshLog());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _logTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    for (final s in services) {
      if (s.busy) continue; // 动作进行中不覆盖状态
      bool up;
      switch (s.name) {
        case 'API':
          up = await Controllers.apiHealthy();
          break;
        default:
          up = await Controllers.portOpen(s.port);
      }
      final pid = await Controllers.findPid(s.port);
      if (!mounted) return;
      setState(() {
        s.pid = pid;
        s.state = up ? SvcState.running : SvcState.stopped;
      });
    }
  }

  Future<void> _refreshLog() async {
    final f = File(Cfg.logPath(_logTab));
    if (!f.existsSync()) return;
    try {
      final lines = f.readAsLinesSync();
      final tail = lines.length > 300 ? lines.sublist(lines.length - 300) : lines;
      final text = tail.join('\n');
      if (text != _logContent && mounted) {
        setState(() => _logContent = text);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients) {
            _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _toggle(ServiceCtl s, bool startIt) async {
    setState(() => s.state = startIt ? SvcState.starting : SvcState.stopping);
    try {
      if (startIt) {
        await s.onStart();
      } else {
        await s.onStop();
      }
      Controllers.log(s.name.toLowerCase(), startIt ? '== 启动完成 ==' : '== 已停止 ==');
    } catch (e) {
      Controllers.log(s.name.toLowerCase(), '!! 操作失败: $e');
    }
    if (!mounted) return;
    setState(() => s.state = SvcState.stopped);
    await _refresh();
  }

  Future<void> _restart(ServiceCtl s) async {
    if (s.state == SvcState.running) await _toggle(s, false);
    await Future.delayed(const Duration(milliseconds: 800));
    await _toggle(s, true);
  }

  Future<void> _all(bool startIt) async {
    for (final s in startIt ? services : services.reversed) {
      final up = startIt ? await Controllers.portOpen(s.port) : await Controllers.portOpen(s.port);
      if (startIt && !up) {
        await _toggle(s, true);
      } else if (!startIt && up) {
        await _toggle(s, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部
            Row(
              children: [
                const Icon(Icons.podcasts, color: Color(0xFF5865F2), size: 26),
                const SizedBox(width: 8),
                const Text('Chord 控制台',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => _all(true),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('全部启动'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _all(false),
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('全部停止'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 服务卡片
            for (final s in services)
              _ServiceCard(
                svc: s,
                onToggle: () => _toggle(s, s.state != SvcState.running),
                onRestart: () => _restart(s),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => Controllers.openUrl('http://127.0.0.1:${Cfg.webPort}'),
                  icon: const Icon(Icons.language, size: 18),
                  label: const Text('打开网页'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: File(Cfg.chatAppExe).existsSync()
                      ? () async {
                          await Process.start(Cfg.chatAppExe, []);
                          Controllers.log('api', '启动桌面聊天客户端');
                        }
                      : null,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('聊天客户端'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => Controllers.openFolder(Cfg.logsDir),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('日志目录'),
                ),
                const SizedBox(width: 14),
                const Text('演示账号 alice / bob / carol（密码 123456）',
                    style: TextStyle(fontSize: 12, color: Color(0xFF949BA4))),
              ],
            ),
            const Divider(height: 24),
            // 日志区
            Row(
              children: [
                for (final tab in ['mysql', 'api', 'web'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tab.toUpperCase()),
                      selected: _logTab == tab,
                      onSelected: (_) => setState(() { _logTab = tab; _logContent = ''; }),
                    ),
                  ),
                const Spacer(),
                Text('关闭窗口不影响已启动的服务', style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF16171A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x22FFFFFF)),
                ),
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  controller: _logScroll,
                  child: SelectableText(
                    _logContent.isEmpty ? '（暂无日志）' : _logContent,
                    style: const TextStyle(
                        fontFamily: 'Consolas', fontSize: 11.5, height: 1.35,
                        color: Color(0xFFB5BAC1)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ServiceCtl {
  final String name;
  final int port;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  SvcState state = SvcState.stopped;
  int? pid;

  ServiceCtl({
    required this.name,
    required this.port,
    required this.onStart,
    required this.onStop,
  });

  bool get busy =>
      state == SvcState.starting || state == SvcState.stopping || state == SvcState.building;
}

class _ServiceCard extends StatelessWidget {
  final ServiceCtl svc;
  final VoidCallback onToggle;
  final VoidCallback onRestart;

  const _ServiceCard({required this.svc, required this.onToggle, required this.onRestart});

  @override
  Widget build(BuildContext context) {
    final running = svc.state == SvcState.running;
    final busy = svc.busy;
    final color = switch (svc.state) {
      SvcState.running => const Color(0xFF3BA55D),
      SvcState.stopped => const Color(0xFF80848E),
      _ => const Color(0xFFFAA61A),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF2B2D31),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                  boxShadow: running ? [BoxShadow(color: color.withAlpha(120), blurRadius: 8)] : null),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 64,
              child: Text(svc.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            SizedBox(
              width: 76,
              child: Text(':${svc.port}', style: const TextStyle(color: Color(0xFF949BA4), fontSize: 13)),
            ),
            Expanded(
              child: Text(
                busy
                    ? (svc.state == SvcState.building ? '编译中…' : (svc.state == SvcState.starting ? '启动中…' : '停止中…'))
                    : (running ? '运行中  PID ${svc.pid ?? '-'}' : '已停止'),
                style: TextStyle(fontSize: 13, color: running ? const Color(0xFF3BA55D) : const Color(0xFF949BA4)),
              ),
            ),
            OutlinedButton(
              onPressed: busy ? null : onToggle,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor: running ? const Color(0xFFED4245) : const Color(0xFF3BA55D),
                side: BorderSide(color: running ? const Color(0x66ED4245) : const Color(0x663BA55D)),
              ),
              child: Text(running ? '停止' : '启动'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: busy ? null : onRestart,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
              child: const Text('重启'),
            ),
          ],
        ),
      ),
    );
  }
}
