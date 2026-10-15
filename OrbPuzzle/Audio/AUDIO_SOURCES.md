# Audio sources and provenance

Access and license verification date: **2026-10-15**

## Combo xylophone dyad

| Field | Value |
| --- | --- |
| Asset | `combo_xylophone_A6_A9.wav` |
| Original Title | Xylophone — hard rubber mallets, mezzo-forte |
| Performer | Andrew Thierauf |
| Collection | University of Iowa Musical Instrument Samples |
| Original URL | https://theremin.music.uiowa.edu/MISxylophone.html |
| C5–B5 Direct Download | https://theremin.music.uiowa.edu/sound%20files/MIS/Percussion/Xylophone/xylophone.hardrubber.mf.C5B5.aif |
| C8 Direct Download | https://theremin.music.uiowa.edu/sound%20files/MIS/Percussion/Xylophone/xylophone.hardrubber.mf.C8.aif |
| C5–B5 Source SHA-256 | `5C4B667C35EA9F787B3D6E4FF3C2375C19F99593F8518F00564E8215B12CF2AA` |
| C8 Source SHA-256 | `348BF65F366BF3B1866C555E8AACAAAA1FE00F6AE1E73AF0438F354ECB0A35AA` |
| Final Asset SHA-256 | `2B3FB296F0FB80F93A07D17BAEC3B25EBF5F5FF21737D4FF254BE244CA47A51D` |
| Usage Permission | University of Iowa MIS unrestricted project-use statement |
| Permission URL | https://theremin.music.uiowa.edu/MIS.html |
| Access Date | 2026-10-15 |
| Recording Type | Real acoustic xylophone recorded in the University of Iowa anechoic chamber on 2013-06-10 with an Earthworks QTC40 microphone and Metric Halo 2882 interface; original files are stereo, 24-bit, 44.1 kHz. |
| Processing | Extracted the directly recorded C5 from the C5–B5 chromatic file and the directly recorded C8 single note; aligned their attacks; applied +18 dB and +12 dB gain respectively; mixed, limited and faded the three-octave dyad. The accepted preview then shifts the complete dyad up 21 semitones to A6 + A9 using sample-rate conversion with tempo compensation. Final output is stereo PCM signed 16-bit WAV at 44.1 kHz, approximately 0.80 seconds. |
| Synthesis Disclosure | No oscillator, synthesizer, MIDI instrument, or generated waveform is used. A6 and A9 are pitch-shifted from the real C5 and C8 recordings and are not claimed as directly recorded A pitches. |
| Redistribution | **Confirmed for this repository.** The collection's official usage page permits downloaded samples to be used in projects without restrictions. |
| Verification | **Confirmed real recording and documented processing.** Selected by the user after listening to the exact final WAV. iPhone playback remains unverified on Windows. |

## Combo soap-bubble Foley

| Field | Value |
| --- | --- |
| Asset | `combo_soap_bubble.wav` |
| Original Title | Grilled bacon |
| Creator | danieldouch (Freesound user) |
| Original URL | https://freesound.org/people/danieldouch/sounds/163998/ |
| Public Preview URL | https://cdn.freesound.org/previews/163/163998_1622836-hq.mp3 |
| Source Preview SHA-256 | `610AD9D90C7DFA905972BA561B411025EE1CE472138710428C604450B055FD30` |
| Final Asset SHA-256 | `B54F36068EB9C3D46EE0FAE488DD151F5C4EF97F9832C5F87A4639C206F129FB` |
| License | CC0 1.0 Universal public-domain dedication |
| License URL | https://creativecommons.org/publicdomain/zero/1.0/ |
| Access Date | 2026-10-14 |
| Recording Type | Real physical bubble-bath Foley. The creator says the source is a bubble bath recorded with the bubbles popping close to the recorder. |
| Source Format | Public high-quality MP3 preview of the 64.768-second, 48 kHz stereo source. The original WAV download was not accessed because Freesound requires login. |
| Processing | Selected one isolated physical pop at 48.295 seconds; trimmed to 0.300 seconds; high-pass filtered at 80 Hz; applied a 3 ms fade-in and 60 ms fade-out; normalized to -20 LUFS with a -6 dB true-peak ceiling; converted to mono PCM signed 16-bit WAV at 44.1 kHz. No speed/pitch change, synthesis, or AI layer. |
| Redistribution | **Confirmed for this public repository.** The source page applies CC0, which permits copying, modification, commercial use, and redistribution. |
| Verification | **Confirmed recording and license.** The Freesound page identifies the physical bubble-bath recording method and CC0 license. iPhone listening remains unverified on Windows. |

### Rejected requested Mixkit candidate

The requested Mixkit item, **Soap bubble sound**, appears on
https://mixkit.co/free-sound-effects/pop/. It was not included because the page
does not identify a creator or recording method, so real-recording authenticity
is unverified. More importantly, the Mixkit Sound Effects Free License permits
use in a video-game end product but says the item cannot be redistributed with
source files. `jonesju46/OrbPuzzle` is a public GitHub repository and bundles
raw WAV resources in its source tree, so committing that item would violate the
stated source-file restriction. The CC0 recording above is the legally
redistributable replacement.

## Real acoustic piano

| Field | Value |
| --- | --- |
| Original Title | Meta Piano |
| Creator | Meta Creative Audio team / Meta Platforms, Inc. |
| Original URL | https://github.com/facebookincubator/Meta-open-sound/tree/main/systems/instruments/meta-piano |
| Source Snapshot | Meta-open-sound commit `e2ff154845994fe4135becc4d5b857c19f172784` |
| License | CC0 1.0 Universal public-domain dedication |
| License URL | https://github.com/facebookincubator/Meta-open-sound/blob/main/LICENSE |
| Recording Type | Acoustic Piano — real full 88-key upright piano, four directly recorded velocity layers per key |
| Processing | Used each pitch's direct Vel03 (mf) OGG preview. Removed leading silence; trimmed to 1.8 s; applied a 3 ms fade-in and 180 ms fade-out; normalized to -24 LUFS with -3 dB true-peak ceiling; converted to mono PCM signed 16-bit WAV at 44.1 kHz. No pitch shifting. |
| Verification | **Confirmed.** The official repository identifies the collection as professionally recorded audio, lists 352 real upright-piano samples, and releases audio and metadata under CC0. |

### Piano asset mapping

Every output note is a direct recording of that exact pitch from the same piano, session, and `Vel03` layer.

| Asset | Direct Download URL |
| --- | --- |
| `combo_C3.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_C3_01.ogg |
| `combo_D3.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_D3_01.ogg |
| `combo_E3.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_E3_01.ogg |
| `combo_F3.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_F3_01.ogg |
| `combo_G3.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_G3_01.ogg |
| `combo_A3.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_A3_01.ogg |
| `combo_B3.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_B3_01.ogg |
| `combo_C4.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_C4_01.ogg |
| `combo_D4.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_D4_01.ogg |
| `combo_E4.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_E4_01.ogg |
| `combo_F4.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_F4_01.ogg |
| `combo_G4.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_G4_01.ogg |
| `combo_A4.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_A4_01.ogg |
| `combo_B4.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_B4_01.ogg |
| `combo_C5.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_C5_01.ogg |
| `combo_D5.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_D5_01.ogg |
| `combo_E5.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_E5_01.ogg |
| `combo_F5.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_F5_01.ogg |
| `combo_G5.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_G5_01.ogg |
| `combo_A5.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_A5_01.ogg |
| `combo_B5.wav` | https://raw.githubusercontent.com/facebookincubator/Meta-open-sound/main/systems/instruments/meta-piano/ogg/INSPiano_Vel03_B5_01.ogg |

## Real glass-marble Foley

| Field | Value |
| --- | --- |
| Asset | `orb_glass_swap.wav` |
| Original Title | Marbles Clicking Together 2 |
| Creator | Joseph Sardin (contributor: BigSoundBank.com) |
| Original URL | https://licensing.routenote.com/sound-effect/marbles-clicking-together-2 |
| Direct Download URL | https://storage.googleapis.com/routenote-licensing-storage/public/sound_effects/3504/2229%20%281%29.mp3 |
| Source SHA-256 | `E116E0100CB6EA30F8CEBCD42468B8B0AD5BA85C3A28434010FD27E8300625F2` |
| License | CC0 1.0 Universal public-domain dedication |
| License URL | https://creativecommons.org/publicdomain/zero/1.0/ |
| Recording Type | Glass Foley — real physical glass marbles clicking together |
| Processing | Removed leading silence; retained the natural short impact; applied a 1 ms fade-in and 30 ms fade-out; normalized to -30 LUFS with -6 dB true-peak ceiling; converted from the public MP3 to mono PCM signed 16-bit WAV at 44.1 kHz. No speed or pitch changes. |
| Verification | **Confirmed.** The source page identifies the sound as marbles/glass, names Joseph Sardin and BigSoundBank.com, and explicitly marks the asset CC0. |

## Licensing notes

- CC0 permits commercial use, editing, app bundling, and repository redistribution without attribution.
- Attribution is not legally required for these sources, but this manifest keeps full credit and traceability.
- Freesound originals that required login were not downloaded. Public playback previews were used where documented; no CAPTCHA, login restriction, or download barrier was bypassed.
- No Pixabay, Sample Focus, commercial-game extraction, MIDI render, or generated audio is included.
