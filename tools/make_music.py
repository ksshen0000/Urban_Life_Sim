#!/usr/bin/env python3
"""Original background music for the promo reel ("清晨的老街", Everyday City).

Synthesised from scratch (no samples, no third-party material), so it is free of any licence:
C-major pentatonic lead, electric-piano chords, round bass, soft kick / snap / shaker.
96 BPM, 4/4, 24 bars = 60 s. Pure Python (no numpy), deterministic.

    python3 tools/make_music.py out.wav [bars]
"""
import array, math, random, struct, sys, wave

SR = 44100
BPM = 96
BEAT = 60.0 / BPM
BAR = 4 * BEAT
BARS = int(sys.argv[2]) if len(sys.argv) > 2 else 24  # 24 bars = 60 s; pass more for a longer reel
DUR = BARS * BAR + 2.0  # ring-out tail

L = array.array("f", [0.0]) * int(DUR * SR)
R = array.array("f", [0.0]) * int(DUR * SR)


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def add(start, length, fn, gain, pan=0.0):
    """Mixes fn(t) for `length` seconds from `start` (seconds), equal-power pan -1..1."""
    i0 = int(start * SR)
    n = int(length * SR)
    gl = gain * math.cos((pan + 1) * math.pi / 4)
    gr = gain * math.sin((pan + 1) * math.pi / 4)
    for k in range(n):
        i = i0 + k
        if i >= len(L):
            break
        v = fn(k / SR)
        L[i] += v * gl
        R[i] += v * gr


def epiano(f, length):
    def fn(t):
        env = min(1.0, t / 0.008) * math.exp(-t * 2.2) * (1.0 if t < length else math.exp(-(t - length) * 12))
        return env * (math.sin(2 * math.pi * f * t) + 0.35 * math.sin(4 * math.pi * f * t)
                      + 0.12 * math.sin(6 * math.pi * f * t) * math.exp(-t * 6))
    return fn


def pluck(f, length):
    def fn(t):
        env = min(1.0, t / 0.005) * math.exp(-t * (3.0 / max(length, 0.2))) * (1.0 if t < length else math.exp(-(t - length) * 18))
        vib = 1 + 0.004 * math.sin(2 * math.pi * 5.5 * t) * min(1.0, t / 0.3)
        p = 2 * math.pi * f * vib * t
        return env * (math.sin(p) + 0.3 * math.sin(3 * p) / 3 + 0.18 * math.sin(2 * p))
    return fn


def bass(f, length):
    def fn(t):
        env = min(1.0, t / 0.01) * math.exp(-t * 1.6) * (1.0 if t < length else math.exp(-(t - length) * 15))
        p = 2 * math.pi * f * t
        return env * (math.sin(p) + 0.25 * math.sin(2 * p) + 0.1 * math.sin(3 * p))
    return fn


def kick(t):
    f = 50 + 90 * math.exp(-t * 30)
    return math.sin(2 * math.pi * f * t) * math.exp(-t * 9)


rng = random.Random(7)
NOISE = [rng.uniform(-1, 1) for _ in range(SR)]


def snap(t):
    return NOISE[int(t * SR) % SR] * math.exp(-t * 28) * 0.8 + math.sin(2 * math.pi * 190 * t) * math.exp(-t * 35) * 0.4


def shaker(t):
    i = int(t * SR) % SR
    hp = NOISE[i] - NOISE[i - 1]
    return hp * math.exp(-t * 60) * min(1.0, t / 0.004)


# chords: (root midi for bass, chord tones for piano)
C = (48, [60, 64, 67, 72])
Am = (45, [57, 60, 64, 69])
F = (41, [57, 60, 65, 69])
G = (43, [55, 59, 62, 67])
Em = (40, [55, 59, 64, 67])
VERSE = [C, Am, F, G]
BRIDGE = [F, G, Em, Am]

# melody per chord: (beat, length in beats, midi) — C-major pentatonic (C D E G A)
MEL_VERSE = {
    0: [(0, 1, 76), (1, 0.5, 79), (1.5, 0.5, 76), (2, 1, 74), (3, 1, 72)],
    1: [(0, 1.5, 72), (1.5, 0.5, 74), (2, 1, 76), (3, 1, 69)],
    2: [(0, 1, 69), (1, 1, 72), (2, 1.5, 74), (3.5, 0.5, 72)],
    3: [(0, 1, 74), (1, 0.5, 76), (1.5, 0.5, 74), (2, 2, 79)],
}
MEL_VERSE_2 = {
    0: [(0, 0.5, 79), (0.5, 0.5, 81), (1, 1, 79), (2, 1, 76), (3, 1, 74)],
    1: [(0, 1, 72), (1, 1, 76), (2, 1.5, 74), (3.5, 0.5, 72)],
    2: [(0, 1, 69), (1, 0.5, 72), (1.5, 0.5, 74), (2, 1, 76), (3, 1, 74)],
    3: [(0, 1.5, 74), (1.5, 0.5, 72), (2, 2, 72)],
}
MEL_BRIDGE = {
    0: [(0, 0.5, 81), (0.5, 0.5, 79), (1, 1, 76), (2, 2, 74)],
    1: [(0, 1, 74), (1, 1, 79), (2, 1, 81), (3, 1, 79)],
    2: [(0, 1.5, 76), (1.5, 0.5, 79), (2, 2, 76)],
    3: [(0, 1, 72), (1, 1, 74), (2, 1, 76), (3, 1, 72)],
}

# form: 2 intro (chords only), 8 verse, 8 bridge+verse, 4 verse', 2 outro
plan = []
for b in range(BARS):
    if b < 2:
        plan.append((VERSE[b % 4], None, False))
    elif b < 10:
        plan.append((VERSE[b % 4], (MEL_VERSE if b < 6 else MEL_VERSE_2)[b % 4], True))
    elif b < 14:
        plan.append((BRIDGE[b % 4], MEL_BRIDGE[b % 4], True))
    elif b < 18:
        plan.append((VERSE[b % 4], MEL_VERSE[b % 4], True))
    elif b < 22:
        plan.append((VERSE[b % 4], MEL_VERSE_2[b % 4], True))
    else:
        plan.append((C, None, b == 22))

for b, ((root, tones), mel, drums) in enumerate(plan):
    t0 = b * BAR
    last = b == BARS - 1
    # piano: on 1 and on the "and" of 2 (a little syncopation), arpeggiated by a few ms
    hits = [(0, 1.5), (1.5, 2.5)] if not last else [(0, 6)]
    for beat, ln in hits:
        for j, m in enumerate(tones):
            add(t0 + beat * BEAT + j * 0.012, ln * BEAT + 0.6, epiano(hz(m), ln * BEAT), 0.055, -0.35)
    # bass on 1 and 3
    for beat in ([0, 2] if not last else [0]):
        add(t0 + beat * BEAT, (2 if not last else 4) * BEAT + 0.3, bass(hz(root), 1.8 * BEAT), 0.1)
    if mel:
        for beat, ln, m in mel:
            add(t0 + beat * BEAT, ln * BEAT + 0.4, pluck(hz(m), ln * BEAT), 0.13, 0.25)
    if last:
        add(t0, 6.0, pluck(hz(72), 3.0), 0.13, 0.25)
    if drums:
        for beat in (0, 2):
            add(t0 + beat * BEAT, 0.5, kick, 0.2)
        for beat in (1, 3):
            add(t0 + beat * BEAT, 0.3, snap, 0.12, 0.1)
        for e in range(8):
            add(t0 + e * BEAT / 2, 0.12, shaker, 0.06 if e % 2 else 0.035, 0.4)

peak = max(max(abs(x) for x in L), max(abs(x) for x in R))
g = 0.89 / peak
out = sys.argv[1] if len(sys.argv) > 1 else "music.wav"
with wave.open(out, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    frames = bytearray()
    for a, c in zip(L, R):
        frames += struct.pack("<hh", int(a * g * 32767), int(c * g * 32767))
    w.writeframes(bytes(frames))
print(f"wrote {out}: {DUR:.1f}s, peak scaled by {g:.2f}")
