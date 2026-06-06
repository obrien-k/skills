'use strict';

// Run with: node --test scripts/rainbow.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const { rainbow, fmtDuration, verbiagateDoneLabel, DEFAULT_PIN } = require('./rainbow.js');

const ESC = /\x1b\[[0-9;]*m/g;
const strip = (s) => s.replace(ESC, '');

test('rainbow() still wraps each char in truecolor and resets at the end', () => {
  const out = rainbow('hi');
  assert.match(out, /\x1b\[38;2;\d+;\d+;\d+m/); // at least one truecolor open
  assert.ok(out.endsWith('\x1b[0m'), 'resets color at the end');
  assert.equal(strip(out), 'hi');
});

test('fmtDuration formats m + s past a minute', () => {
  assert.equal(fmtDuration(184000), '3m 4s');
  assert.equal(fmtDuration(4000), '4s');
});

test('DEFAULT_PIN carries iconography + verb + a link', () => {
  assert.equal(DEFAULT_PIN.icon, '⚡️');
  assert.equal(DEFAULT_PIN.verb, '10万ボルトed');
  assert.equal(typeof DEFAULT_PIN.url, 'string');
  assert.match(DEFAULT_PIN.url, /^https?:\/\//);
});

test('verbiagateDoneLabel leads with the icon, then the verbed text', () => {
  const label = strip(verbiagateDoneLabel(DEFAULT_PIN, 184000));
  assert.equal(label, '⚡️ 10万ボルトed for 3m 4s');
});

test('verbiagateDoneLabel is rainbowed (carries color escapes)', () => {
  const out = verbiagateDoneLabel(DEFAULT_PIN, 184000);
  assert.match(out, /\x1b\[38;2;/);
});

test('CLI emits "<label>\\t<url>" so the closeout can render iconography+link+text', () => {
  const script = path.join(__dirname, 'rainbow.js');
  const out = execFileSync('node', [script, '184'], { encoding: 'utf8' }).replace(/\n$/, '');
  const [label, url] = out.split('\t');
  assert.equal(url, DEFAULT_PIN.url, 'second field is the link');
  assert.equal(strip(label), '⚡️ 10万ボルトed for 3m 4s', 'first field is the icon+verbed text');
});
