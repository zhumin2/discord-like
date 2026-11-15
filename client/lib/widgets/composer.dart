import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// 消息输入框：回车发送（Shift+回车换行），输入时触发 typing；
/// v1.1 支持附件：onAttach 由外层完成选文件+上传并返回要插入的文本（null=取消）。
class Composer extends StatefulWidget {
  final String channelName;
  final bool isDM;
  final Future<void> Function(String text) onSend;
  final VoidCallback onTyping;
  final Future<String?> Function()? onAttach;

  const Composer({
    super.key,
    required this.channelName,
    required this.isDM,
    required this.onSend,
    required this.onTyping,
    this.onAttach,
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _ctl = TextEditingController();
  final _keyFocus = FocusNode(); // 仅用于捕获按键，不参与输入焦点
  bool _sending = false;

  @override
  void dispose() {
    _ctl.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctl.clear();
    try {
      await widget.onSend(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final onAttach = widget.onAttach;
    if (onAttach == null || _sending) return;
    setState(() => _sending = true);
    String? insert;
    String? err;
    try {
      insert = await onAttach();
    } catch (e) {
      err = e.toString();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (insert != null && insert.isNotEmpty) {
      _ctl.text += insert;
      _ctl.selection = TextSelection.fromPosition(
          TextPosition(offset: _ctl.text.length));
    }
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err, style: const TextStyle(fontSize: 13))));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // 桌面/Web：无 Shift 修饰的 Enter 发送，Shift+Enter 换行
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) &&
        !HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftRight)) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _ctl.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 8 + MediaQuery.of(context).padding.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: ChordColors.bgLight,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.onAttach != null)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: IconButton(
                  tooltip: '发送文件',
                  icon: _sending
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: ChordColors.blurple))
                      : const Icon(Icons.attach_file,
                          color: ChordColors.textMuted, size: 22),
                  onPressed: _sending ? null : _attach,
                ),
              ),
            PopupMenuButton<String>(
              tooltip: '表情',
              icon: const Icon(Icons.emoji_emotions_outlined,
                  color: ChordColors.textMuted, size: 22),
              color: ChordColors.bgModal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onSelected: (e) {
                _ctl.text += e;
                _ctl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _ctl.text.length));
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: '😄', height: 40, child: Text('😄', style: TextStyle(fontSize: 22))),
                PopupMenuItem(value: '😂', height: 40, child: Text('😂', style: TextStyle(fontSize: 22))),
                PopupMenuItem(value: '🥰', height: 40, child: Text('🥰', style: TextStyle(fontSize: 22))),
                PopupMenuItem(value: '👍', height: 40, child: Text('👍', style: TextStyle(fontSize: 22))),
                PopupMenuItem(value: '🎉', height: 40, child: Text('🎉', style: TextStyle(fontSize: 22))),
                PopupMenuItem(value: '🔥', height: 40, child: Text('🔥', style: TextStyle(fontSize: 22))),
                PopupMenuItem(value: '🚀', height: 40, child: Text('🚀', style: TextStyle(fontSize: 22))),
                PopupMenuItem(value: '🤝', height: 40, child: Text('🤝', style: TextStyle(fontSize: 22))),
              ],
            ),
            Expanded(
              child: Focus(
                focusNode: _keyFocus,
                onKeyEvent: _onKey,
                skipTraversal: true,
                canRequestFocus: false,
                descendantsAreFocusable: true,
                child: TextField(
                  controller: _ctl,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 15, color: ChordColors.textNormal),
                  decoration: InputDecoration(
                    hintText: widget.isDM ? '发送私信消息' : '发送消息到 #${widget.channelName}',
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (_) {
                    setState(() {}); // 刷新发送按钮可用态
                    widget.onTyping();
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2),
              child: IconButton(
                tooltip: '发送',
                icon: Icon(Icons.send,
                    size: 20,
                    color: canSend ? ChordColors.blurple : ChordColors.textMuted),
                onPressed: canSend ? _send : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
