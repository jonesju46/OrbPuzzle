# OrbPuzzle audio assets

The app now ships recordings rather than generated waveforms. Full provenance, direct source URLs, licenses, and processing details are in [AUDIO_SOURCES.md](AUDIO_SOURCES.md).

## Piano

- `combo_C3.wav` through `combo_B5.wav` are derived from the CC0 **Meta Piano** recordings by Meta's Creative Audio team.
- Every note uses the directly recorded `Vel03` (mf) sample for that pitch. No pitch shifting, MIDI rendering, oscillator, or synthesized replacement is used.
- Final files are mono PCM signed 16-bit WAV, 44.1 kHz, approximately 1.8 seconds.
- V5.2 playback uses the same preloaded `B5 + D5` acoustic-piano pair for every resolved Combo group. The other verified recordings remain bundled assets but are not decoded into player pools during gameplay.

## Glass marble

- `orb_glass_swap.wav` is derived from **Marbles Clicking Together 2**, a real physical glass-marble collision recorded by Joseph Sardin and released as CC0.
- The source is used as one natural variation; it is not duplicated with pitch or speed changes to simulate extra takes.
- The final file is mono PCM signed 16-bit WAV, 44.1 kHz, approximately 0.16 seconds.

The former synthesized-audio generator was removed so it cannot overwrite the recorded assets.
