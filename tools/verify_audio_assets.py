"""Static WAV integrity and signal checks for OrbPuzzle's shipped recordings."""

from __future__ import annotations

import hashlib
import json
import math
import sys
import wave
from array import array
from pathlib import Path


NOTES = [
    "C3", "D3", "E3", "F3", "G3", "A3", "B3",
    "C4", "D4", "E4", "F4", "G4", "A4", "B4",
    "C5", "D5", "E5", "F5", "G5", "A5", "B5",
]

EXPECTED_SHA256 = {
    "combo_soap_bubble.wav": "b54f36068eb9c3d46ee0fae488dd151f5c4ef97f9832c5f87a4639c206f129fb",
}


def inspect(path: Path) -> dict[str, int | float | str]:
    with wave.open(str(path), "rb") as source:
        channels = source.getnchannels()
        sample_width = source.getsampwidth()
        sample_rate = source.getframerate()
        frame_count = source.getnframes()
        frames = source.readframes(frame_count)

    if channels != 1 or sample_width != 2 or sample_rate != 44_100:
        raise AssertionError(f"Unexpected PCM format: {path}")
    samples = array("h")
    samples.frombytes(frames)
    if sys.byteorder != "little":
        samples.byteswap()
    peak = max(abs(sample) for sample in samples)
    rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
    dc = sum(samples) / len(samples)
    clipping_samples = sum(1 for sample in samples if abs(sample) >= 32_767)
    if peak == 0 or rms == 0:
        raise AssertionError(f"Silent audio asset: {path}")
    if clipping_samples:
        raise AssertionError(f"Clipping detected in {path}: {clipping_samples} samples")
    if abs(dc) > 200:
        raise AssertionError(f"Excessive DC offset in {path}: {dc}")
    if abs(samples[0]) > 128 or abs(samples[-1]) > 128:
        raise AssertionError(
            f"Edge discontinuity risk in {path}: first={samples[0]} last={samples[-1]}"
        )

    duration = frame_count / sample_rate
    if path.name == "combo_soap_bubble.wav" and not 0.15 <= duration <= 0.35:
        raise AssertionError(f"Unexpected soap-bubble duration: {path} ({duration})")
    if path.name.startswith("combo_") and path.name != "combo_soap_bubble.wav" and abs(duration - 1.8) > 0.01:
        raise AssertionError(f"Unexpected piano duration: {path} ({duration})")
    if path.name == "orb_glass_swap.wav" and not 0.14 <= duration <= 0.175:
        raise AssertionError(f"Unexpected glass duration: {path} ({duration})")
    sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
    expected_hash = EXPECTED_SHA256.get(path.name)
    if expected_hash is not None and sha256 != expected_hash:
        raise AssertionError(f"SHA-256 mismatch in {path}: {sha256}")
    return {
        "asset": path.name,
        "sampleRate": sample_rate,
        "bitDepth": sample_width * 8,
        "channels": channels,
        "duration": round(duration, 6),
        "peakDbFS": round(20 * math.log10(peak / 32_767), 3),
        "rmsDbFS": round(20 * math.log10(rms / 32_767), 3),
        "dcOffset": round(dc, 3),
        "firstSample": samples[0],
        "lastSample": samples[-1],
        "clippingSamples": clipping_samples,
        "bytes": path.stat().st_size,
        "sha256": sha256,
    }


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    audio_dir = root / "OrbPuzzle" / "Audio"
    expected = [audio_dir / f"combo_{note}.wav" for note in NOTES]
    expected.append(audio_dir / "combo_soap_bubble.wav")
    expected.append(audio_dir / "orb_glass_swap.wav")
    missing = [str(path) for path in expected if not path.is_file()]
    if missing:
        raise AssertionError(f"Missing audio assets: {missing}")
    report = [inspect(path) for path in expected]
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
