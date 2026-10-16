import 'package:flutter/material.dart';
import '../../../community/cloud_backend.dart';
import '../../../community/community_repository.dart';
import 'community_widgets.dart';
import 'question_detail_page.dart';
import 'publish_question_page.dart';
import 'social_pages.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({
    this.bookmarks = false,
    this.search = false,
    this.repository,
    super.key,
  });
  final bool bookmarks, search;
  final CommunityRepository? repository;
  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  late final CommunityRepository _repo =
      widget.repository ?? CommunityRepository();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  late Future<List<Json>> _future;
  List<Json> _items = [];
  int _mode = 0, _generation = 0;
  bool _more = true, _loadingMore = false;
  String? _pageError;
  static const _modes = ['recommended', 'latest', 'unanswered'];
  @override
  void initState() {
    super.initState();
    _reload();
    _scroll.addListener(_onScroll);
    CloudBackend.instance.addListener(_cloudChanged);
  }

  @override
  void dispose() {
    CloudBackend.instance.removeListener(_cloudChanged);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _cloudChanged() {
    if (mounted) setState(_reload);
  }

  void _reload() {
    final generation = ++_generation;
    _more = true;
    _pageError = null;
    _loadingMore = false;
    _future = _repo
        .feed(
          mode: _modes[_mode],
          keyword: _search.text,
          bookmarks: widget.bookmarks,
        )
        .then((items) {
          if (generation == _generation) {
            _items = items;
            _more = items.length == 20;
          }
          return items;
        });
  }

  Future<void> _refresh() async {
    setState(_reload);
    try {
      await _future;
    } catch (_) {}
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 350) _next();
  }

  Future<void> _next() async {
    if (_loadingMore || !_more || _items.isEmpty || _pageError != null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final items = await _repo.feed(
        mode: _modes[_mode],
        keyword: _search.text,
        offset: _items.length,
        bookmarks: widget.bookmarks,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _items.addAll(
            items.where((i) => !_items.any((o) => o['id'] == i['id'])),
          );
          _more = items.length == 20;
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _pageError = cloudError(e));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuestionDetailPage(questionId: id)),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.bookmarks && !widget.search)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '学习社区',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10213A),
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: '搜索问题',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CommunityPage(search: true),
                        ),
                      ),
                      icon: const Icon(Icons.search, size: 27),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PublishQuestionPage(),
                          ),
                        );
                        if (mounted) _refresh();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: communityBlue,
                        minimumSize: const Size(0, 44),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('发问题'),
                    ),
                  ],
                ),
              if (!widget.bookmarks && !widget.search)
                const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 18),
                  child: Text(
                    '分享问题 · 交流经验 · 一起进步',
                    style: TextStyle(color: Color(0xFF8590A4), fontSize: 14),
                  ),
                ),
              if (widget.search)
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索问题标题或正文',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      onPressed: () => setState(_reload),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                  onSubmitted: (_) => setState(_reload),
                ),
              if (!widget.bookmarks && !widget.search)
                Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          label: Text(['推荐', '最新', '待解答'][i]),
                          selected: _mode == i,
                          showCheckmark: false,
                          selectedColor: communityBlue,
                          labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: _mode == i
                                ? Colors.white
                                : const Color(0xFF7F8BA1),
                            fontWeight: FontWeight.w600,
                          ),
                          onSelected: (_) => setState(() {
                            _mode = i;
                            _reload();
                          }),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: CloudFutureView(
            future: _future,
            onRetry: () => setState(_reload),
            builder: (_) => RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  14,
                  8,
                  14,
                  widget.bookmarks || widget.search ? 24 : 112,
                ),
                itemCount: _items.isEmpty ? 1 : _items.length + 1,
                itemBuilder: (context, i) {
                  if (_items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Column(
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 48,
                            color: Colors.blueGrey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '还没有相关问题',
                            style: TextStyle(color: Colors.blueGrey),
                          ),
                        ],
                      ),
                    );
                  }
                  if (i == _items.length) {
                    return _pageError != null
                        ? TextButton(
                            onPressed: () {
                              setState(() => _pageError = null);
                              _next();
                            },
                            child: Text('$_pageError，点击重试'),
                          )
                        : _loadingMore
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : _more
                        ? TextButton(
                            onPressed: _next,
                            child: const Text('加载更多'),
                          )
                        : const Center(
                            child: Text(
                              '已显示全部问题',
                              style: TextStyle(
                                color: Colors.blueGrey,
                                fontSize: 12,
                              ),
                            ),
                          );
                  }
                  final q = _items[i];
                  return CommunityQuestionCard(
                    question: q,
                    onTap: () => _open(q['id'] as String),
                    onProfile: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CommunityUserPage(userId: q['author_id'] as String),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
    return widget.bookmarks || widget.search
        ? Scaffold(
            backgroundColor: communityBackground,
            appBar: AppBar(title: Text(widget.bookmarks ? '社区收藏' : '搜索问题')),
            body: body,
          )
        : ColoredBox(color: communityBackground, child: body);
  }
}
