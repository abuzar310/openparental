'use client';

import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import {
  getInstalledApps,
  getPolicy,
  listDevices,
  updatePolicy,
  type InstalledApp,
  type PolicyRules,
} from '@/lib/api';

type AppState = 'allowed' | 'blocked' | 'default';

export default function RulesPage() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const [apps, setApps] = useState<InstalledApp[]>([]);
  const [query, setQuery] = useState('');
  const [state, setState] = useState<Record<string, AppState>>({});
  const [limits, setLimits] = useState<Record<string, number>>({});
  const [blockedDomains, setBlockedDomains] = useState('');
  const [bedtimeOn, setBedtimeOn] = useState(false);
  const [bedtimeStart, setBedtimeStart] = useState('22:00');
  const [bedtimeEnd, setBedtimeEnd] = useState('06:30');
  const [blockAllExceptAllowed, setBlockAllExceptAllowed] = useState(false);
  const [blockNewApps, setBlockNewApps] = useState(false);
  const [customKeywords, setCustomKeywords] = useState('');
  const [snapshotIntervalMinutes, setSnapshotIntervalMinutes] = useState(0);

  useEffect(() => {
    (async () => {
      const devices = await listDevices().catch(() => []);
      let inv: InstalledApp[] = [];
      for (const d of devices) {
        inv = await getInstalledApps(d.id);
        if (inv.length) break;
      }
      setApps(inv);

      const r = await getPolicy();
      const st: Record<string, AppState> = {};
      (r.blockedApps ?? []).forEach((p) => (st[p] = 'blocked'));
      (r.allowedApps ?? []).forEach((p) => (st[p] = 'allowed'));
      setState(st);
      setBlockedDomains((r.blockedDomains ?? []).join('\n'));
      const lm: Record<string, number> = {};
      (r.appLimits ?? []).forEach((l) => (lm[l.pkg] = l.dailyMinutes));
      setLimits(lm);
      setBlockAllExceptAllowed(r.blockAllExceptAllowed ?? false);
      setBlockNewApps(r.blockNewApps ?? false);
      setCustomKeywords((r.customKeywords ?? []).join('\n'));
      setSnapshotIntervalMinutes(r.snapshotIntervalMinutes ?? 0);
      const bed = (r.schedules ?? []).find((s) => s.blockAll);
      if (bed) {
        setBedtimeOn(true);
        setBedtimeStart(bed.start);
        setBedtimeEnd(bed.end);
      }
      setLoading(false);
    })();
  }, []);

  const labelOf = useMemo(() => {
    const m = new Map(apps.map((a) => [a.pkg, a.label]));
    return (pkg: string) => m.get(pkg) ?? pkg;
  }, [apps]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = q
      ? apps.filter(
          (a) =>
            a.label.toLowerCase().includes(q) || a.pkg.toLowerCase().includes(q),
        )
      : apps;
    const rank = (p: string) =>
      state[p] === 'blocked' ? 0 : state[p] === 'allowed' ? 1 : 2;
    return [...list].sort(
      (a, b) => rank(a.pkg) - rank(b.pkg) || a.label.localeCompare(b.label),
    );
  }, [apps, query, state]);

  const counts = useMemo(() => {
    let allowed = 0;
    let blocked = 0;
    for (const v of Object.values(state)) {
      if (v === 'allowed') allowed++;
      else if (v === 'blocked') blocked++;
    }
    return { allowed, blocked };
  }, [state]);

  function setAppState(pkg: string, s: AppState) {
    setState((prev) => {
      const next = { ...prev };
      if (s === 'default') delete next[pkg];
      else next[pkg] = s;
      return next;
    });
  }

  async function save() {
    setSaving(true);
    setMessage(null);
    const rules: PolicyRules = {
      blockedApps: Object.keys(state).filter((p) => state[p] === 'blocked'),
      allowedApps: Object.keys(state).filter((p) => state[p] === 'allowed'),
      blockedDomains: blockedDomains
        .split('\n')
        .map((s) => s.trim())
        .filter(Boolean),
      appLimits: Object.entries(limits)
        .filter(([, m]) => m > 0)
        .map(([pkg, dailyMinutes]) => ({ pkg, dailyMinutes })),
      schedules: bedtimeOn
        ? [{ start: bedtimeStart, end: bedtimeEnd, blockAll: true }]
        : [],
      blockAllExceptAllowed,
      blockNewApps,
      customKeywords: customKeywords
        .split('\n')
        .map((s) => s.trim())
        .filter(Boolean),
      snapshotIntervalMinutes: snapshotIntervalMinutes > 0 ? snapshotIntervalMinutes : 0,
    };
    try {
      await updatePolicy(rules);
      setMessage('Rules saved and pushed to all devices.');
    } catch (e) {
      setMessage(e instanceof Error ? e.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <p className="text-muted">Loading rules…</p>;

  return (
    <div className="max-w-2xl">
      <Link href="/dashboard" className="text-sm text-brand">
        ← Devices
      </Link>
      <h1 className="text-2xl font-semibold mt-2">App rules</h1>
      <p className="text-muted text-sm">Applied to every paired device.</p>

      {message && (
        <p className="mt-4 text-sm rounded-xl bg-brand/10 text-brand px-3 py-2">
          {message}
        </p>
      )}

      {/* ---- Quick settings ---- */}
      <section className="mt-8 rounded-2xl border border-line bg-white p-5">
        <h2 className="font-semibold">Quick settings</h2>
        <label className="flex items-start gap-3 mt-3 text-sm">
          <input
            type="checkbox"
            checked={blockAllExceptAllowed}
            onChange={(e) => setBlockAllExceptAllowed(e.target.checked)}
            className="mt-1"
          />
          <span>
            <b>Block all apps except allowed</b>
            <span className="block text-xs text-muted">
              Every app not in the Allowed list is blocked (system/home apps stay
              usable).
            </span>
          </span>
        </label>
        <label className="flex items-start gap-3 mt-3 text-sm">
          <input
            type="checkbox"
            checked={blockNewApps}
            onChange={(e) => setBlockNewApps(e.target.checked)}
            className="mt-1"
          />
          <span>
            <b>Block newly installed apps</b>
            <span className="block text-xs text-muted">
              Any app installed from now on is blocked until you allow it.
            </span>
          </span>
        </label>
        <label className="block mt-4 text-sm">
          <b>Scheduled screen snapshots</b>
          <span className="block text-xs text-muted mb-2">
            FlashGet-style automatic captures (minutes between shots). Device minimum
            interval is 15 minutes. 0 = off.
          </span>
          <input
            type="number"
            min={0}
            max={1440}
            step={15}
            value={snapshotIntervalMinutes}
            onChange={(e) =>
              setSnapshotIntervalMinutes(Math.max(0, Number(e.target.value) || 0))
            }
            className="w-full rounded-xl border border-line bg-white p-2"
          />
        </label>
      </section>

      {/* ---- Per-app tri-state ---- */}
      <section className="mt-6 rounded-2xl border border-line bg-white p-5">
        <div className="flex items-center justify-between">
          <h2 className="font-semibold">Apps</h2>
          <span className="text-xs text-muted">
            {counts.allowed} allowed · {counts.blocked} blocked
          </span>
        </div>

        {apps.length === 0 ? (
          <p className="text-xs text-muted mt-3">
            The app list appears once a paired device reports in. Until then, use
            the device&apos;s activity to see installed apps.
          </p>
        ) : (
          <>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search apps…"
              className="mt-3 w-full rounded-xl border border-line bg-white p-2 text-sm"
            />
            <ul className="mt-3 max-h-80 overflow-auto divide-y divide-line">
              {filtered.map((a) => (
                <li key={a.pkg} className="flex items-center gap-3 py-2">
                  {a.iconB64 ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={`data:image/png;base64,${a.iconB64}`}
                      alt=""
                      className="h-9 w-9 rounded-lg border border-line shrink-0 object-cover"
                    />
                  ) : (
                    <div className="h-9 w-9 rounded-lg bg-surface border border-line flex items-center justify-center text-xs font-semibold text-muted shrink-0">
                      {a.label.slice(0, 2).toUpperCase()}
                    </div>
                  )}
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium truncate">{a.label}</p>
                    <p className="text-xs text-muted truncate">{a.pkg}</p>
                  </div>
                  <TriState
                    value={state[a.pkg] ?? 'default'}
                    onChange={(s) => setAppState(a.pkg, s)}
                  />
                </li>
              ))}
            </ul>
          </>
        )}
      </section>

      {/* ---- Daily limits ---- */}
      <section className="mt-6 rounded-2xl border border-line bg-white p-5">
        <h2 className="font-semibold">Daily time limits</h2>
        <p className="text-xs text-muted mt-1 mb-3">
          Minutes per day. The app is blocked once the limit is reached.
        </p>
        {Object.keys(limits).map((pkg) => (
          <div key={pkg} className="flex items-center gap-2 mb-2">
            <span className="flex-1 text-sm truncate">{labelOf(pkg)}</span>
            <input
              type="number"
              value={limits[pkg]}
              onChange={(e) =>
                setLimits((xs) => ({ ...xs, [pkg]: Number(e.target.value) || 0 }))
              }
              className="w-20 rounded-xl border border-line bg-white p-2 text-sm"
            />
            <span className="text-xs text-muted">min</span>
            <button
              type="button"
              onClick={() =>
                setLimits((xs) => {
                  const n = { ...xs };
                  delete n[pkg];
                  return n;
                })
              }
              className="px-2 rounded-lg border border-line text-sm"
            >
              ✕
            </button>
          </div>
        ))}
        {apps.length > 0 && (
          <select
            value=""
            onChange={(e) => {
              if (e.target.value)
                setLimits((xs) => ({ ...xs, [e.target.value]: 60 }));
            }}
            className="mt-2 w-full rounded-xl border border-line bg-white p-2 text-sm"
          >
            <option value="">+ Add an app to limit…</option>
            {apps
              .filter((a) => !(a.pkg in limits))
              .map((a) => (
                <option key={a.pkg} value={a.pkg}>
                  {a.label}
                </option>
              ))}
          </select>
        )}
      </section>

      {/* ---- Bedtime ---- */}
      <section className="mt-6 rounded-2xl border border-line bg-white p-5">
        <h2 className="font-semibold">Bedtime (block all)</h2>
        <label className="flex items-center gap-2 mt-3 mb-2 text-sm">
          <input
            type="checkbox"
            checked={bedtimeOn}
            onChange={(e) => setBedtimeOn(e.target.checked)}
          />
          Enable bedtime block (overnight supported)
        </label>
        {bedtimeOn && (
          <div className="flex gap-3 items-center text-sm">
            <input
              type="time"
              value={bedtimeStart}
              onChange={(e) => setBedtimeStart(e.target.value)}
              className="rounded-xl border border-line bg-white p-2"
            />
            <span className="text-muted">to</span>
            <input
              type="time"
              value={bedtimeEnd}
              onChange={(e) => setBedtimeEnd(e.target.value)}
              className="rounded-xl border border-line bg-white p-2"
            />
          </div>
        )}
      </section>

      <section className="mt-6 rounded-2xl border border-line bg-white p-5">
        <h2 className="font-semibold">Custom keywords</h2>
        <p className="text-xs text-muted mt-1 mb-3">
          One phrase per line — matched in social app notifications on the child device
          (FlashGet Keyword Detection).
        </p>
        <textarea
          value={customKeywords}
          onChange={(e) => setCustomKeywords(e.target.value)}
          rows={4}
          className="w-full rounded-xl border border-line bg-white p-3 text-sm"
          placeholder="meet me alone&#10;send pics"
        />
      </section>

      {/* ---- Blocked websites ---- */}
      <section className="mt-6 rounded-2xl border border-line bg-white p-5">
        <h2 className="font-semibold">Blocked websites</h2>
        <p className="text-xs text-muted mt-1 mb-3">
          One domain per line. Adult/malware categories are filtered upstream.
        </p>
        <textarea
          value={blockedDomains}
          onChange={(e) => setBlockedDomains(e.target.value)}
          rows={4}
          className="w-full rounded-xl border border-line bg-white p-3 font-mono text-sm"
          placeholder="example.com"
        />
      </section>

      <button
        type="button"
        disabled={saving}
        onClick={save}
        className="mt-6 rounded-2xl bg-brand text-white px-6 py-3 font-medium disabled:opacity-50"
      >
        {saving ? 'Saving…' : 'Save rules'}
      </button>
    </div>
  );
}

function TriState({
  value,
  onChange,
}: {
  value: AppState;
  onChange: (s: AppState) => void;
}) {
  const opt = (s: AppState, label: string, active: string) => (
    <button
      type="button"
      onClick={() => onChange(s)}
      className={
        'text-xs px-2.5 py-1 font-medium ' +
        (value === s ? active : 'text-muted')
      }
    >
      {label}
    </button>
  );
  return (
    <div className="flex rounded-full border border-line overflow-hidden shrink-0">
      {opt('allowed', 'Allow', 'bg-online/10 text-online')}
      {opt('default', 'Default', 'bg-surface text-ink')}
      {opt('blocked', 'Block', 'bg-alert/10 text-alert')}
    </div>
  );
}
