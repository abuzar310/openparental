import type { Pairing } from './api';

/** Payload scanned by the child app (OpenParental v1). */
export type PairingQrPayload = {
  v: 1;
  /** Backend origin, no trailing slash — e.g. https://openparental.vercel.app */
  u: string;
  /** Pairing secret (qrToken); also accepted: manual short code on device. */
  t: string;
};

export function buildPairingQrPayload(
  siteOrigin: string,
  pairing: Pick<Pairing, 'qrToken'>,
): string {
  const payload: PairingQrPayload = {
    v: 1,
    u: siteOrigin.replace(/\/$/, ''),
    t: pairing.qrToken,
  };
  return JSON.stringify(payload);
}
