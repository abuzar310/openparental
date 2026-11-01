/** Copy for /setup — kept in one place for the guide page and anchors. */

export type SetupStep = {
  id: string;
  title: string;
  summary: string;
  body: string[];
  tips?: string[];
};

export const setupOverview = {
  title: 'Set up OpenParental in one sitting',
  subtitle:
    'Child app on their Android phone. You manage from the parent Android app or the web dashboard (perfect on iPhone). Everything talks to your private cloud — no home server.',
  time: 'About 15–20 minutes the first time',
  youNeed: [
    'An Android phone for your child (managed device)',
    'Your phone: Android (parent app) or iPhone (Safari dashboard)',
    'Wi‑Fi on both devices during pairing',
    'Permission to sideload the child APK (Android “Install unknown apps”)',
  ],
};

export const setupSteps: SetupStep[] = [
  {
    id: 'account',
    title: '1. Create your parent account',
    summary: 'Register once on the web — same login works in the Android parent app.',
    body: [
      'On your phone or computer, open the Parent dashboard and choose Register.',
      'Use an email and password you will remember. This creates your family in the cloud.',
      'After sign-in you land on Devices. You will pair the child phone from here or from Pair in the menu.',
    ],
    tips: [
      'On iPhone: open the site in Safari, sign in, then Share → Add to Home Screen for an app-like icon.',
    ],
  },
  {
    id: 'download',
    title: '2. Install the apps (from this website)',
    summary: 'Download APKs here — we do not send you to GitHub.',
    body: [
      'On the child’s phone: open our Download page in Chrome and install the Child APK.',
      'On your Android phone (optional): install the Parent APK from the same page.',
      'If a download is not ready yet, the page will tell you — check back after the next release build is published to this site.',
    ],
    tips: [
      'Android may ask you to allow installs from Chrome or Files — that is normal for private APKs.',
    ],
  },
  {
    id: 'pair',
    title: '3. Pair the child device',
    summary: 'A short code links the kid phone to your family.',
    body: [
      'In the parent app or web dashboard, open Pair and tap Create pairing code.',
      'You will see a QR code and a short code like ABCD-EFGH — keep this screen open.',
      'On the child phone, open OpenParental, tap Scan QR code, or enter the server URL and code manually.',
      'When pairing succeeds, the child app shows Protected & online and the device appears in your Device list.',
    ],
  },
  {
    id: 'permissions',
    title: '4. Finish the child permission wizard',
    summary: 'OpenParental needs the same kinds of access as other family safety apps.',
    body: [
      'The child app walks through: notifications, battery optimization off, accessibility (for app limits), usage access, device admin (remote lock), location, and optional hide-from-launcher.',
      'Grant each step when prompted. Skipping steps limits features (e.g. no lock without device admin).',
      'On Xiaomi / Oppo / Vivo, also allow autostart in the manufacturer security app.',
    ],
  },
  {
    id: 'daily',
    title: '5. Daily use — what you will see',
    summary: 'Parent: Notice · Device · Me. Child: calm status + protection running quietly.',
    body: [
      'Notice — alerts, unblock requests, and important events from the child device.',
      'Device — pick a child phone, then location, lock, screen tools, policies, and quick commands.',
      'Me — server URL (already set to this site), account, and sign out.',
      'Web dashboard mirrors the same backend: devices, alerts, pairing, and commands from any browser.',
    ],
  },
  {
    id: 'troubleshoot',
    title: '6. If something fails',
    summary: 'Most issues are network URL or permissions.',
    body: [
      'Child or parent app can’t sign in: set Server URL to your site origin only (https://openparental.vercel.app) — no /api suffix.',
      'Device offline: open the child app once on Wi‑Fi; check battery optimization is off for OpenParental.',
      'Pairing expired: codes last 15 minutes — create a new pairing from the parent side.',
      'Health check: visit /health on this site — you should see ok: true and db: true.',
    ],
  },
];

export const featureHighlights = [
  {
    title: 'Live device status',
    description: 'Online, battery, and last seen — know the phone is reachable before you lock or locate.',
    icon: '📡',
  },
  {
    title: 'Remote lock & commands',
    description: 'Send lock, policy updates, and other commands over your private API — built for real parents, not demos.',
    icon: '🔒',
  },
  {
    title: 'Location & geofences',
    description: 'Last known location on the map; geofence alerts when your build enables them on device.',
    icon: '📍',
  },
  {
    title: 'Notice feed',
    description: 'FlashGet-style Notice tab — unblock requests and alerts in one chronological feed.',
    icon: '🔔',
  },
  {
    title: 'Tamper & supervision',
    description: 'Child app runs a foreground supervisor, resists casual uninstall, and supports hide-from-launcher for older kids.',
    icon: '🛡️',
  },
  {
    title: 'iPhone-friendly parent',
    description: 'No App Store required for your test — full dashboard in Safari with the same account as Android parent.',
    icon: '📱',
  },
];
