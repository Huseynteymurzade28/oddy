#!/usr/bin/env python3
"""Makes the game's own sound effects: the ones no sound pack has, because
they belong to things only this game does. Written straight to assets/sounds
as 44.1kHz mono WAVs. Run it again after changing a sound here.

  light_on   the light coming back: two soft bell notes going up
  light_off  the light being spent: the same two, lower, going down
  room       crossing into the next room: a breath of air
"""
import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "sounds")


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def bell(freq, seconds, decay):
    """A struck note: the tone, a little of its octave and a detuned
    shimmer, dying away."""
    x = t(seconds)
    tone = np.sin(2 * np.pi * freq * x) + 0.35 * np.sin(2 * np.pi * freq * 2.01 * x) + 0.12 * np.sin(2 * np.pi * freq * 3.02 * x)
    env = np.exp(-x * decay) * np.minimum(1, x / 0.004)
    return tone * env


def place(parts, seconds):
    out = np.zeros(int(RATE * seconds))
    for start, sound in parts:
        i = int(RATE * start)
        n = min(len(sound), len(out) - i)
        out[i:i + n] += sound[:n]
    return out


def save(name, samples, peak=0.7):
    samples = samples / max(1e-9, np.abs(samples).max()) * peak
    fade = int(RATE * 0.01)
    samples[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((samples * 32767).astype("<i2").tobytes())


def breath(seconds):
    """Noise through a band that opens and closes: air going past."""
    rng = np.random.default_rng(7)
    noise = rng.standard_normal(int(RATE * seconds))
    x = t(seconds)
    out = np.zeros_like(noise)
    low = 0.0
    band = 0.0
    for i in range(len(noise)):
        k = 0.02 + 0.10 * np.sin(np.pi * x[i] / seconds) ** 2
        low += k * (noise[i] - low)
        band += 0.5 * k * (low - band)
        out[i] = low - band
    return out * np.sin(np.pi * x / seconds) ** 1.5


E5, B5, E4, B4 = 659.25, 987.77, 329.63, 493.88

save("light_on", place([(0, bell(E5, 0.3, 16)), (0.055, bell(B5, 0.3, 13))], 0.34), 0.6)
save("light_off", place([(0, bell(B4, 0.26, 20)), (0.05, bell(E4, 0.3, 15) * 0.9)], 0.32), 0.6)
save("room", breath(0.38), 0.5)
print("wrote light_on, light_off, room")
