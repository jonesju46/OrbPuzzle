# OrbPuzzle audio assets

The app ships real recordings rather than generated waveforms. Full provenance,
source URLs, licenses, hashes, and processing details are in
[AUDIO_SOURCES.md](AUDIO_SOURCES.md).

## Combo xylophone dyad

- `combo_xylophone_A6_A9.wav` is based on two real University of Iowa xylophone recordings made with hard-rubber mallets: C5 and C8, three octaves apart.
- The selected in-game sound shifts that recorded dyad up 21 semitones to A6 + A9 while retaining the three-octave interval. It is processed real-instrument audio, not an oscillator, MIDI render, or synthesized replacement.
- Every successfully resolved normalized Match Group requests this one sound once. Manual and Skyfall groups share the same mapping.
- The file is preloaded into a bounded four-voice pool. A request is dropped if all four attacks are still active; gameplay never waits for audio and no player is allocated during Resolve.
- Final format is stereo PCM signed 16-bit WAV at 44.1 kHz, approximately 0.80 seconds.

## Retained soap-bubble recording

- `combo_soap_bubble.wav` remains bundled for provenance and rollback, but Combo playback no longer loads or plays it.

## Retained piano recordings

- `combo_C3.wav` through `combo_B5.wav` remain as verified CC0 **Meta Piano** assets, but V5.3 no longer loads or plays them for Combo events.
- Every note uses the directly recorded `Vel03` (mf) sample for that pitch. No pitch shifting, MIDI rendering, oscillator, or synthesized replacement is used.
- Final files are mono PCM signed 16-bit WAV, 44.1 kHz, approximately 1.8 seconds.

## Glass marble

- `orb_glass_swap.wav` is derived from **Marbles Clicking Together 2**, a real physical glass-marble collision recorded by Joseph Sardin and released as CC0.
- The source is used as one natural variation; it is not duplicated with pitch or speed changes to simulate extra takes.
- The final file is mono PCM signed 16-bit WAV, 44.1 kHz, approximately 0.16 seconds.

The former synthesized-audio generator was removed so it cannot overwrite the recorded assets.
