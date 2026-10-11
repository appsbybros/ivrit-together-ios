"""Renders Resources/success.wav, the short chime played after a right answer.

Two rising bell-like notes (C6, then G6 a tenth of a second later), each a sine with two
softer overtones that fade faster, a 4 ms attack so nothing clicks, and a short fade at the
end. 44.1 kHz, mono, 16-bit PCM, 0.65 seconds, peak about -6 dBFS so it stays gentle next to
the Hebrew speech. Standard library only; the output is the same on every run.

Usage: python Scripts/make_sound.py
"""
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Resources" / "success.wav"

RATE = 44100
LENGTH = 0.65  # seconds; well inside the 1.2-second success pause
PEAK = 0.5  # about -6 dBFS
ATTACK = 0.004  # seconds
FADE = 0.03  # seconds of fade at the very end
# (frequency in Hz, start in seconds, decay time in seconds, level)
NOTES = [
    (1046.50, 0.00, 0.16, 0.8),  # C6
    (1567.98, 0.10, 0.22, 1.0),  # G6
]
# (multiple of the note's frequency, level); a higher partial decays proportionally faster
PARTIALS = [(1.0, 1.0), (2.0, 0.22), (3.0, 0.06)]


def sample(t):
    value = 0.0
    for frequency, start, decay, level in NOTES:
        local = t - start
        if local < 0:
            continue
        attack = min(local / ATTACK, 1.0)
        for multiple, partial_level in PARTIALS:
            envelope = attack * math.exp(-local * multiple / decay)
            value += level * partial_level * envelope * math.sin(2 * math.pi * frequency * multiple * local)
    fade = min((LENGTH - t) / FADE, 1.0)
    return value * max(fade, 0.0)


def main():
    count = int(RATE * LENGTH)
    raw = [sample(index / RATE) for index in range(count)]
    loudest = max(abs(value) for value in raw)
    scale = PEAK / loudest
    frames = b"".join(struct.pack("<h", int(round(value * scale * 32767))) for value in raw)
    with wave.open(str(OUTPUT), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(frames)
    print(f"{OUTPUT.relative_to(ROOT)}: {count} frames, {count / RATE:.2f} s, {len(frames) + 44} bytes")


if __name__ == "__main__":
    main()
