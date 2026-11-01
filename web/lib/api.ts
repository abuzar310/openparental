import { apiBaseUrl } from './config';

export type AuthUser = {
  userId: string;
  email: string;
  familyId: string;
};

export type Device = {
  id: string;
  name: string;
  status: string;
  batteryPct?: number | null;
  model?: string | null;
  lastSeenAt?: string | null;
};

export type Alert = {
  id: string;
  type: string;
  title: string;
  body: string;
  createdAt?: string;
  readAt?: string | null;
  read?: boolean;
};

export type DeviceLocation = {
  lat: number;
  lng: number;
  accuracyM?: number | null;
  occurredAt?: string | null;
};

export type Pairing = {
  id: string;
  code: string;
  qrToken: string;
  status: string;
};

const TOKEN_KEY = 'op_access';
const REFRESH_KEY = 'op_refresh';

function storage(): Storage | null {
  if (typeof window === 'undefined') return null;
  return window.localStorage;
}

export function getAccessToken(): string | null {
  return storage()?.getItem(TOKEN_KEY) ?? null;
}

export function clearSession(): void {
  storage()?.removeItem(TOKEN_KEY);
  storage()?.removeItem(REFRESH_KEY);
}

async function persistAuth(data: {
  accessToken: string;
  refreshToken: string;
}): Promise<void> {
  storage()?.setItem(TOKEN_KEY, data.accessToken);
  storage()?.setItem(REFRESH_KEY, data.refreshToken);
}

async function refreshTokens(): Promise<boolean> {
  const refresh = storage()?.getItem(REFRESH_KEY);
  if (!refresh) return false;
  const res = await fetch(`${apiBaseUrl}/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refreshToken: refresh }),
  });
  if (!res.ok) return false;
  const json = (await res.json()) as {
    accessToken: string;
    refreshToken: string;
  };
  await persistAuth(json);
  return true;
}

async function apiFetch<T>(
  path: string,
  init: RequestInit = {},
  retry = true,
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set('Content-Type', 'application/json');
  const token = getAccessToken();
  if (token) headers.set('Authorization', `Bearer ${token}`);

  const res = await fetch(`${apiBaseUrl}${path}`, { ...init, headers });
  if (res.status === 401 && retry) {
    const ok = await refreshTokens();
    if (ok) return apiFetch(path, init, false);
    clearSession();
    throw new Error('Session expired');
  }
  if (!res.ok) {
    let message = res.statusText;
    try {
      const err = (await res.json()) as { message?: string | string[] };
      if (err.message) {
        message = Array.isArray(err.message)
          ? err.message.join(', ')
          : err.message;
      }
    } catch {
      /* ignore */
    }
    throw new Error(message);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

async function authRequest(
  path: string,
  body: Record<string, unknown>,
): Promise<AuthUser> {
  const res = await fetch(`${apiBaseUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    let message = res.statusText;
    try {
      const err = (await res.json()) as { message?: string | string[] };
      if (err.message) {
        message = Array.isArray(err.message)
          ? err.message.join(', ')
          : err.message;
      }
    } catch {
      /* ignore */
    }
    throw new Error(message);
  }
  const json = (await res.json()) as {
    accessToken: string;
    refreshToken: string;
    user: { id: string; email: string; familyId: string };
  };
  await persistAuth({
    accessToken: json.accessToken,
    refreshToken: json.refreshToken,
  });
  return {
    userId: json.user.id,
    email: json.user.email,
    familyId: json.user.familyId,
  };
}

export async function login(email: string, password: string): Promise<AuthUser> {
  return authRequest('/auth/login', { email, password });
}

export async function register(
  email: string,
  password: string,
  familyName?: string,
): Promise<AuthUser> {
  return authRequest('/auth/register', {
    email,
    password,
    ...(familyName ? { familyName } : {}),
  });
}

export async function logout(): Promise<void> {
  try {
    await apiFetch('/auth/logout', { method: 'POST' });
  } catch {
    /* best effort */
  }
  clearSession();
}

export function listDevices(): Promise<Device[]> {
  return apiFetch<Device[]>('/devices');
}

export function listAlerts(): Promise<Alert[]> {
  return apiFetch<Alert[]>('/alerts');
}

export function markAlertRead(id: string): Promise<void> {
  return apiFetch(`/alerts/${id}/read`, { method: 'POST' });
}

export function createPairing(): Promise<Pairing> {
  return apiFetch<Pairing>('/pairings', {
    method: 'POST',
    body: JSON.stringify({}),
  });
}

export function sendCommand(
  deviceId: string,
  type: string,
  payload?: Record<string, unknown>,
): Promise<void> {
  return apiFetch(`/devices/${deviceId}/commands`, {
    method: 'POST',
    body: JSON.stringify({ type, ...(payload ? { payload } : {}) }),
  });
}

export function latestLocation(deviceId: string): Promise<DeviceLocation | null> {
  return apiFetch<DeviceLocation | null>(
    `/devices/${deviceId}/locations/latest`,
  ).catch(() => null);
}

export function locationHistory(
  deviceId: string,
  limit = 100,
): Promise<DeviceLocation[]> {
  return apiFetch<DeviceLocation[]>(
    `/devices/${deviceId}/locations?limit=${limit}`,
  ).catch(() => []);
}

// ---- geofences ----

export type Geofence = {
  id: string;
  name: string;
  lat: number;
  lng: number;
  radiusM: number;
  active?: boolean;
};

export function listGeofences(deviceId: string): Promise<Geofence[]> {
  return apiFetch<Geofence[]>(`/devices/${deviceId}/geofences`).catch(() => []);
}

export function createGeofence(
  deviceId: string,
  g: { name: string; lat: number; lng: number; radiusM?: number },
): Promise<Geofence> {
  return apiFetch<Geofence>(`/devices/${deviceId}/geofences`, {
    method: 'POST',
    body: JSON.stringify(g),
  });
}

export function deleteGeofence(
  deviceId: string,
  geofenceId: string,
): Promise<void> {
  return apiFetch(`/devices/${deviceId}/geofences/${geofenceId}`, {
    method: 'DELETE',
  });
}

// ---- AI usage report ----

export function aiReport(deviceId: string): Promise<{ report: string }> {
  return apiFetch<{ report: string }>(`/devices/${deviceId}/ai-report`, {
    method: 'POST',
    body: JSON.stringify({}),
  });
}

// ---- policy / rules (family-wide; pushed to every device) ----

export type PolicyRules = {
  blockedApps?: string[];
  allowedApps?: string[];
  appLimits?: { pkg: string; dailyMinutes: number }[];
  schedules?: { start: string; end: string; blockAll?: boolean }[];
  blockedDomains?: string[];
  blockAllExceptAllowed?: boolean;
  blockNewApps?: boolean;
  customKeywords?: string[];
  /** Periodic screen capture on child (minutes). 0 = off. Min 15 on device. */
  snapshotIntervalMinutes?: number;
};

export async function getPolicy(): Promise<PolicyRules> {
  const res = await apiFetch<{ rules?: PolicyRules } | null>('/policies').catch(
    () => null,
  );
  return res?.rules ?? {};
}

export function updatePolicy(rules: PolicyRules): Promise<void> {
  return apiFetch('/policies', {
    method: 'PUT',
    body: JSON.stringify({ rules }),
  });
}

// ---- screen (screenshot = one frame; mirror = continuous) ----

export type ScreenSession = {
  id: string;
  status: string;
};

export function createScreenSession(
  deviceId: string,
  mode: 'mirror' | 'screenshot' = 'mirror',
): Promise<ScreenSession> {
  return apiFetch<ScreenSession>(`/devices/${deviceId}/screen-sessions`, {
    method: 'POST',
    body: JSON.stringify({ mode }),
  });
}

export function requestScreenshot(deviceId: string): Promise<ScreenSession> {
  return createScreenSession(deviceId, 'screenshot');
}

export type ScreenFrame = {
  data: string | null;
  ts: number | null;
  status: string;
};

export function getScreenFrame(sessionId: string): Promise<ScreenFrame> {
  return apiFetch<ScreenFrame>(`/screen-sessions/${sessionId}/frame`);
}

/** Lift Device Owner self-protection so the app can be uninstalled again. */
export function releaseDeviceOwner(deviceId: string): Promise<void> {
  return sendCommand(deviceId, 'RELEASE_OWNER');
}

// ---- activity timeline (app opens, usage, installs, notifications, history) ----

export type EventLog = {
  id: string;
  type: string;
  data: Record<string, unknown>;
  occurredAt: string;
};

export type ContentItem = {
  id: string;
  source: string;
  body: string;
  matched?: string | null;
  counterparty?: string | null;
  occurredAt: string;
};

export function getEvents(deviceId: string, limit = 200): Promise<EventLog[]> {
  return apiFetch<EventLog[]>(
    `/devices/${deviceId}/events?limit=${limit}`,
  ).catch(() => []);
}

export function getContent(
  deviceId: string,
  source?: string,
): Promise<ContentItem[]> {
  const q = source ? `?source=${encodeURIComponent(source)}` : '';
  return apiFetch<ContentItem[]>(`/devices/${deviceId}/content${q}`).catch(
    () => [],
  );
}

export type InstalledApp = {
  pkg: string;
  label: string;
  system?: boolean;
  launchable?: boolean;
  iconB64?: string;
};

export type PhotoFlag = {
  id: string;
  category: string;
  confidence: number;
  occurredAt: string;
};

export function getPhotoFlags(deviceId: string): Promise<PhotoFlag[]> {
  return apiFetch<PhotoFlag[]>(`/devices/${deviceId}/photo-flags`).catch(() => []);
}

/**
 * The child's installed-app list, read from the latest APP_INVENTORY event the
 * device reported. Returns [] until the device has reported one.
 */
export async function getInstalledApps(
  deviceId: string,
): Promise<InstalledApp[]> {
  const events = await getEvents(deviceId, 300);
  const inv = events.find((e) => e.type === 'APP_INVENTORY');
  const apps = (inv?.data?.apps as InstalledApp[] | undefined) ?? [];
  return apps;
}
