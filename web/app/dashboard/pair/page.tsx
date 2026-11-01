'use client';

import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { Pairing, createPairing } from '@/lib/api';
import { buildPairingQrPayload } from '@/lib/pairing-qr';

export default function PairPage() {
  const [pairing, setPairing] = useState<Pairing | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [siteOrigin, setSiteOrigin] = useState('');
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);

  useEffect(() => {
    setSiteOrigin(window.location.origin);
  }, []);

  useEffect(() => {
    if (!pairing || !siteOrigin) {
      setQrDataUrl(null);
      return;
    }
    let cancelled = false;
    QRCode.toDataURL(buildPairingQrPayload(siteOrigin, pairing), {
      width: 280,
      margin: 2,
      errorCorrectionLevel: 'M',
    })
      .then((url) => {
        if (!cancelled) setQrDataUrl(url);
      })
      .catch(() => {
        if (!cancelled) setQrDataUrl(null);
      });
    return () => {
      cancelled = true;
    };
  }, [pairing, siteOrigin]);

  async function generate() {
    setLoading(true);
    setError(null);
    try {
      setPairing(await createPairing());
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div>
      <h1 className="text-2xl font-semibold">Pair a child device</h1>
      <ol className="mt-4 text-sm text-muted list-decimal list-inside space-y-2 max-w-lg">
        <li>Install the child APK on the kid&apos;s Android phone.</li>
        <li>Generate a code below and keep this screen open.</li>
        <li>
          On the child app, tap <strong className="text-ink">Scan QR code</strong>{' '}
          and point at the QR below (or enter the text code).
        </li>
      </ol>

      <button
        type="button"
        disabled={loading}
        onClick={generate}
        className="mt-8 rounded-2xl bg-brand text-white px-6 py-3 font-medium disabled:opacity-60"
      >
        {loading ? 'Creating…' : 'Generate pairing code'}
      </button>

      {error && <p className="mt-4 text-sm text-alert">{error}</p>}

      {pairing && (
        <div className="mt-8 rounded-3xl border border-line bg-white p-8 text-center max-w-md">
          {qrDataUrl ? (
            <>
              <p className="text-sm text-muted">Scan with the child app</p>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={qrDataUrl}
                alt="Pairing QR code"
                className="mx-auto mt-4 rounded-2xl border border-line"
                width={280}
                height={280}
              />
            </>
          ) : (
            <p className="text-sm text-muted">Generating QR…</p>
          )}
          <p className="text-sm text-muted mt-6">Or enter this code manually</p>
          <p className="text-4xl font-mono font-bold tracking-widest mt-2 text-brand">
            {pairing.code}
          </p>
          {siteOrigin && (
            <p className="text-xs text-muted mt-4 break-all">
              Server URL for manual entry: {siteOrigin}
            </p>
          )}
        </div>
      )}
    </div>
  );
}
