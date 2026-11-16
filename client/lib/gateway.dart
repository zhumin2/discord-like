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
  DateTime _lastRecv = DateTime.now(); // 最近一次收到任何入站数据的时间（心跳看门狗用）
  String _base;
  String _token;

  Gateway({required String base, required String token})
      : _base = base,
        _token = token;

  Stream<WSEvent> get events => _events?.stream ?? const Stream.empty();
  bool get connected => _sock != null;

  /// 每次（重新）连接成功时触发，供上层做状态重同步（如在线状态/成员列表）。
  Stream<void> get onOpen => _openCtl.stream;
  final _openCtl = StreamController<void>.broadcast();

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

    // 握手成功 → 通知上层重同步（重连后会错过期间的 presence/member 事件）
    _sock!.ready.then((_) {
      if (_disposed) return;
      _openCtl.add(null);
    }).catchError((_) {
      // 失败由下面的 onError/onDone 处理
    });

    _sock!.stream.listen(
      (data) {
        _lastRecv = DateTime.now(); // 心跳 ACK 等任何入站数据都刷新
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
    _lastRecv = DateTime.now();
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      // 看门狗：半开连接（TCP 尚在但数据不通）不会触发 onDone/onError，
      // 表现为"消息靠 REST 照常收发、但服务端认为你离线、自己也收不到实时事件"。
      // 超过 75s 没有任何入站数据（服务端每 25s 会回 HEARTBEAT_ACK）⇒ 判定假死，强制重连。
      if (DateTime.now().difference(_lastRecv) > const Duration(seconds: 75)) {
        _cleanupSock();
        _scheduleReconnect();
        return;
      }
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
    _openCtl.close();
  }
}
