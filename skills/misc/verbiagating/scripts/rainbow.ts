export type TierPin = { icon: string; phrase: string; verb: string; url: string };

export const DEFAULT_PIN: TierPin = {
  icon: '🌈⚡️',
  phrase: '10万ボルト',
  verb: '10万ボルトed',
  url: 'https://www.youtube.com/watch?v=5QzEoWeybp4',
};

// Closeout terminal color — the dusty magenta #c594a9 ≈ HSL(334°, 30%, 68%).
export const END_RGB: [number, number, number] = [197, 148, 169];
const END_HUE = 334, END_SAT = 0.3, END_LIGHT = 0.68;

// Active-wait "spin" band: INDIGO (270°) → MAGENTA (334°), ping-ponged so it
// cycles without a hard seam. Offset advances with elapsed → the band slides.
const SPIN_FROM_HUE = 270, SPIN_TO_HUE = END_HUE, SPIN_SPEED = 0.15;

const _seg = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
const graphemes = (text: string): string[] => [..._seg.segment(text)].map((s) => s.segment);

export function hslToRgb(h: number, s: number, l: number): [number, number, number] {
  const a = s * Math.min(l, 1 - l);
  const f = (n: number) => {
    const k = (n + h / 30) % 12;
    return Math.round((l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))) * 255);
  };
  return [f(0), f(8), f(4)];
}

// triangle wave, period 1, range [0,1] — ping-pong so the band has no seam.
const triangle = (x: number): number => {
  const u = x - Math.floor(x);
  return u < 0.5 ? u * 2 : 2 - u * 2;
};

// Colors each grapheme cluster (not code point) so an emoji + its variation
// selector stay one color unit; `colorAt(t, i, n) -> [r,g,b]`.
export function colorize(
  text: string,
  colorAt: (t: number, i: number, n: number) => [number, number, number],
): string {
  const g = graphemes(text);
  const n = g.length;
  return (
    g
      .map((ch, i) => {
        const t = n > 1 ? i / (n - 1) : 0;
        const [r, gr, b] = colorAt(t, i, n);
        return `\x1b[38;2;${r};${gr};${b}m${ch}`;
      })
      .join('') + '\x1b[0m'
  );
}

// Active wait: the INDIGO→MAGENTA band, cycling with elapsed (the "spin").
export function spin(text: string, elapsedSec = 0): string {
  const offset = elapsedSec * SPIN_SPEED;
  return colorize(text, (t) => {
    const u = triangle(t + offset);
    const hue = SPIN_FROM_HUE + u * (SPIN_TO_HUE - SPIN_FROM_HUE);
    return hslToRgb(hue, 0.7, 0.58);
  });
}

// Closeout: the full red→magenta rainbow, frozen, landing exactly on #c594a9.
export function done(text: string): string {
  return colorize(text, (t, i, n) => {
    if (i === n - 1) return END_RGB; // exact terminal color
    const hue = t * END_HUE; // 0 (red) → 334, through the spectrum
    const sat = 1 + t * (END_SAT - 1); // 1.0 → 0.30
    const light = 0.5 + t * (END_LIGHT - 0.5); // 0.5 → 0.68
    return hslToRgb(hue, sat, light);
  });
}

export function fmtDuration(ms: number): string {
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

if (require.main === module) {
  const [mode, a2, a3, a4] = process.argv.slice(2);
  if (mode === 'spin') {
    process.stdout.write(spin(a3 ?? '', parseInt(a2 ?? '0', 10)) + '\n');
  } else if (mode === 'done') {
    const dur = fmtDuration(parseInt(a2 ?? '0', 10) * 1000);
    if (a3) {
      process.stdout.write(`${done(`${a3} for ${dur}`)}\t${a4 ?? ''}\n`);
    } else {
      process.stdout.write(`${done(`${DEFAULT_PIN.icon} ${DEFAULT_PIN.verb} for ${dur}`)}\t${DEFAULT_PIN.url}\n`);
    }
  }
}
