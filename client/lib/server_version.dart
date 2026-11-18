import 'dart:convert';

import 'package:flutter/material.dart';import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'state/app_state.dart';
import 'theme.dart';
import 'version.dart';

/// 服务器版本：GET /api/health 的 version 字段。
/// 后端由 CI 以 `-ldflags -X chord/server/internal/handlers.Version=<tag>` 注入，
/// 本地 `go run` 时为 dev。与客户端 [appVersion] 一起用于测试时核对前后端版本。
final serverVersionProvider = FutureProvider.autoDispose<String>((ref) async {
  final base = ref.watch(serverBaseProvider);
  try {
    final resp = await http
        .get(Uri.parse('$base/api/health'))
        .timeout(const Duration(seconds: 5));
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (j['version'] as String?) ?? '未知';
  } catch (_) {
    return '无法获取';
  }
});

/// 一行版本文字，如「客户端 v1.3.1 ｜ 服务器 v1.3.1」。
class VersionText extends ConsumerWidget {
  const VersionText({super.key, this.fontSize = 11.5});

  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverVersionProvider);
    final serverText = server.when(
      data: (v) => v,
      loading: () => '查询中…',
      error: (_, __) => '无法获取',
    );
    final style = TextStyle(fontSize: fontSize, color: ChordColors.textMuted);
    return Text('客户端 $appVersion ｜ 服务器 $serverText', style: style);
  }
}
