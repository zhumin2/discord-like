import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clipboard_image.dart';
import '../theme.dart';

/// 消息输入框：回车发送（Shift+回车换行），输入时触发 typing；
/// v1.1 支持附件：onAttach 由外层完成选文件+上传并返回要插入的文本（null=取消）。
class Composer extends StatefulWidget {
  final String channelName;
  final bool isDM;
  final Future<String?> Function(String text) onSend;
  final VoidCallback onTyping;
  final Future<String?> Function()? onAttach;
  // 引用回复（null = 非回复状态）
  final String? replyAuthor;
  final String? replySnippet;
  final Color? replyColor;
  final VoidCallback? onCancelReply;
  /// 频道成员名列表（@ 自动补全用）；空 = 不启用补全
  final List<String> memberNames;
  /// 剪贴板图片粘贴回调（返回要插入输入框的 Markdown 文本）；null = 不启用
  final Future<String?> Function(Uint8List bytes, String mime)? onPasteImage;

  const Composer({
    super.key,
    required this.channelName,
    required this.isDM,
    required this.onSend,
    required this.onTyping,
    this.onAttach,
    this.replyAuthor,
    this.replySnippet,
    this.replyColor,
    this.onCancelReply,
    this.memberNames = const [],
    this.onPasteImage,
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _ctl = TextEditingController();
  final _keyFocus = FocusNode(); // 仅用于捕获按键，不参与输入焦点
  bool _sending = false; // 消息发送中（发送键转圈，防连发）
  bool _uploading = false; // 附件上传中（附件键转圈）
  Unregister? _unregisterPaste; // 剪贴板图片监听（Web/Windows）
  int _lastPasteLen = -1; // 最近一次粘贴的图片字节数（原生推送 + Dart 主动拉取去重）
  DateTime _lastPasteAt = DateTime.fromMillisecondsSinceEpoch(0);
  List<String> _mentionCandidates = []; // @ 自动补全候选
  String _mentionToken = ''; // 正在输入的 @partial

  @override
  void initState() {
    super.initState();
    // 剪贴板图片粘贴（v 反馈 1）：Web 监听 document.onPaste，Windows 由原生回调
    if (widget.onPasteImage != null) {
      _unregisterPaste = registerPasteImage((bytes, mime) => _insertPastedImage(bytes, mime));
    }
  }

  @override
  void dispose() {
    _unregisterPaste?.call();
    _ctl.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  /// Ctrl+V 时主动读系统剪贴板（Windows 专用；Web 返回 null 由 JS 监听负责）。
  Future<void> _pasteFromSystemClipboard() async {
    final bytes = await readClipboardImage();
    if (bytes == null) return;
    await _insertPastedImage(bytes, 'image/png');
  }

  /// 粘贴的图片走附件管线（压缩→上传），把返回的 Markdown 追加到输入框。
  Future<void> _insertPastedImage(Uint8List bytes, String mime) async {
    final fn = widget.onPasteImage;
    if (fn == null || _uploading) return;
    // 去重：原生 WM_KEYDOWN 推送与 Dart 主动拉取可能同时/先后触发同一次 Ctrl+V
    final now = DateTime.now();
    if (bytes.length == _lastPasteLen &&
        now.difference(_lastPasteAt).inMilliseconds < 2000) {
      return;
    }
    _lastPasteLen = bytes.length;
    _lastPasteAt = now;
    setState(() => _uploading = true);
    String? insert;
    try {
      insert = await fn(bytes, mime);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('图片上传失败：$e', style: const TextStyle(fontSize: 13))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
    if (insert != null && insert.isNotEmpty && mounted) {
      _ctl.text += insert;
      _ctl.selection = TextSelection.fromPosition(TextPosition(offset: _ctl.text.length));
      setState(() {});
    }
  }

  /// 检测光标前是否有未完成的 @提及，如有则填充候选。
  void _updateMentionCandidates() {
    final sel = _ctl.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _mentionCandidates = [];
      return;
    }
    final pos = sel.baseOffset;
    if (pos < 0 || pos > _ctl.text.length) {
      _mentionCandidates = [];
      return;
    }
    final before = _ctl.text.substring(0, pos);
    final m = RegExp(r'[@＠]([^\s@＠]{0,20})$').firstMatch(before);
    if (m == null) {
      if (_mentionCandidates.isNotEmpty || _mentionToken.isNotEmpty) {
        _mentionCandidates = [];
        _mentionToken = '';
      }
      return;
    }
    _mentionToken = m.group(0)!; // 形如 "@he"
    final typed = m.group(1)!.toLowerCase();
    _mentionCandidates = widget.memberNames
        .where((n) =>
            n.toLowerCase().startsWith(typed) ||
            n.toLowerCase().contains(typed))
        .take(5)
        .toList();
  }

  /// 用选中的成员名替换光标前的 @partial。
  void _applyMention(String name) {
    final sel = _ctl.selection;
    final pos = sel.baseOffset;
    if (pos < 0 || pos > _ctl.text.length) return;
    final before = _ctl.text.substring(0, pos - _mentionToken.length);
    final after = _ctl.text.substring(pos);
    // 统一写成半角 @（渲染/通知判定都以半角为准）
    _ctl.text = '$before@$name $after';
    _ctl.selection = TextSelection.fromPosition(
        TextPosition(offset: before.length + name.length + 2));
    setState(() {
      _mentionCandidates = [];
      _mentionToken = '';
    });
    widget.onTyping();
  }

  Future<void> _send() async {
    final text = _ctl.text.trim();
    if (text.isEmpty || _sending || _uploading) return;
    setState(() => _sending = true);
    _ctl.clear();
    String? err;
    try {
      err = await widget.onSend(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    // 失败（如 429 发言太快）：把原文放回输入框，提示后可重试
    if (err != null && mounted) {
      _ctl.text = text;
      _ctl.selection = TextSelection.fromPosition(TextPosition(offset: _ctl.text.length));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err, style: const TextStyle(fontSize: 13))));
    }
  }

  Future<void> _attach() async {
    final onAttach = widget.onAttach;
    if (onAttach == null || _sending || _uploading) return;
    setState(() => _uploading = true);
    String? insert;
    String? err;
    try {
      insert = await onAttach();
    } catch (e) {
      err = e.toString();
    } finally {
      if (mounted) setState(() => _uploading = false);
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
    // Ctrl+V：主动向系统要剪贴板图片（Windows）。
    // 顶层窗口的 WM_KEYDOWN 可能收不到（焦点在 Flutter 子窗口），这是兜底路径；
    // 原生推送与这里的结果会按「字节数 + 2 秒窗口」去重。不 handled，文本粘贴照常。
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        widget.onPasteImage != null) {
      _pasteFromSystemClipboard();
    }
    // @ 候选列表打开时：Tab 选中第一个候选（之前 Tab 被焦点遍历吃掉，用户反馈"没反应"）
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        _mentionCandidates.isNotEmpty) {
      _applyMention(_mentionCandidates.first);
      return KeyEventResult.handled;
    }
    // 桌面/Web：无 Shift 修饰的 Enter 发送，Shift+Enter 换行
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) &&
        !HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.shiftRight)) {
      if (_mentionCandidates.isNotEmpty) {
        _applyMention(_mentionCandidates.first);
        return KeyEventResult.handled;
      }
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 注意：这里必须保留固定占位（空时 SizedBox.shrink），不能条件插入。
          // Column 的子节点是按索引更新的：在顶部插入候选列表会让下面的输入框
          // 被整体重建，Web 端 DOM input 因此重新挂载、立刻失焦
          //（用户反馈：输入 @ 之后"跳出输入框"，后续字符和 Tab 都无效）。
          _mentionCandidates.isEmpty ? const SizedBox.shrink() : _buildMentionList(),
          widget.replyAuthor == null ? const SizedBox.shrink() : _buildReplyBar(),
          Container(
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
                  icon: _uploading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: ChordColors.blurple))
                      : const Icon(Icons.attach_file,
                          color: ChordColors.textMuted, size: 22),
                  onPressed: (_sending || _uploading) ? null : _attach,
                ),
              ),
            // 桌面端显式「粘贴图片」入口：不依赖 Ctrl+V 拦截（顶层窗口可能收不到
            // 键盘消息，见 AGENTS 坑 29），点一下就直接读系统剪贴板
            if (widget.onPasteImage != null &&
                !kIsWeb &&
                defaultTargetPlatform != TargetPlatform.android)
              IconButton(
                tooltip: '粘贴图片',
                icon: _uploading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.content_paste,
                        color: ChordColors.textMuted, size: 20),
                onPressed: (_sending || _uploading) ? null : _pasteFromSystemClipboard,
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
                    _updateMentionCandidates();
                    widget.onTyping();
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2),
              child: IconButton(
                tooltip: '发送',
                // 发送中转圈并禁用，防止快速连发两条（v 反馈 2）
                icon: _sending
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.send,
                        size: 20,
                        color: canSend ? ChordColors.blurple : ChordColors.textMuted),
                onPressed: (canSend && !_sending && !_uploading) ? _send : null,
              ),
            ),
          ],
        ),
          ),
        ],
      ),
    );
  }

  /// 引用回复提示条：显示"回复 某人 + 摘要"，可关闭。
  Widget _buildReplyBar() {
    final snippet = (widget.replySnippet ?? '').replaceAll('\n', ' ').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: ChordColors.bgLight,
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(color: widget.replyColor ?? ChordColors.blurple, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 14, color: widget.replyColor ?? ChordColors.blurple),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(
                    text: '回复 ',
                    style: TextStyle(fontSize: 12.5, color: ChordColors.textMuted)),
                TextSpan(
                  text: widget.replyAuthor,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: widget.replyColor ?? ChordColors.blurple),
                ),
                TextSpan(
                    text: snippet.isEmpty ? '' : '：$snippet',
                    style: const TextStyle(fontSize: 12.5, color: ChordColors.textMuted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: widget.onCancelReply,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 15, color: ChordColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// @ 自动补全候选列表（显示在输入框上方，最多 5 条）。
  Widget _buildMentionList() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: ChordColors.bgDarker,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x22FFFFFF)),
      ),
      child: Column(
        children: [
          for (final name in _mentionCandidates)
            InkWell(
              onTap: () => _applyMention(name),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.alternate_email, size: 14, color: ChordColors.textMuted),
                    const SizedBox(width: 8),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13.5, color: ChordColors.textNormal)),
                  ],
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Tab 或 Enter 选中',
                  style: TextStyle(fontSize: 10.5, color: ChordColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }}
