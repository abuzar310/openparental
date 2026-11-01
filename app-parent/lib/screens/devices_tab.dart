import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import '../theme/status.dart';
import '../widgets/device_card.dart';
import '../widgets/feature_tile.dart';
import '../widgets/gradient_header.dart';
import '../widgets/ui.dart';
import 'blocked_apps_screen.dart';
import 'browser_safety_screen.dart';
import 'call_sms_safety_screen.dart';
import 'content_feed_screen.dart';
import 'device_info_screen.dart';
import 'keyword_detection_screen.dart';
import 'live_mirror_screen.dart';
import 'location_history_screen.dart';
import 'location_screen.dart';
import 'notifications_screen.dart';
import 'pairing_screen.dart';
import 'setup_wizard_screen.dart';
import 'snapshot_screen.dart';
import 'usage_logs_screen.dart';
import 'watch_history_screen.dart';

/// Device hub: gradient header with a device selector, then sectioned
/// feature grids (the reference "Device" tab pattern).
class DevicesTab extends ConsumerWidget {
  const DevicesTab({super.key});

  Future<void> _startPairing(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final pairing = await ref.read(apiProvider).createPairing();
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => PairingScreen(pairing: pairing)),
      );
      ref.invalidate(devicesProvider);
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text('Could not start pairing: $e')));
    }
  }

  Future<void> _command(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
    String type,
    String label, [
    Map<String, dynamic>? payload,
  ]) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiProvider).sendCommand(deviceId, type, payload);
      messenger.showSnackBar(SnackBar(content: Text('$label sent')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  void _openFeed(BuildContext context, Device device, String feedKey) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ContentFeedScreen(
          deviceId: device.id,
          deviceName: device.name,
          feedKey: feedKey,
        ),
      ),
    );
  }

  void _switchDevice(
      BuildContext context, WidgetRef ref, List<Device> devices) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            for (final d in devices) ...[
              DeviceCard(
                device: d,
                onTap: () {
                  ref.read(selectedDeviceIdProvider.notifier).state = d.id;
                  Navigator.pop(sheet);
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesProvider);
    final selectedId = ref.watch(selectedDeviceIdProvider);

    return devicesAsync.when(
      loading: () => const HeaderShell(
        header: Row(children: [Expanded(child: HeaderTitle('Devices'))]),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => HeaderShell(
        header: const Row(children: [Expanded(child: HeaderTitle('Devices'))]),
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(devicesProvider.future),
          child: EmptyState(
            icon: Icons.wifi_off_rounded,
            title: "Couldn't reach the server",
            subtitle: '$e',
          ),
        ),
      ),
      data: (devices) {
        if (devices.isEmpty) {
          return HeaderShell(
            header:
                const Row(children: [Expanded(child: HeaderTitle('Devices'))]),
            body: Builder(builder: (context) {
              final muted = Theme.of(context).colorScheme.onSurfaceVariant;
              return ListView(
                padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
                children: [
                  Icon(Icons.smartphone, size: 44, color: muted),
                  const SizedBox(height: 16),
                  Text(
                    'No devices yet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Pair your child's phone to start — they'll see "
                    'everything this app does.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const SetupWizardScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.rocket_launch_rounded),
                    label: const Text('Setup guide (FlashGet-style)'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _startPairing(context, ref),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Quick pair only'),
                  ),
                ],
              );
            }),
          );
        }

        final device = devices.firstWhere(
          (d) => d.id == selectedId,
          orElse: () => devices.first,
        );

        return HeaderShell(
          header: _DeviceHeader(
            device: device,
            canSwitch: devices.length > 1,
            onSwitch: () => _switchDevice(context, ref, devices),
            onAdd: () => _startPairing(context, ref),
          ),
          body: RefreshIndicator(
            onRefresh: () => ref.refresh(devicesProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                FeatureSection(
                  title: 'Live monitoring',
                  tiles: [
                    FeatureTile(
                      icon: Icons.screen_share_rounded,
                      label: 'Screen mirror',
                      color: AppColors.online,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => LiveMirrorScreen(device: device),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.photo_camera_rounded,
                      label: 'Screenshot',
                      color: AppColors.brand,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => LiveMirrorScreen(
                            device: device,
                            mode: 'screenshot',
                          ),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.schedule_rounded,
                      label: 'Scheduled snaps',
                      color: AppColors.offline,
                      onTap: () => _openFeed(context, device, 'scheduled'),
                    ),
                    FeatureTile(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      color: AppColors.brand,
                      onTap: () => _command(
                        context,
                        ref,
                        device.id,
                        'CAMERA_SNAPSHOT',
                        'Camera snapshot',
                        {'camera': 'front'},
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.collections_rounded,
                      label: 'Camera gallery',
                      color: AppColors.offline,
                      onTap: () => _openFeed(context, device, 'camera'),
                    ),
                    FeatureTile(
                      icon: Icons.hearing_rounded,
                      label: 'One-way audio',
                      color: AppColors.attention,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SnapshotScreen(device: device),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.fiber_manual_record_rounded,
                      label: 'Screen record',
                      color: AppColors.alert,
                      onTap: () => _command(
                        context,
                        ref,
                        device.id,
                        'SCREEN_RECORD',
                        'Screen record',
                        {'action': 'start'},
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.video_library_rounded,
                      label: 'Recordings',
                      color: AppColors.alert,
                      onTap: () => _openFeed(context, device, 'recordings'),
                    ),
                    FeatureTile(
                      icon: Icons.tune_rounded,
                      label: 'More live tools',
                      color: AppColors.brand,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SnapshotScreen(device: device),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FeatureSection(
                  title: 'Location',
                  tiles: [
                    FeatureTile(
                      icon: Icons.location_on_rounded,
                      label: 'Live location',
                      color: AppColors.brand,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => LocationScreen(device: device),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.history_rounded,
                      label: 'Location history',
                      color: AppColors.offline,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              LocationHistoryScreen(device: device),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.fence_rounded,
                      label: 'Geofences',
                      color: AppColors.online,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              LocationHistoryScreen(device: device),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FeatureSection(
                  title: 'Screen time & rules',
                  tiles: [
                    FeatureTile(
                      icon: Icons.timeline_rounded,
                      label: 'Usage & activity',
                      color: AppColors.brand,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => UsageLogsScreen(
                            deviceId: device.id,
                            deviceName: device.name,
                          ),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.block_rounded,
                      label: 'App rules',
                      color: AppColors.attention,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const BlockedAppsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FeatureSection(
                  title: 'Communication',
                  tiles: [
                    FeatureTile(
                      icon: Icons.phone_rounded,
                      label: 'Calls',
                      color: AppColors.online,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CallSmsSafetyScreen(
                            deviceId: device.id,
                            deviceName: device.name,
                          ),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.sms_rounded,
                      label: 'Messages',
                      color: AppColors.brand,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CallSmsSafetyScreen(
                            deviceId: device.id,
                            deviceName: device.name,
                            initialTab: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FeatureSection(
                  title: 'Content safety',
                  tiles: [
                    FeatureTile(
                      icon: Icons.language_rounded,
                      label: 'Browser',
                      color: AppColors.offline,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => BrowserSafetyScreen(
                            deviceId: device.id,
                            deviceName: device.name,
                          ),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.notifications_rounded,
                      label: 'Notifications',
                      color: AppColors.attention,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => NotificationsScreen(
                            deviceId: device.id,
                            deviceName: device.name,
                          ),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.flag_rounded,
                      label: 'Keywords',
                      color: AppColors.alert,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => KeywordDetectionScreen(
                            deviceId: device.id,
                            deviceName: device.name,
                          ),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.play_circle_rounded,
                      label: 'Watch history',
                      color: AppColors.brand,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => WatchHistoryScreen(
                            deviceId: device.id,
                            deviceName: device.name,
                          ),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.photo_library_rounded,
                      label: 'Albums safety',
                      color: AppColors.online,
                      onTap: () => _openFeed(context, device, 'albums'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FeatureSection(
                  title: 'Device',
                  tiles: [
                    FeatureTile(
                      icon: Icons.smartphone,
                      label: 'Device info',
                      color: AppColors.offline,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => DeviceInfoScreen(device: device),
                        ),
                      ),
                    ),
                    FeatureTile(
                      icon: Icons.lock_rounded,
                      label: 'Lock now',
                      color: AppColors.alert,
                      onTap: () =>
                          _command(context, ref, device.id, 'LOCK', 'Lock'),
                    ),
                    FeatureTile(
                      icon: Icons.qr_code_rounded,
                      label: 'Add device',
                      color: AppColors.brand,
                      onTap: () => _startPairing(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'After setup, use Hide and continue on the child phone to remove the launcher icon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  final Device device;
  final bool canSwitch;
  final VoidCallback onSwitch;
  final VoidCallback onAdd;
  const _DeviceHeader({
    required this.device,
    required this.canSwitch,
    required this.onSwitch,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final s = deviceStatusStyle(device.status);
    final initial =
        device.name.isNotEmpty ? device.name[0].toUpperCase() : '?';

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: canSwitch ? onSwitch : null,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (canSwitch)
                      const Icon(Icons.expand_more_rounded,
                          color: Colors.white70, size: 22),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  StatusDot(s.color, size: 8),
                  const SizedBox(width: 6),
                  Text(
                    s.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '${device.batteryPct != null ? ' · ${device.batteryPct}%' : ''}'
                      ' · ${timeAgo(device.lastSeenAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          tooltip: 'Pair a device',
        ),
      ],
    );
  }
}
