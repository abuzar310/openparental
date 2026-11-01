'use client';

import Link from 'next/link';
import { useParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import { getContent, getPhotoFlags, type ContentItem, type PhotoFlag } from '@/lib/api';

const META: Record<
  string,
  { title: string; icon: string; sources: string[]; empty: string }
> = {
  notification: {
    title: 'Notifications',
    icon: '🔔',
    sources: ['notification'],
    empty: 'No notifications synced yet.',
  },
  browser: {
    title: 'Browser history',
    icon: '🌐',
    sources: ['browser'],
    empty: 'No browsing activity yet.',
  },
  keyword: {
    title: 'Keyword alerts',
    icon: '⚠️',
    sources: ['keyword'],
    empty: 'No flagged keywords yet.',
  },
  sms: {
    title: 'Messages (SMS)',
    icon: '💬',
    sources: ['sms'],
    empty: 'No SMS captured yet.',
  },
  calllog: {
    title: 'Calls',
    icon: '📞',
    sources: ['calllog'],
    empty: 'No call activity yet.',
  },
  videos: {
    title: 'Watch history',
    icon: '▶️',
    sources: ['youtube', 'tiktok'],
    empty: 'No watch history yet.',
  },
  camera: {
    title: 'Remote camera snapshots',
    icon: '📷',
    sources: ['camera'],
    empty: 'No snapshots yet. Tap Remote camera on the device hub.',
  },
  recordings: {
    title: 'Recordings',
    icon: '🎙️',
    sources: ['ambient', 'screen_record'],
    empty: 'No ambient or screen recordings uploaded yet.',
  },
  albums: {
    title: 'Albums safety',
    icon: '🖼️',
    sources: [],
    empty: 'No new gallery activity flagged yet. Grant Photos access on the child device.',
  },
  scheduled: {
    title: 'Scheduled snapshots',
    icon: '🕐',
    sources: ['scheduled_snapshot'],
    empty: 'No scheduled snapshots yet. Set interval under App rules.',
  },
};

export default function FeedPage() {
  const params = useParams();
  const id = params.id as string;
  const sourceKey = params.source as string;
  const meta = META[sourceKey] ?? {
    title: sourceKey,
    icon: '📝',
    sources: [sourceKey],
    empty: 'Nothing captured yet.',
  };

  const [items, setItems] = useState<ContentItem[] | null>(null);
  const [photos, setPhotos] = useState<PhotoFlag[] | null>(null);

  useEffect(() => {
    if (sourceKey === 'albums') {
      getPhotoFlags(id).then(setPhotos);
      return;
    }
    Promise.all(meta.sources.map((s) => getContent(id, s))).then((lists) => {
      const merged = lists
        .flat()
        .sort(
          (a, b) =>
            new Date(b.occurredAt).getTime() - new Date(a.occurredAt).getTime(),
        );
      setItems(merged);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, sourceKey]);

  return (
    <div className="max-w-2xl">
      <Link href={`/dashboard/devices/${id}`} className="text-sm text-brand">
        ← Device
      </Link>
      <h1 className="text-2xl font-semibold mt-2">
        {meta.icon} {meta.title}
      </h1>

      {sourceKey === 'albums' ? (
        photos == null ? (
          <p className="mt-6 text-muted">Loading…</p>
        ) : photos.length === 0 ? (
          <p className="mt-6 text-muted text-sm">{meta.empty}</p>
        ) : (
          <ul className="mt-6 space-y-1">
            {photos.map((p) => (
              <li
                key={p.id}
                className="rounded-xl border border-line bg-white px-3 py-2 flex justify-between gap-2"
              >
                <span className="text-sm font-medium capitalize">{p.category}</span>
                <time className="text-xs text-muted shrink-0">
                  {new Date(p.occurredAt).toLocaleString()}
                </time>
              </li>
            ))}
          </ul>
        )
      ) : items == null ? (
        <p className="mt-6 text-muted">Loading…</p>
      ) : items.length === 0 ? (
        <p className="mt-6 text-muted text-sm">{meta.empty}</p>
      ) : (
        <ul className="mt-6 space-y-1">
          {items.map((c) => (
            <li
              key={c.id}
              className="rounded-xl border border-line bg-white px-3 py-2"
            >
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-medium truncate">
                  {c.counterparty ?? meta.title}
                </span>
                <time className="text-xs text-muted shrink-0">
                  {new Date(c.occurredAt).toLocaleString()}
                </time>
              </div>
              {(c.source === 'camera' || c.source === 'scheduled_snapshot') &&
              c.body.length > 100 ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={`data:image/jpeg;base64,${c.body}`}
                  alt="snapshot"
                  className="mt-2 rounded-lg max-h-80 w-full object-contain bg-black/5"
                />
              ) : c.source === 'ambient' && c.body.length > 100 ? (
                // eslint-disable-next-line jsx-a11y/media-has-caption
                <audio
                  controls
                  className="mt-2 w-full"
                  src={`data:audio/mp4;base64,${c.body}`}
                />
              ) : c.source === 'screen_record' && c.body.length > 100 ? (
                // eslint-disable-next-line jsx-a11y/media-has-caption
                <video
                  controls
                  className="mt-2 rounded-lg max-h-80 w-full bg-black"
                  src={`data:video/mp4;base64,${c.body}`}
                />
              ) : (
                <p className="text-sm text-ink/80 mt-0.5 break-words">
                  {c.body.length > 120 ? `${c.body.slice(0, 80)}…` : c.body}
                </p>
              )}
              {c.matched && (
                <span className="inline-block mt-1 text-[11px] rounded bg-alert/10 text-alert px-1.5 py-0.5">
                  flagged: {c.matched}
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
