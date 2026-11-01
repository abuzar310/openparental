import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';

/// Call logs and SMS messages from the child's device.
/// Mirrors the FlashGet Kids "Call & SMS Safety" screen.
class CallSmsSafetyScreen extends ConsumerStatefulWidget {
  final String deviceId;
  final String deviceName;
  final int initialTab;
  const CallSmsSafetyScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    this.initialTab = 0,
  });

  @override
  ConsumerState<CallSmsSafetyScreen> createState() =>
      _CallSmsSafetyScreenState();
}

class _CallSmsSafetyScreenState extends ConsumerState<CallSmsSafetyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<ContentItem> _calls = [];
  List<ContentItem> _sms = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    _error = null;
    try {
      final api = ref.read(apiProvider);
      final results = await Future.wait([
        api.getContent(widget.deviceId, source: 'calllog'),
        api.getContent(widget.deviceId, source: 'sms'),
      ]);
      _calls = results[0];
      _sms = results[1];
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call & SMS Safety'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.phone_rounded), text: 'Calls'),
            Tab(icon: Icon(Icons.message_rounded), text: 'SMS'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _loadData)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _CallLogTab(
                      calls: _calls,
                      deviceName: widget.deviceName,
                      onRefresh: _loadData,
                    ),
                    _SmsTab(
                      sms: _sms,
                      deviceName: widget.deviceName,
                      onRefresh: _loadData,
                    ),
                  ],
                ),
    );
  }
}

/// Tab showing call log entries grouped by date.
class _CallLogTab extends StatelessWidget {
  final List<ContentItem> calls;
  final String deviceName;
  final VoidCallback onRefresh;

  const _CallLogTab({
    required this.calls,
    required this.deviceName,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (calls.isEmpty) {
      return _EmptyState(
        icon: Icons.phone_rounded,
        message: 'No call activity recorded yet',
        subtitle: 'Call logs will appear here once the child makes or receives calls.',
        onRefresh: onRefresh,
      );
    }

    final grouped = _groupByDate(calls);
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.phone_rounded, size: 18, color: AppColors.brand),
                const SizedBox(width: 6),
                Text('${calls.length} calls',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                Text(deviceName,
                    style: TextStyle(fontSize: 12, color: AppColors.mutedLight)),
              ],
            ),
          ),
          ...grouped.entries.map(
            (entry) => _DateGroup(
              label: entry.key,
              children: entry.value.map((call) => _CallCard(item: call)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<ContentItem>> _groupByDate(List<ContentItem> items) {
    final map = <String, List<ContentItem>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final item in items) {
      final date = item.occurredAt ?? now;
      String label;
      if (date.isAfter(today)) {
        label = 'Today';
      } else if (date.isAfter(yesterday)) {
        label = 'Yesterday';
      } else {
        label =
            '${date.day}/${date.month}/${date.year}';
      }
      map.putIfAbsent(label, () => []);
      map[label]!.add(item);
    }
    return map;
  }
}

/// Tab showing SMS messages grouped by sender.
class _SmsTab extends StatelessWidget {
  final List<ContentItem> sms;
  final String deviceName;
  final VoidCallback onRefresh;

  const _SmsTab({
    required this.sms,
    required this.deviceName,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (sms.isEmpty) {
      return _EmptyState(
        icon: Icons.message_rounded,
        message: 'No SMS messages recorded yet',
        subtitle: 'Incoming SMS messages will appear here.',
        onRefresh: onRefresh,
      );
    }

    // Group by sender
    final grouped = <String, List<ContentItem>>{};
    for (final msg in sms) {
      final sender = msg.counterparty ?? 'Unknown';
      grouped.putIfAbsent(sender, () => []);
      grouped[sender]!.add(msg);
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.message_rounded, size: 18, color: AppColors.online),
                const SizedBox(width: 6),
                Text('${sms.length} messages',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                Text(deviceName,
                    style: TextStyle(fontSize: 12, color: AppColors.mutedLight)),
              ],
            ),
          ),
          ...grouped.entries.map(
            (entry) => _SenderGroup(
              sender: entry.key,
              messages: entry.value,
            ),
          ),
        ],
      ),
    );
  }
}

/// A date group header with a list of items.
class _DateGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _DateGroup({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6, left: 4),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedLight)),
        ),
        ...children,
      ],
    );
  }
}

/// A sender group with a header and message cards.
class _SenderGroup extends StatelessWidget {
  final String sender;
  final List<ContentItem> messages;
  const _SenderGroup({required this.sender, required this.messages});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4, left: 4),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.online.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_rounded,
                    size: 16, color: AppColors.online),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(sender,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${messages.length}',
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        ...messages.map((msg) => _SmsCard(item: msg)),
      ],
    );
  }
}

/// Card for a single call log entry.
class _CallCard extends StatelessWidget {
  final ContentItem item;
  const _CallCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = item.body;
    final isIncoming = body.contains('Incoming') || body.contains('from');
    final isOutgoing = body.contains('Outgoing') || body.contains('to');

    IconData icon;
    Color color;
    if (isIncoming) {
      icon = Icons.phone_in_talk_rounded;
      color = AppColors.online;
    } else if (isOutgoing) {
      icon = Icons.phone_forwarded_rounded;
      color = AppColors.brand;
    } else {
      icon = Icons.phone_missed_rounded;
      color = AppColors.alert;
    }

    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: color, size: 22),
          title: Text(
            item.counterparty ?? 'Unknown',
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            body.length > 60 ? body.substring(0, 60) : body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          trailing: Text(
            _formatTime(item.occurredAt),
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Call Details',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _detailRow('Number', item.counterparty ?? 'Unknown'),
            _detailRow('Type', item.body.contains('Incoming') ? 'Incoming' : 'Outgoing'),
            _detailRow('Time', item.occurredAt?.toLocal().toString() ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: AppColors.mutedLight)),
          ),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Card for a single SMS message.
class _SmsCard extends StatelessWidget {
  final ContentItem item;
  const _SmsCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Card(
        margin: const EdgeInsets.only(bottom: 4),
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.message_rounded,
                      size: 14, color: AppColors.online),
                  const SizedBox(width: 6),
                  Text(
                    item.counterparty ?? 'Unknown',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(item.occurredAt),
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('SMS Details',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _detailRow('From', item.counterparty ?? 'Unknown'),
            const Divider(),
            Text(item.body,
                style: const TextStyle(fontSize: 14, height: 1.4)),
            const SizedBox(height: 12),
            Text(
              item.occurredAt?.toLocal().toString() ?? '',
              style: TextStyle(fontSize: 11, color: AppColors.mutedLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: AppColors.mutedLight)),
          ),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Empty state for tabs with no data.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String subtitle;
  final VoidCallback onRefresh;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.subtitle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 32, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(message,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state with retry.
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48, color: AppColors.alert),
            const SizedBox(height: 16),
            Text('Failed to load',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared helpers
String _formatTime(DateTime? dt) {
  if (dt == null) return '';
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
