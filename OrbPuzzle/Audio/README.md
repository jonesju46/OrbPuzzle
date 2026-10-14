# OrbPuzzle audio assets

The app ships real recordings rather than generated waveforms. Full provenance,
source URLs, licenses, hashes, and processing details are in
[AUDIO_SOURCES.md](AUDIO_SOURCES.md).

## Combo soap bubble

- `combo_soap_bubble.wav` is a 0.30-second excerpt of a CC0 physical bubble-bath recording by Freesound user **danieldouch**.
- Every successfully resolved normalized Match Group requests this one sound once. Manual and Skyfall groups share the same mapping.
- The file is preloaded into a bounded four-voice pool. A request is dropped if all four attacks are still active; gameplay never waits for audio and no player is allocated during Resolve.
- Final format is mono PCM signed 16-bit WAV at 44.1 kHz. It has a short fade-in/out and no pitch change or synthesized layer.

## Retained piano recordings

- `combo_C3.wav` through `combo_B5.wav` remain as verified CC0 **Meta Piano** assets, but V5.3 no longer loads or plays them for Combo events.
- Every note uses the directly recorded `Vel03` (mf) sample for that pitch. No pitch shifting, MIDI rendering, oscillator, or synthesized replacement is used.
- Final files are mono PCM signed 16-bit WAV, 44.1 kHz, approximately 1.8 seconds.

## Glass marble

- `orb_glass_swap.wav` is derived from **Marbles Clicking Together 2**, a real physical glass-marble collision recorded by Joseph Sardin and released as CC0.
- The source is used as one natural variation; it is not duplicated with pitch or speed changes to simulate extra takes.
- The final file is mono PCM signed 16-bit WAV, 44.1 kHz, approximately 0.16 seconds.

The former synthesized-audio generator was removed so it cannot overwrite the recorded assets.
