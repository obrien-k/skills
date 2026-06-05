// Renders the rainbow closeout label in a real xterm.js terminal and screenshots it.
// Usage: node screenshot.mjs [elapsed_seconds] [verb]
// Outputs: preview.png in this directory
import { execSync } from 'node:child_process';
import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const dir = dirname(fileURLToPath(import.meta.url));
const rainbowScript = resolve(dir, '../rainbow.js');

const elapsedSec = process.argv[2] ?? '90';
const verb = process.argv[3];
const cmdArgs = verb ? `${elapsedSec} ${JSON.stringify(verb)}` : elapsedSec;
const ansi = execSync(`node ${JSON.stringify(rainbowScript)} ${cmdArgs}`).toString().trimEnd();

const browser = await chromium.launch();
const page = await browser.newPage();
await page.setViewportSize({ width: 780, height: 120 });

await page.setContent(`<!DOCTYPE html><html>
<head>
  <link rel="stylesheet" href="https://unpkg.com/@xterm/xterm/css/xterm.css"/>
  <style>
    body { margin: 16px; background: #1a1a1a; }
    .xterm-viewport { border-radius: 6px; overflow: hidden; }
  </style>
</head>
<body><div id="t"></div></body></html>`);

await page.addScriptTag({ url: 'https://unpkg.com/@xterm/xterm/lib/xterm.js' });

await page.evaluate((text) => {
  const term = new Terminal({
    cols: 72,
    rows: 2,
    theme: {
      background: '#1a1a1a',
      foreground: '#f0f0f0',
      cursor: '#f0f0f0',
    },
    fontFamily: '"Cascadia Code", "Fira Code", "JetBrains Mono", monospace',
    fontSize: 15,
    lineHeight: 1.4,
    cursorBlink: false,
  });
  term.open(document.getElementById('t'));
  term.write(text);
}, ansi);

await page.waitForTimeout(400);

const out = join(dir, 'preview.png');
await page.locator('#t').screenshot({ path: out });
await browser.close();
console.log(out);
