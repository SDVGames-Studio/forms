#!/usr/bin/env node
'use strict';
// Procedural SFX generator for Forms (godot-sound-work skill, 2026-11-11).
//
// Deterministic: seeded PRNG, no dependencies, no network — identical
// bytes on every run. License-free (generated, not sampled).
//
// Recipes:
//   shot      noise burst with a 10 ms attack and ~55 ms exponential
//             decay body under a lowpass sweep (5.5 kHz -> 350 Hz toward
//             the tail) + a pitch-down thump (sine ~170 Hz -> 55 Hz over
//             ~130 ms) for weight. ~0.35 s total.
//   explosion filtered noise with a 6 ms attack and ~0.45 s exponential
//             decay under a closing lowpass (700 Hz -> 90 Hz), a sub-bass
//             rumble (~48 Hz with a slow frequency wobble) and a shallow
//             ~5.5 Hz amplitude wobble for texture. ~1.2 s total.
//
// Output: 16-bit PCM mono 44.1 kHz WAV files under assets/audio/.

const fs = require('node:fs');
const path = require('node:path');

const SR = 44100;
const OUT = {
	shot: 'assets/audio/weapons/shot.wav',
	explosion: 'assets/audio/explosions/explosion.wav',
};

// mulberry32 — tiny deterministic PRNG (fixed seeds per sound).
function prng(seed) {
	let a = seed >>> 0;
	return function () {
		a |= 0;
		a = (a + 0x6d2b79f5) | 0;
		let t = Math.imul(a ^ (a >>> 15), 1 | a);
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

function writeWav(file, samples) {
	const n = samples.length;
	const buf = Buffer.alloc(44 + n * 2);
	buf.write('RIFF', 0);
	buf.writeUInt32LE(36 + n * 2, 4);
	buf.write('WAVE', 8);
	buf.write('fmt ', 12);
	buf.writeUInt32LE(16, 16); // PCM chunk size
	buf.writeUInt16LE(1, 20); // PCM
	buf.writeUInt16LE(1, 22); // mono
	buf.writeUInt32LE(SR, 24);
	buf.writeUInt32LE(SR * 2, 28); // byte rate
	buf.writeUInt16LE(2, 32); // block align
	buf.writeUInt16LE(16, 34); // bits per sample
	buf.write('data', 36);
	buf.writeUInt32LE(n * 2, 40);
	for (let i = 0; i < n; i++) {
		const v = Math.max(-1, Math.min(1, samples[i]));
		buf.writeInt16LE(Math.round(v * 32767), 44 + i * 2);
	}
	fs.mkdirSync(path.dirname(file), { recursive: true });
	fs.writeFileSync(file, buf);
	console.log(`wrote ${file} (${(n / SR).toFixed(3)} s, ${n} samples)`);
}

// One-pole lowpass coefficient for a cutoff in Hz.
function lpCoef(cutoffHz) {
	const c = (2.0 * Math.PI * cutoffHz) / SR;
	return c / (c + 1.0);
}

function normalize(samples, peakTarget) {
	let peak = 0;
	for (const v of samples) peak = Math.max(peak, Math.abs(v));
	const gain = peakTarget / peak;
	for (let i = 0; i < samples.length; i++) samples[i] *= gain;
	return samples;
}

function makeShot() {
	const n = Math.floor(0.35 * SR);
	const rnd = prng(0x51f1ed); // fixed seed -> deterministic asset
	const out = new Float64Array(n);
	let lp = 0.0;
	let thumpPhase = 0.0;
	for (let i = 0; i < n; i++) {
		const t = i / SR;
		// Envelope: 10 ms attack, ~55 ms exponential body, silent tail.
		const env = Math.min(1.0, t / 0.010) * Math.exp(-t / 0.055);
		// Lowpass sweep 5.5 kHz -> 350 Hz toward the tail.
		const cutoff = 350 + 5150 * Math.exp(-t / 0.045);
		lp += (rnd() * 2 - 1 - lp) * lpCoef(cutoff);
		// Pitch-down thump: 170 Hz -> 55 Hz over ~130 ms (phase-integrated
		// so the sweep stays continuous), slightly longer body than the noise.
		const sweep = Math.min(1.0, t / 0.130);
		const thumpF = 170 * Math.pow(55 / 170, sweep);
		thumpPhase += thumpF / SR;
		const thump =
			Math.sin(2 * Math.PI * thumpPhase) * Math.exp(-t / 0.085) * 0.9;
		out[i] = lp * env * 0.85 + thump;
	}
	return normalize(out, 0.88);
}

function makeExplosion() {
	const n = Math.floor(1.2 * SR);
	const rnd = prng(0x600d); // fixed seed -> deterministic asset
	const out = new Float64Array(n);
	let lp = 0.0;
	let rumblePhase = 0.0;
	for (let i = 0; i < n; i++) {
		const t = i / SR;
		// 6 ms attack then ~0.45 s exponential decay.
		const env = Math.min(1.0, t / 0.006) * Math.exp(-t / 0.45);
		// Closing lowpass 700 Hz -> 90 Hz.
		const cutoff = 90 + 610 * Math.exp(-t / 0.30);
		lp += (rnd() * 2 - 1 - lp) * lpCoef(cutoff);
		// Sub-bass rumble: ~48 Hz with a slow +-3.5 Hz wobble (~2.3 Hz),
		// longer body than the noise (0.60 s tau), phase-integrated.
		const rumbleF = 48 + 3.5 * Math.sin(2 * Math.PI * 2.3 * t);
		rumblePhase += rumbleF / SR;
		const rumble =
			Math.sin(2 * Math.PI * rumblePhase) * Math.exp(-t / 0.60);
		// Shallow ~5.5 Hz amplitude wobble for texture.
		const wobble = 0.86 + 0.14 * Math.sin(2 * Math.PI * 5.5 * t);
		out[i] = (lp * 0.8 + rumble * 0.75) * env * wobble;
	}
	return normalize(out, 0.95);
}

writeWav(OUT.shot, makeShot());
writeWav(OUT.explosion, makeExplosion());
