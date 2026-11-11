#!/usr/bin/env node
'use strict';
// Procedural background-music generator for Forms (issue #463,
// godot-sound-work skill). One endless loop per playable level.
//
// Deterministic: seeded PRNG, no dependencies, no network — identical
// bytes on every run. License-free (generated, not sampled).
//
// Output: 16-bit PCM mono 44.1 kHz WAV files under assets/audio/music/,
// one per playable level (5 levels + 2 duel maps). Every track is a
// seamless ENDLESS loop: each arrangement is bar-synchronous and the
// rendered tail is crossfaded into the head (see loopify), so wrapping
// the loop point is click-free; the Godot import pins loop_mode=forward
// so playback loops forever without retriggering.
//
// Moods (distinct key/tempo/texture per level):
//   level1    "meadow"   80 BPM  C major pentatonic — gentle plucks, pad
//   level2    "cliff"   104 BPM  D minor — bouncy bass, light ticks
//   level3    "cavern"  120 BPM  E minor — driving 8th-note bass pulse
//   level4    "depths"   66 BPM  F# minor — dark pad drone, deep swells
//   level5    "summit"  144 BPM  A minor — energetic arp + drums
//   duel      "faceoff"  96 BPM  G minor — martial ticks, low unison riff
//   duel_big  "war"     108 BPM  B minor — heavier drums, wider riff

const fs = require('node:fs');
const path = require('node:path');

const SR = 44100;
const OUT = {
	level1: 'assets/audio/music/level1.wav',
	level2: 'assets/audio/music/level2.wav',
	level3: 'assets/audio/music/level3.wav',
	level4: 'assets/audio/music/level4.wav',
	level5: 'assets/audio/music/level5.wav',
	duel: 'assets/audio/music/duel.wav',
	duel_big: 'assets/audio/music/duel_big.wav',
};
const XFADE = 1.2; // s of tail crossfaded into the head (seamless wrap)

// mulberry32 — tiny deterministic PRNG (fixed seed per track).
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

function normalize(samples, peakTarget) {
	let peak = 0;
	for (const v of samples) peak = Math.max(peak, Math.abs(v));
	const gain = peakTarget / peak;
	for (let i = 0; i < samples.length; i++) samples[i] *= gain;
	return samples;
}

// Crossfade the rendered tail into the head so wrapping the loop point
// is seamless: out[i] = raw[i] for i >= F, and for the first F samples
// the head fades in while the overshoot raw[L..L+F) fades out over it.
function loopify(raw, loopLen, fade) {
	const out = new Float64Array(loopLen);
	for (let i = 0; i < loopLen; i++) {
		if (i < fade) {
			const w = i / fade;
			out[i] = raw[i] * w + raw[loopLen + i] * (1 - w);
		} else {
			out[i] = raw[i];
		}
	}
	return out;
}

// --- Shared voices ---------------------------------------------------------

// Plucked tone: fundamental + soft harmonics, exponential decay,
// slight detune for warmth.
function pluck(buf, start, freq, dur, vel, rnd) {
	const n = Math.floor(dur * SR);
	const detune = 1 + (rnd() - 0.5) * 0.004;
	let phase = 0;
	for (let i = 0; i < n; i++) {
		const idx = start + i;
		if (idx >= buf.length) break;
		const t = i / SR;
		phase += (freq * detune) / SR;
		const env = Math.min(1, t / 0.008) * Math.exp(-t / (dur * 0.38));
		const s =
			Math.sin(2 * Math.PI * phase) * 0.72 +
			Math.sin(4 * Math.PI * phase) * 0.18 +
			Math.sin(6 * Math.PI * phase) * 0.07;
		buf[idx] += s * env * vel;
	}
}

// Pad chord: detuned sines with a slow swell (bar-aligned), soft top.
function pad(buf, start, dur, freqs, vel) {
	const n = Math.floor(dur * SR);
	const phases = freqs.map(() => 0);
	const dets = freqs.map((f, k) => f * (1 + (k % 2 === 0 ? 0.003 : -0.003)));
	for (let i = 0; i < n; i++) {
		const idx = start + i;
		if (idx >= buf.length) break;
		const t = i / SR;
		// Slow swell: 0.8 s in, hold, 0.8 s out.
		const env =
			Math.min(1, t / 0.8) * Math.min(1, (dur - t) / 0.8) * vel;
		let s = 0;
		for (let k = 0; k < freqs.length; k++) {
			phases[k] += dets[k] / SR;
			s += Math.sin(2 * Math.PI * phases[k]);
		}
		buf[idx] += (s / freqs.length) * env;
	}
}

// Sustained drone: near-static tone with a very slow amplitude LFO.
function drone(buf, start, dur, freq, vel) {
	const n = Math.floor(dur * SR);
	let phase = 0;
	for (let i = 0; i < n; i++) {
		const idx = start + i;
		if (idx >= buf.length) break;
		const t = i / SR;
		phase += freq / SR;
		const lfo = 0.75 + 0.25 * Math.sin(2 * Math.PI * (1 / dur) * t);
		buf[idx] += Math.sin(2 * Math.PI * phase) * vel * lfo;
	}
}

// Kick: pitch-swept sine thump (150 -> 42 Hz), fast decay.
function kick(buf, start, vel) {
	const dur = 0.22;
	const n = Math.floor(dur * SR);
	let phase = 0;
	for (let i = 0; i < n; i++) {
		const idx = start + i;
		if (idx >= buf.length) break;
		const t = i / SR;
		const f = 42 + 108 * Math.exp(-t / 0.035);
		phase += f / SR;
		buf[idx] += Math.sin(2 * Math.PI * phase) * Math.exp(-t / 0.09) * vel;
	}
}

// Tick: short bright noise tap (hi-hat / snare-ish), highpassed by
// differencing white noise.
function tick(buf, start, vel, rnd, tone) {
	const dur = tone === 'snare' ? 0.09 : 0.045;
	const n = Math.floor(dur * SR);
	let prev = 0;
	for (let i = 0; i < n; i++) {
		const idx = start + i;
		if (idx >= buf.length) break;
		const t = i / SR;
		const w = rnd() * 2 - 1;
		const hp = w - prev; // crude 1st-order highpass
		prev = w;
		const env = Math.exp(-t / (dur * 0.35));
		buf[idx] += hp * env * vel * 0.5;
	}
}

// Musical helpers.
function note(rootSemi, semiOffset) {
	return rootSemi + semiOffset;
}
const A4 = 440;
function hz(midi) {
	return A4 * Math.pow(2, (midi - 69) / 12);
}
function beatSec(bpm) {
	return 60 / bpm;
}

// Shared track renderer: renders `bars` bars of 4/4 plus the XFADE
// overshoot, then loops + normalizes.
function render(bpm, bars, arrange) {
	const B = beatSec(bpm);
	const loopLen = Math.floor(bars * 4 * B * SR);
	const total = loopLen + Math.floor(XFADE * SR);
	const buf = new Float64Array(total);
	arrange(buf, B, loopLen);
	return normalize(loopify(buf, loopLen, Math.floor(XFADE * SR)), 0.9);
}

// --- Tracks ----------------------------------------------------------------

// level1 "meadow" — 80 BPM, C major pentatonic: gentle plucked arpeggio
// over slow pad swells; no drums.
function makeLevel1() {
	const rnd = prng(0x4631);
	const root = 48; // C3
	const scale = [0, 2, 4, 7, 9, 12, 14, 16]; // C major pent, 2 octaves
	return render(80, 6, (buf, B, loopLen) => {
		pad(buf, 0, loopLen + Math.floor(XFADE * SR),
			[hz(root), hz(root + 7), hz(root + 16)], 0.16);
		// 8th-note arpeggio, pattern wanders deterministically.
		const steps = 6 * 4 * 2;
		let deg = 0;
		for (let s = 0; s < steps; s++) {
			const t = Math.floor(s * (B / 2) * SR);
			deg += [1, 2, -1, 1, -2, 1, 2, -1][s % 8];
			deg = Math.max(0, Math.min(scale.length - 1, deg));
			const midi = note(root + 12, scale[deg]);
			pluck(buf, t, hz(midi), 0.9, 0.16, rnd);
			if (s % 4 === 0) {
				pluck(buf, t, hz(midi - 12), 1.4, 0.10, rnd); // soft bass
			}
		}
	});
}

// level2 "cliff" — 104 BPM, D minor: bouncy bass on 1/& of 3, arp 8ths,
// light ticks on the offbeats.
function makeLevel2() {
	const rnd = prng(0x4632);
	const root = 50; // D3
	return render(104, 8, (buf, B) => {
		for (let bar = 0; bar < 8; bar++) {
			const t0 = Math.floor(bar * 4 * B * SR);
			kick(buf, t0, 0.5);
			kick(buf, t0 + Math.floor(2.5 * B * SR), 0.32);
			tick(buf, t0 + Math.floor(B * SR), 0.35, rnd, 'hat');
			tick(buf, t0 + Math.floor(3 * B * SR), 0.35, rnd, 'hat');
			// Bass: root / fifth / root / minor seventh bounce.
			const bassLine = [0, 0, 7, 0, 0, 10, 7, 0];
			for (let e = 0; e < 8; e++) {
				const t = t0 + Math.floor(e * (B / 2) * SR);
				pluck(buf, t, hz(root - 12 + bassLine[e % 8]), 0.5, 0.2, rnd);
			}
			// Arp over the chord of the bar.
			const chords = [[0, 3, 7], [5, 8, 12], [3, 7, 10], [0, 4, 7]];
			const ch = chords[bar % 4];
			for (let e = 0; e < 8; e++) {
				if ((bar % 2 === 0 && e % 2 === 1) || (bar % 2 === 1 && e % 4 !== 0)) {
					continue; // sparser on odd bars
				}
				const t = t0 + Math.floor(e * (B / 2) * SR);
				const midi = note(root + 12, ch[e % ch.length] + (e >= 4 ? 12 : 0));
				pluck(buf, t, hz(midi), 0.7, 0.13, rnd);
			}
		}
	});
}

// level3 "cavern" — 120 BPM, E minor: driving 8th-note bass pulse, low
// drone, sparse dark arp, kick on 1 & 3.
function makeLevel3() {
	const rnd = prng(0x4633);
	const root = 40; // E2
	const minor = [0, 3, 7, 10, 12];
	return render(120, 8, (buf, B, loopLen) => {
		drone(buf, 0, loopLen + Math.floor(XFADE * SR), hz(root), 0.12);
		for (let bar = 0; bar < 8; bar++) {
			const t0 = Math.floor(bar * 4 * B * SR);
			kick(buf, t0, 0.55);
			kick(buf, t0 + Math.floor(2 * B * SR), 0.4);
			// Driving 8ths: root with occasional flat-six drop.
			const pat = bar % 4 === 3 ? [0, 0, 8, 0, 0, 7, 0, 0] : [0, 0, 0, 12, 0, 0, 7, 0];
			for (let e = 0; e < 8; e++) {
				const t = t0 + Math.floor(e * (B / 2) * SR);
				pluck(buf, t, hz(root + pat[e]), 0.45, 0.22, rnd);
			}
			// Sparse dark arp every other bar.
			if (bar % 2 === 0) {
				for (let e = 0; e < 4; e++) {
					const t = t0 + Math.floor(e * B * SR);
					pluck(buf, t, hz(root + 12 + minor[(e + bar) % minor.length]), 0.8, 0.11, rnd);
				}
			}
		}
	});
}

// level4 "depths" — 66 BPM, F# minor: dark two-note pad drone, deep sub
// swells, tolling low bell, minimal ticks.
function makeLevel4() {
	const rnd = prng(0x4634);
	const root = 42; // F#2
	return render(66, 5, (buf, B, loopLen) => {
		drone(buf, 0, loopLen + Math.floor(XFADE * SR), hz(root), 0.15);
		drone(buf, 0, loopLen + Math.floor(XFADE * SR), hz(root + 3), 0.1);
		for (let bar = 0; bar < 5; bar++) {
			const t0 = Math.floor(bar * 4 * B * SR);
			// Deep sub swell at each bar start.
			pad(buf, t0, 4 * B + 0.5, [hz(root - 12)], 0.22);
			// Tolling low bell: root or minor third, every half bar.
			const bell = bar % 2 === 0 ? root + 12 : root + 15;
			pluck(buf, t0 + Math.floor(2 * B * SR), hz(bell), 2.4, 0.14, rnd);
			if (bar % 2 === 1) {
				tick(buf, t0 + Math.floor(3.5 * B * SR), 0.18, rnd, 'hat');
			}
		}
	});
}

// level5 "summit" — 144 BPM, A minor: energetic — kick/hat groove,
// 16th-note arp, walking bass.
function makeLevel5() {
	const rnd = prng(0x4635);
	const root = 45; // A2
	const minor = [0, 3, 7, 10, 12, 15];
	return render(144, 12, (buf, B) => {
		for (let bar = 0; bar < 12; bar++) {
			const t0 = Math.floor(bar * 4 * B * SR);
			kick(buf, t0, 0.6);
			kick(buf, t0 + Math.floor(2 * B * SR), 0.45);
			if (bar % 2 === 1) kick(buf, t0 + Math.floor(3.75 * B * SR), 0.3);
			tick(buf, t0 + Math.floor(0.5 * B * SR), 0.3, rnd, 'hat');
			tick(buf, t0 + Math.floor(1.5 * B * SR), 0.3, rnd, 'hat');
			tick(buf, t0 + Math.floor(2.5 * B * SR), 0.3, rnd, 'hat');
			tick(buf, t0 + Math.floor(3.5 * B * SR), 0.3, rnd, 'hat');
			// Walking bass, 8ths.
			const bass = [0, 0, 3, 0, 7, 0, 3, 10][bar % 8];
			for (let e = 0; e < 8; e++) {
				const t = t0 + Math.floor(e * (B / 2) * SR);
				pluck(buf, t, hz(root + (e % 4 === 3 ? bass + 12 : bass)), 0.4, 0.2, rnd);
			}
			// 16th arp climbing the scale.
			for (let e = 0; e < 16; e++) {
				const t = t0 + Math.floor(e * (B / 4) * SR);
				if (e % 2 === 1 && bar % 4 !== 3) continue;
				const midi = note(root + 24, minor[(e + bar * 2) % minor.length]);
				pluck(buf, t, hz(midi), 0.35, 0.12, rnd);
			}
		}
	});
}

// duel "faceoff" — 96 BPM, G minor: martial snare-ish ticks, low unison
// riff answered by a sparse high motif.
function makeDuel() {
	const rnd = prng(0x4636);
	const root = 43; // G2
	return render(96, 8, (buf, B) => {
		for (let bar = 0; bar < 8; bar++) {
			const t0 = Math.floor(bar * 4 * B * SR);
			kick(buf, t0, 0.55);
			kick(buf, t0 + Math.floor(2 * B * SR), 0.4);
			// Martial snare pattern.
			for (const off of [1, 2, 3, 3.5]) {
				tick(buf, t0 + Math.floor(off * B * SR), off === 2 ? 0.4 : 0.25, rnd, 'snare');
			}
			// Low unison riff: G - Bb - F - G.
			const riff = [0, 3, -2, 0];
			for (let e = 0; e < 4; e++) {
				const t = t0 + Math.floor(e * B * SR);
				pluck(buf, t, hz(root + riff[e]), 0.8, 0.22, rnd);
				pluck(buf, t, hz(root + 12 + riff[e]), 0.8, 0.12, rnd);
			}
			// Sparse high answer every 4th bar.
			if (bar % 4 === 3) {
				for (let e = 0; e < 3; e++) {
					const t = t0 + Math.floor((2 + e * 0.5) * B * SR);
					pluck(buf, t, hz(root + 24 + [0, 3, 7][e]), 0.5, 0.12, rnd);
				}
			}
		}
	});
}

// duel_big "war" — 108 BPM, B minor: heavier — double kick drive, wider
// riff (root + fifth + octave), rolling hats.
function makeDuelBig() {
	const rnd = prng(0x4637);
	const root = 47; // B2
	return render(108, 9, (buf, B) => {
		for (let bar = 0; bar < 9; bar++) {
			const t0 = Math.floor(bar * 4 * B * SR);
			kick(buf, t0, 0.6);
			kick(buf, t0 + Math.floor(1.75 * B * SR), 0.35);
			kick(buf, t0 + Math.floor(2 * B * SR), 0.5);
			kick(buf, t0 + Math.floor(3.5 * B * SR), 0.35);
			for (const off of [1, 2.5, 3, 3.5]) {
				tick(buf, t0 + Math.floor(off * B * SR), 0.3, rnd, 'snare');
			}
			tick(buf, t0 + Math.floor(0.5 * B * SR), 0.22, rnd, 'hat');
			tick(buf, t0 + Math.floor(1.5 * B * SR), 0.22, rnd, 'hat');
			tick(buf, t0 + Math.floor(2.5 * B * SR), 0.22, rnd, 'hat');
			// Wider riff: root/fifth/octave rotates across bars.
			const riff = [0, 7, 12, 10, 7, 3, 0, 7];
			for (let e = 0; e < 8; e++) {
				const t = t0 + Math.floor(e * (B / 2) * SR);
				const semi = riff[(e + bar) % riff.length];
				pluck(buf, t, hz(root + semi), 0.6, 0.2, rnd);
				if (e % 2 === 0) pluck(buf, t, hz(root + 12 + semi), 0.6, 0.1, rnd);
			}
		}
	});
}

writeWav(OUT.level1, makeLevel1());
writeWav(OUT.level2, makeLevel2());
writeWav(OUT.level3, makeLevel3());
writeWav(OUT.level4, makeLevel4());
writeWav(OUT.level5, makeLevel5());
writeWav(OUT.duel, makeDuel());
writeWav(OUT.duel_big, makeDuelBig());
