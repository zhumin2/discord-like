import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// 服务端事件信封。
class WSEvent {
  final String t;
  final dynamic d;
  const WSEvent(this.t, this.d);
}

/// WebSocket 网关：连接、心跳、断线自动重连（指数退避）。
class Gateway {
  WebSocketChannel? _sock;
  StreamController<WSEvent>? _events;
  Timer? _heartbeat;
  Timer? _reconnect;
  int _backoff = 1; // 秒
  bool _disposed = false;
  String _base;
  String _token;

  Gateway({required String base, required String token})
      : _base = base,
        _token = token;

  Stream<WSEvent> get events => _events?.stream ?? const Stream.empty();
  bool get connected => _sock != null;

  /// 建立连接（重复调用安全）。
  void connect() => _connect();

  void _connect() {
    if (_disposed) return;
    final wsUrl = _base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    try {
      _sock = WebSocketChannel.connect(Uri.parse('$wsUrl/ws?token=$_token'));
    } catch (e) {
      _scheduleReconnect();
      return;
    }
    _events ??= StreamController<WSEvent>.broadcast();
    _backoff = 1;

    _sock!.stream.listen(
      (data) {
        try {
          final obj = jsonDecode(data as String) as Map<String, dynamic>;
          final t = obj['t'] as String?;
          if (t == null) return;
          _events!.add(WSEvent(t, obj['d']));
        } catch (_) {}
      },
      onDone: () {
        _cleanupSock();
        _scheduleReconnect();
      },
      onError: (_) {
        _cleanupSock();
        _scheduleReconnect();
      },
    );

    // 25s 心跳，保活 + 更新在线状态
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      _sendRaw('{"t":"heartbeat"}');
    });
  }

  void _sendRaw(String s) {
    try {
      _sock?.sink.add(s);
    } catch (_) {}
  }

  void sendTyping(String channelId) {
    _sendRaw(jsonEncode({
      't': 'typing',
      'd': {'channelId': channelId},
    }));
  }

  void _cleanupSock() {
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      _sock?.sink.close();
    } catch (_) {}
    _sock = null;
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnect != null) return;
    _reconnect = Timer(Duration(seconds: _backoff), () {
      _reconnect = null;
      if (!_disposed) {
        _backoff = (_backoff * 2).clamp(1, 30);
        _connect();
      }
    });
  }

  /// 服务器地址或 token 变化时重连。
  void reconfigure({String? base, String? token}) {
    final changed = (base != null && base != _base) || (token != null && token != _token);
    if (base != null) _base = base;
    if (token != null) _token = token;
    if (!changed || _disposed) return;
    _reconnect?.cancel();
    _reconnect = null;
    _cleanupSock();
    _connect();
  }

  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _cleanupSock();
    _events?.close();
    _events = null;
  }
}
