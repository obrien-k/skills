export type TierPin = { icon: string; phrase: string; verb: string; url: string };

export const DEFAULT_PIN: TierPin = {
  icon: '🌈⚡️',
  phrase: '10万ボルト',
  verb: '10万ボルトed',
  url: 'https://www.youtube.com/watch?v=5QzEoWeybp4',
};

export function hslToRgb(h: number, s: number, l: number): [number, number, number] {
  const a = s * Math.min(l, 1 - l);
  const f = (n: number) => {
    const k = (n + h / 30) % 12;
    return Math.round((l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))) * 255);
  };
  return [f(0), f(8), f(4)];
}

const _seg = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

// Sweeps hue from 0° (red) to 320° (hot pink/magenta) — not a full 360 loop.
// Iterates by grapheme cluster (not code point) so an emoji and its variation
// selector (e.g. ⚡ + U+FE0F) stay one color unit — splitting them with an escape
// breaks emoji presentation in the terminal.
export function rainbow(text: string, offset = 0): string {
  const chars = [..._seg.segment(text)].map((s) => s.segment);
  const out = chars.map((ch, i) => {
    const hue = (offset + (i / Math.max(chars.length - 1, 1)) * 320) % 360;
    const [r, g, b] = hslToRgb(hue, 1, 0.5);
    return `\x1b[38;2;${r};${g};${b}m${ch}`;
  });
  return out.join('') + '\x1b[0m';
}

function fmtDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const parts: string[] = [];
  if (h) parts.push(`${h}h`);
  if (m) parts.push(`${m}m`);
  parts.push(`${sec}s`);
  return parts.join(' ');
}

// Leads with the pin's iconography, then the verbed phrase + duration — the
// whole run rainbowed. The link rides alongside (emitted by the CLI as a second
// TSV field), so the closeout can fuse iconography + link + text via render_strip.
export function verbiagateDoneLabel(pin: TierPin = DEFAULT_PIN, durationMs: number): string {
  return rainbow(`${pin.icon} ${pin.verb} for ${fmtDuration(durationMs)}`);
}

if (require.main === module) {
  const elapsedSec = parseInt(process.argv[2] ?? '0', 10);
  const verb = process.argv[3];
  const pin = verb ? { ...DEFAULT_PIN, verb } : DEFAULT_PIN;
  // "<label>\t<url>" — same contract as the phrase-pin file, so statusline.sh
  // can split and hand both halves to render_strip.
  process.stdout.write(`${verbiagateDoneLabel(pin, elapsedSec * 1000)}\t${pin.url}\n`);
}
