'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import {
  Device,
  DeviceLocation,
  latestLocation,
  listDevices,
  releaseDeviceOwner,
  sendCommand,
} from '@/lib/api';

type Card = {
  icon: string;
  label: string;
  href?: string;
  cmd?: { type: string; payload?: Record<string, unknown> };
  soon?: boolean;
  danger?: boolean;
};

export default function DeviceDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const [device, setDevice] = useState<Device | null>(null);
  const [loc, setLoc] = useState<DeviceLocation | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    listDevices().then((list) => setDevice(list.find((d) => d.id === id) ?? null));
    latestLocation(id).then(setLoc);
  }, [id]);

  async function runCommand(type: string, label: string, payload?: Record<string, unknown>) {
    setBusy(true);
    setMessage(null);
    try {
      await sendCommand(id, type, payload);
      setMessage(`${label} sent`);
    } catch (e) {
      setMessage(e instanceof Error ? e.message : 'Command failed');
    } finally {
      setBusy(false);
    }
  }

  async function release() {
    if (
      !window.confirm(
        'Lift the uninstall / force-stop lock and relinquish device ownership? The app can then be removed.',
      )
    ) {
      return;
    }
    await runCommand('RELEASE_OWNER', 'Release protection');
  }

  if (!device) {
    return (
      <p className="text-muted">
        <Link href="/dashboard" className="text-brand">
          ← Back
        </Link>
        {' · '}
        Loading…
      </p>
    );
  }

  const base = `/dashboard/devices/${id}`;
  const mapsUrl =
    loc != null
      ? `https://www.google.com/maps/search/?api=1&query=${loc.lat},${loc.lng}`
      : null;

  const groups: { title: string; cards: Card[] }[] = [
    {
      title: 'Live monitoring',
      cards: [
        { icon: '🖥️', label: 'Screen mirror', href: `${base}/screen?mode=mirror` },
        { icon: '📸', label: 'Screenshot now', href: `${base}/screen?mode=screenshot` },
        { icon: '🕐', label: 'Scheduled snapshots', href: `${base}/feed/scheduled` },
        { icon: '📷', label: 'Camera snapshot', cmd: { type: 'CAMERA_SNAPSHOT', payload: { camera: 'front' } } },
        { icon: '🖼️', label: 'Camera gallery', href: `${base}/feed/camera` },
        { icon: '🎙️', label: 'Ambient audio', cmd: { type: 'AMBIENT_RECORD', payload: { action: 'start' } } },
        { icon: '⏺️', label: 'Screen record', cmd: { type: 'SCREEN_RECORD', payload: { action: 'start' } } },
        { icon: '📼', label: 'Recordings', href: `${base}/feed/recordings` },
      ],
    },
    {
      title: 'Location',
      cards: [
        { icon: '📍', label: 'Request location', cmd: { type: 'REQUEST_LOCATION' } },
        { icon: '🗺️', label: 'Location history', href: `${base}/locations` },
        { icon: '🧭', label: 'Geofences', href: `${base}/geofences` },
      ],
    },
    {
      title: 'Screen time & rules',
      cards: [
        { icon: '⏱️', label: 'Usage & activity', href: `${base}/activity` },
        { icon: '🧩', label: 'App rules & limits', href: '/dashboard/rules' },
        { icon: '🌙', label: 'Downtime / bedtime', href: '/dashboard/rules' },
      ],
    },
    {
      title: 'Communication',
      cards: [
        { icon: '📞', label: 'Calls', href: `${base}/feed/calllog` },
        { icon: '💬', label: 'Messages (SMS)', href: `${base}/feed/sms` },
      ],
    },
    {
      title: 'Content safety',
      cards: [
        { icon: '🌐', label: 'Browser history', href: `${base}/feed/browser` },
        { icon: '🔔', label: 'Notifications', href: `${base}/feed/notification` },
        { icon: '⚠️', label: 'Keyword alerts', href: `${base}/feed/keyword` },
        { icon: '▶️', label: 'Watch history', href: `${base}/feed/videos` },
        { icon: '🖼️', label: 'Albums safety', href: `${base}/feed/albums` },
      ],
    },
    {
      title: 'Insights',
      cards: [
        { icon: '📊', label: 'Activity log', href: `${base}/activity` },
        { icon: '🤖', label: 'AI usage report', href: `${base}/ai-report` },
      ],
    },
    {
      title: 'Device controls',
      cards: [
        { icon: '🔒', label: 'Lock now', cmd: { type: 'LOCK' } },
        { icon: '📡', label: 'Ping', cmd: { type: 'PING' } },
        { icon: '🔓', label: 'Release protection', danger: true },
      ],
    },
  ];

  return (
    <div>
      <Link href="/dashboard" className="text-sm text-brand">
        ← Devices
      </Link>
      <h1 className="text-2xl font-semibold mt-2">{device.name}</h1>
      <p className="text-muted text-sm">
        {device.status}
        {device.batteryPct != null ? ` · ${device.batteryPct}%` : ''}
        {device.model ? ` · ${device.model}` : ''}
      </p>

      {message && (
        <p className="mt-4 text-sm rounded-xl bg-brand/10 text-brand px-3 py-2">
          {message}
        </p>
      )}

      {loc && mapsUrl && (
        <a
          href={mapsUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="mt-4 inline-flex items-center gap-2 text-sm text-brand underline"
        >
          📍 {loc.lat.toFixed(4)}, {loc.lng.toFixed(4)} — open in Maps
        </a>
      )}

      {groups.map((g) => (
        <section key={g.title} className="mt-8">
          <h2 className="text-xs font-semibold uppercase tracking-wide text-muted">
            {g.title}
          </h2>
          <div className="mt-3 grid grid-cols-2 sm:grid-cols-3 gap-3">
            {g.cards.map((c) => (
              <FeatureCard
                key={c.label}
                card={c}
                busy={busy}
                onCmd={() =>
                  c.danger
                    ? release()
                    : c.cmd && runCommand(c.cmd.type, c.label, c.cmd.payload)
                }
              />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

function FeatureCard({
  card,
  busy,
  onCmd,
}: {
  card: Card;
  busy: boolean;
  onCmd: () => void;
}) {
  const cls =
    'rounded-2xl border bg-white p-4 flex flex-col gap-2 text-left transition ' +
    (card.soon
      ? 'border-line opacity-50'
      : card.danger
        ? 'border-alert/30 hover:border-alert/60'
        : 'border-line hover:border-brand/50');

  const inner = (
    <>
      <span className="text-2xl">{card.icon}</span>
      <span className="text-sm font-medium">
        {card.label}
        {card.soon && <span className="text-muted font-normal"> · soon</span>}
      </span>
    </>
  );

  if (card.href && !card.soon) {
    return (
      <Link href={card.href} className={cls}>
        {inner}
      </Link>
    );
  }
  return (
    <button
      type="button"
      disabled={busy || card.soon}
      onClick={onCmd}
      className={cls + ' disabled:cursor-default'}
    >
      {inner}
    </button>
  );
}
