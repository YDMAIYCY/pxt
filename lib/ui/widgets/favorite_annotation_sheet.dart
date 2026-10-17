import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../database/favorite_repository.dart';
import '../theme/app_theme.dart';

const _highlightColors = <String, Color>{
  '黄色': Color(0xFFFFE89B),
  '绿色': Color(0xFFBBE8BE),
  '蓝色': Color(0xFFB9DDFF),
  '粉色': Color(0xFFF6C9DF),
};

class FavoriteAnnotationSheet extends StatefulWidget {
  const FavoriteAnnotationSheet({
    required this.item,
    required this.onSave,
    required this.onClearLegacyNote,
    required this.onClearLegacyHighlight,
    required this.onRemoveFavorite,
    super.key,
  });

  final FavoriteItemRecord item;
  final Future<void> Function(List<FavoriteAnnotation>) onSave;
  final Future<void> Function() onClearLegacyNote;
  final Future<void> Function() onClearLegacyHighlight;
  final VoidCallback onRemoveFavorite;

  @override
  State<FavoriteAnnotationSheet> createState() =>
      _FavoriteAnnotationSheetState();
}

class _FavoriteAnnotationSheetState extends State<FavoriteAnnotationSheet> {
  late List<FavoriteAnnotation> _annotations = [...widget.item.annotations];
  late String? _legacyNote = widget.item.note;
  late String? _legacyHighlight = widget.item.highlightText;
  TextSelection _selection = const TextSelection.collapsed(offset: -1);
  bool _saving = false;

  String get _body => widget.item.body;
  bool get _hasSelection =>
      _selection.isValid &&
      !_selection.isCollapsed &&
      _selection.end <= _body.length;

  Future<bool> _save(List<FavoriteAnnotation> next) async {
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      await widget.onSave(next);
      if (mounted) setState(() => _annotations = next);
      return true;
    } catch (error) {
      if (mounted) _message('批注保存失败：$error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  FavoriteAnnotation? _at(TextSelection range) => _annotations
      .where(
        (a) => a.matches(_body) && a.start == range.start && a.end == range.end,
      )
      .lastOrNull;

  Future<void> _mark(TextSelection range, {String? color, String? note}) async {
    final previous = _at(range);
    final annotation = FavoriteAnnotation(
      id: previous?.id ?? const Uuid().v4(),
      start: range.start,
      end: range.end,
      quote: _body.substring(range.start, range.end),
      color: color ?? previous?.color,
      note: note ?? previous?.note,
    );
    await _save([
      ..._annotations.where((a) => a.id != annotation.id),
      annotation,
    ]);
  }

  Future<void> _removeHighlight(TextSelection range) async {
    await _save([
      for (final a in _annotations)
        if (!a.matches(_body) || a.end <= range.start || a.start >= range.end)
          a
        else ...[
          if (a.note != null)
            FavoriteAnnotation(
              id: a.id,
              start: a.start,
              end: a.end,
              quote: a.quote,
              note: a.note,
            ),
          if (a.color != null && a.start < range.start)
            _highlightFragment(a.start, range.start, a.color!),
          if (a.color != null && a.end > range.end)
            _highlightFragment(range.end, a.end, a.color!),
        ],
    ]);
  }

  FavoriteAnnotation _highlightFragment(int start, int end, String color) =>
      FavoriteAnnotation(
        id: const Uuid().v4(),
        start: start,
        end: end,
        quote: _body.substring(start, end),
        color: color,
      );

  Future<void> _editNote(TextSelection range) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _NoteEditor(
        quote: _body.substring(range.start, range.end),
        initialNote: _at(range)?.note ?? '',
      ),
    );
    if (text != null && mounted) await _mark(range, note: text);
  }

  Future<void> _deleteNote(FavoriteAnnotation annotation) async {
    await _save([
      for (final a in _annotations)
        if (a.id != annotation.id)
          a
        else if (a.color != null)
          FavoriteAnnotation(
            id: a.id,
            start: a.start,
            end: a.end,
            quote: a.quote,
            color: a.color,
          ),
    ]);
  }

  TextSpan _contentSpan(TextStyle style) {
    final valid = _annotations.where((a) => a.matches(_body)).toList();
    final boundaries = {
      0,
      _body.length,
      ...valid.expand((a) => [a.start, a.end]),
    }.toList()..sort();
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i + 1 < boundaries.length; i++)
          _segment(valid, boundaries[i], boundaries[i + 1]),
      ],
    );
  }

  TextSpan _segment(List<FavoriteAnnotation> valid, int start, int end) {
    final covering = valid.where((a) => a.start <= start && a.end >= end);
    final color = covering.where((a) => a.color != null).lastOrNull?.color;
    final hasNote = covering.any((a) => a.note != null);
    return TextSpan(
      text: _body.substring(start, end),
      style: TextStyle(
        backgroundColor: _highlightColors[color],
        decoration: hasNote ? TextDecoration.underline : null,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: AppColors.primary,
      ),
    );
  }

  Widget _annotatedBody() => LayoutBuilder(
    builder: (context, constraints) {
      final style = AppTextStyles.body(context);
      final span = _contentSpan(style);
      final direction = Directionality.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final width = math.max(1.0, constraints.maxWidth - 40);
      final strut = StrutStyle.fromTextStyle(style);
      final painter = TextPainter(
        text: span,
        textDirection: direction,
        textScaler: scaler,
        strutStyle: strut,
        textWidthBasis: TextWidthBasis.parent,
        // SelectableText reserves its 2px caret and a 1px gap, even read-only.
      )..layout(maxWidth: math.max(0.0, width - 3));
      final notes =
          _annotations.where((a) => a.note != null && a.matches(_body)).toList()
            ..sort((a, b) => a.end.compareTo(b.end));
      final tops = <double>[];
      for (final note in notes) {
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: note.start, extentOffset: note.end),
        );
        final top = boxes.isEmpty ? 0.0 : boxes.last.top;
        tops.add(math.max(top, tops.isEmpty ? 0 : tops.last + 32));
      }
      painter.dispose();
      return SizedBox(
        key: const ValueKey('favorite-annotation-layout'),
        width: constraints.maxWidth,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 40, bottom: 8),
              child: SelectableText.rich(
                span,
                key: const ValueKey('favorite-annotated-body'),
                style: style,
                textDirection: direction,
                textScaler: scaler,
                strutStyle: strut,
                textWidthBasis: TextWidthBasis.parent,
                onSelectionChanged: (selection, _) {
                  setState(() => _selection = selection);
                },
                contextMenuBuilder: (context, editable) {
                  final range = editable.textEditingValue.selection;
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editable.contextMenuAnchors,
                    buttonItems: [
                      ...editable.contextMenuButtonItems,
                      if (range.isValid && !range.isCollapsed) ...[
                        for (final color in _highlightColors.keys)
                          ContextMenuButtonItem(
                            label: '$color高亮',
                            onPressed: () {
                              editable.hideToolbar();
                              _mark(range, color: color);
                            },
                          ),
                        ContextMenuButtonItem(
                          label: '添加笔记',
                          onPressed: () {
                            editable.hideToolbar();
                            _editNote(range);
                          },
                        ),
                        if (_annotations.any(
                          (a) =>
                              a.color != null &&
                              a.matches(_body) &&
                              a.start < range.end &&
                              a.end > range.start,
                        ))
                          ContextMenuButtonItem(
                            label: '取消高亮',
                            onPressed: () {
                              editable.hideToolbar();
                              _removeHighlight(range);
                            },
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
            if (tops.isNotEmpty) SizedBox(height: tops.last + 32, width: 1),
            for (var i = 0; i < notes.length; i++)
              Positioned(
                right: 0,
                top: tops[i],
                width: 36,
                height: 30,
                child: _NoteTag(
                  key: ValueKey(notes[i].id),
                  annotation: notes[i],
                  number: i + 1,
                  onEdit: () => _editNote(
                    TextSelection(
                      baseOffset: notes[i].start,
                      extentOffset: notes[i].end,
                    ),
                  ),
                  onDelete: () => _deleteNote(notes[i]),
                ),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _clearLegacy(bool note) async {
    try {
      if (note) {
        await widget.onClearLegacyNote();
      } else {
        await widget.onClearLegacyHighlight();
      }
      if (mounted) {
        setState(() {
          if (note) {
            _legacyNote = null;
          } else {
            _legacyHighlight = null;
          }
        });
      }
    } catch (error) {
      if (mounted) _message('保存失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final detached = _annotations.where((a) => !a.matches(_body)).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.title,
                style: AppTextStyles.h2(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                widget.item.subtitle,
                style: AppTextStyles.bodySmall(context),
              ),
              const SizedBox(height: 12),
              const Text('长按正文选中文字后，可高亮或添加笔记'),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '完整内容',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _annotatedBody(),
                      if (_legacyNote?.isNotEmpty == true ||
                          _legacyHighlight?.isNotEmpty == true)
                        ExpansionTile(
                          title: const Text('原有笔记与重点'),
                          children: [
                            if (_legacyNote?.isNotEmpty == true)
                              ListTile(
                                title: const Text('原有笔记'),
                                subtitle: Text(_legacyNote!),
                                trailing: TextButton(
                                  onPressed: () => _clearLegacy(true),
                                  child: const Text('删除笔记'),
                                ),
                              ),
                            if (_legacyHighlight?.isNotEmpty == true)
                              ListTile(
                                title: const Text('原有高亮文本'),
                                subtitle: Text(_legacyHighlight!),
                                trailing: TextButton(
                                  onPressed: () => _clearLegacy(false),
                                  child: const Text('取消高亮'),
                                ),
                              ),
                          ],
                        ),
                      if (detached.isNotEmpty)
                        ExpansionTile(
                          title: const Text('原文已变更的批注'),
                          children: [
                            for (final a in detached)
                              ListTile(
                                title: Text(a.quote),
                                subtitle: a.note == null ? null : Text(a.note!),
                                trailing: IconButton(
                                  tooltip: '删除批注',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: _saving
                                      ? null
                                      : () => _save(
                                          _annotations
                                              .where((n) => n.id != a.id)
                                              .toList(),
                                        ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final color in _highlightColors.entries)
                    IconButton(
                      tooltip: '${color.key}高亮',
                      onPressed: _hasSelection && !_saving
                          ? () => _mark(_selection, color: color.key)
                          : null,
                      icon: Icon(
                        Icons.format_color_fill,
                        color: _hasSelection ? color.value : null,
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _hasSelection && !_saving
                        ? () => _editNote(_selection)
                        : null,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('笔记'),
                  ),
                  if (_hasSelection &&
                      _annotations.any(
                        (a) =>
                            a.color != null &&
                            a.matches(_body) &&
                            a.start < _selection.end &&
                            a.end > _selection.start,
                      ))
                    IconButton(
                      tooltip: '取消所选高亮',
                      onPressed: _saving
                          ? null
                          : () => _removeHighlight(_selection),
                      icon: const Icon(Icons.format_color_reset),
                    ),
                  TextButton(
                    onPressed: _saving ? null : widget.onRemoveFavorite,
                    child: const Text('取消收藏'),
                  ),
                  if (_saving)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.quote, required this.initialNote});
  final String quote, initialNote;
  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _controller = TextEditingController(text: widget.initialNote);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加笔记'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('“${widget.quote}”', maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '写下对这段内容的理解',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('保存'),
      ),
    ],
  );
}

class _NoteTag extends StatefulWidget {
  const _NoteTag({
    required this.annotation,
    required this.number,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });
  final FavoriteAnnotation annotation;
  final int number;
  final VoidCallback onEdit, onDelete;
  @override
  State<_NoteTag> createState() => _NoteTagState();
}

class _NoteTagState extends State<_NoteTag> {
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  bool _above = false;

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _overlay,
    overlayChildBuilder: (context) => Positioned.fill(
      child: Stack(
        children: [
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: _above ? Alignment.topRight : Alignment.bottomRight,
            followerAnchor: _above ? Alignment.bottomRight : Alignment.topRight,
            offset: Offset(0, _above ? -6 : 6),
            child: SizedBox(
              width: math.min(300, MediaQuery.sizeOf(context).width - 48),
              child: Material(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.borderLight),
                ),
                color: Theme.of(context).colorScheme.surface,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '笔记 ${widget.number}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '“${widget.annotation.quote}”',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(widget.annotation.note!),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                _overlay.hide();
                                widget.onEdit();
                              },
                              child: const Text('编辑'),
                            ),
                            TextButton(
                              onPressed: () {
                                _overlay.hide();
                                widget.onDelete();
                              },
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    child: CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message: '笔记 ${widget.number}，点击展开或收起',
        child: Material(
          color: AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: ValueKey('note-tag-${widget.annotation.id}'),
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              final box = context.findRenderObject() as RenderBox;
              _above =
                  box.localToGlobal(Offset.zero).dy >
                  MediaQuery.sizeOf(context).height - 290;
              _overlay.toggle();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.sticky_note_2_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                Text(
                  '${widget.number}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
