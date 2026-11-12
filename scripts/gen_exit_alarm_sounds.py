#!/usr/bin/env python3
"""Synthesises the three alarm sounds of the Aussteige-Wecker (docs/EXIT_ALARM.md §4): App/Resources/exitalarm-*.wav.

Plain sine tones with a fast attack and an exponential decay, generated here so the files carry no third-party licence.
16 bit, mono, 16 kHz, about 4 seconds each (a notification sound must stay under 30 s). Standard library only.

    python3 scripts/gen_exit_alarm_sounds.py            # writes App/Resources/exitalarm-*.wav
"""
import math
import os
import struct
import wave

RATE = 16000
DURATION = 4.0
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources")


def tone(buf, start, length, freq, gain, decay, partials=((1.0, 1.0),), attack=0.004):
    """Adds one struck tone into `buf` starting at `start` seconds."""
    first = int(start * RATE)
    count = int(length * RATE)
    for i in range(count):
        index = first + i
        if index >= len(buf):
            break
        t = i / RATE
        envelope = min(t / attack, 1.0) * math.exp(-t * decay)
        value = sum(weight * math.sin(2 * math.pi * freq * mult * t) for mult, weight in partials)
        buf[index] += gain * envelope * value


def write(name, buf):
    peak = max(1e-9, max(abs(v) for v in buf))
    scale = 0.89 / peak
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * scale)) * 32767)) for v in buf))
    print(path, os.path.getsize(path), "bytes")


def bell():
    """Glocke: three bell strikes."""
    buf = [0.0] * int(RATE * DURATION)
    for k, start in enumerate((0.0, 1.15, 2.3)):
        tone(buf, start, 1.6, 784.0, 1.0, 2.6, partials=((1.0, 1.0), (2.0, 0.45), (3.0, 0.2), (4.2, 0.1)))
        tone(buf, start, 1.6, 1174.7, 0.5, 3.0, partials=((1.0, 1.0), (2.0, 0.3)))
    return buf


def signal():
    """Signal: two groups of four short beeps, the urgent one."""
    buf = [0.0] * int(RATE * DURATION)
    for group in (0.0, 2.0):
        for k in range(4):
            tone(buf, group + k * 0.28, 0.2, 1200.0, 1.0, 5.0, partials=((1.0, 1.0), (2.0, 0.25)), attack=0.002)
    return buf


def soft():
    """Sanft: a rising chime, C5 E5 G5 C6, twice."""
    buf = [0.0] * int(RATE * DURATION)
    for round_start in (0.0, 2.0):
        for k, freq in enumerate((523.25, 659.25, 783.99, 1046.5)):
            tone(buf, round_start + k * 0.42, 1.3, freq, 0.8, 3.4, partials=((1.0, 1.0), (2.0, 0.18)), attack=0.012)
    return buf


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("exitalarm-glocke.wav", bell())
    write("exitalarm-signal.wav", signal())
    write("exitalarm-sanft.wav", soft())
