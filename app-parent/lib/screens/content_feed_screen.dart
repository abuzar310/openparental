import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';

/// FlashGet-style content feeds (camera gallery, recordings, albums, etc.).
class ContentFeedScreen extends ConsumerStatefulWidget {
  final String deviceId;
  final String deviceName;
  /// Matches web `/feed/[source]` keys: camera, recordings, albums, …
  final String feedKey;

  const ContentFeedScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.feedKey,
  });

  @override
  ConsumerState<ContentFeedScreen> createState() => _ContentFeedScreenState();
}

class _FeedMeta {
  final String title;
  final IconData icon;
  final List<String> sources;
  final String empty;

  const _FeedMeta({
    required this.title,
    required this.icon,
    required this.sources,
    required this.empty,
  });
}

const _meta = <String, _FeedMeta>{
  'camera': _FeedMeta(
    title: 'Remote camera',
    icon: Icons.camera_alt_rounded,
    sources: ['camera'],
    empty: 'No snapshots yet. Tap Camera snapshot on the device hub.',
  ),
  'recordings': _FeedMeta(
    title: 'Recordings',
    icon: Icons.fiber_manual_record_rounded,
    sources: ['ambient', 'screen_record'],
    empty: 'No ambient or screen recordings uploaded yet.',
  ),
  'albums': _FeedMeta(
    title: 'Albums safety',
    icon: Icons.photo_library_rounded,
    sources: [],
    empty:
        'No new gallery activity flagged yet. Grant Photos on the child device.',
  ),
  'scheduled': _FeedMeta(
    title: 'Scheduled snapshots',
    icon: Icons.schedule_rounded,
    sources: ['scheduled_snapshot'],
    empty: 'No scheduled snapshots yet. Set interval in family app rules (web).',
  ),
};

class _ContentFeedScreenState extends ConsumerState<ContentFeedScreen> {
  List<ContentItem> _items = [];
  List<PhotoFlag> _photos = [];
  bool _loading = true;
  String? _error;

  _FeedMeta get meta =>
      _meta[widget.feedKey] ??
      _FeedMeta(
        title: widget.feedKey,
        icon: Icons.article_outlined,
        sources: [widget.feedKey],
        empty: 'Nothing captured yet.',
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      if (widget.feedKey == 'albums') {
        final photos = await api.getPhotoFlags(widget.deviceId);
        if (!mounted) return;
        setState(() {
          _photos = photos
            ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
          _loading = false;
        });
        return;
      }
      final lists = await Future.wait(
        meta.sources.map((s) => api.getContent(widget.deviceId, source: s)),
      );
      final merged = lists.expand((e) => e).toList()
        ..sort((a, b) {
          final ta = a.occurredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = b.occurredAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(meta.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(_error!, style: TextStyle(color: muted)),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  )
                : widget.feedKey == 'albums'
                    ? _albumList(muted)
                    : _contentList(muted),
      ),
    );
  }

  Widget _albumList(Color muted) {
    if (_photos.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [Text(meta.empty, style: TextStyle(color: muted))],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _photos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = _photos[i];
        return Card(
          child: ListTile(
            title: Text(
              p.category,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Confidence ${(p.confidence * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            trailing: Text(
              _fmt(p.occurredAt),
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ),
        );
      },
    );
  }

  Widget _contentList(Color muted) {
    if (_items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [Text(meta.empty, style: TextStyle(color: muted))],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ContentTile(item: _items[i], muted: muted),
    );
  }

  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    return '${local.month}/${local.day} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ContentTile extends StatelessWidget {
  final ContentItem item;
  final Color muted;

  const _ContentTile({required this.item, required this.muted});

  @override
  Widget build(BuildContext context) {
    final title = item.counterparty?.isNotEmpty == true
        ? item.counterparty!
        : item.source;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (item.occurredAt != null)
                  Text(
                    _shortTime(item.occurredAt!),
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _bodyWidget(),
            if (item.matched != null && item.matched!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.alert.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Flagged: ${item.matched}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.alert,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bodyWidget() {
    final body = item.body;
    if ((item.source == 'camera' || item.source == 'scheduled_snapshot') &&
        body.length > 100) {
      try {
        final bytes = base64Decode(body);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      } catch (_) {
        /* fall through */
      }
    }
    if (body.length > 120) {
      return Text('${body.substring(0, 80)}…',
          style: TextStyle(fontSize: 13, color: muted));
    }
    return Text(body, style: TextStyle(fontSize: 13, color: muted));
  }

  String _shortTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.month}/${local.day} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }
}
