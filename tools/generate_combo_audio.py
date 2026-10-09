"""Generate original CC0 piano-like short PCM notes; no external samples."""
import math, random, struct, wave
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1] / "OrbPuzzle" / "Audio"
ROOT.mkdir(parents=True, exist_ok=True)
MIDDLE = {"C":261.625565,"D":293.664768,"E":329.627557,"F":349.228231,
          "G":391.995436,"A":440.0,"B":493.883301}
NOTES = {f"{note}{octave}": frequency * 2 ** (octave - 4)
         for octave in (3, 4, 5) for note, frequency in MIDDLE.items()}
for index,(note,freq) in enumerate(NOTES.items()):
    rng=random.Random(20261009+list(MIDDLE).index(note[0]))
    samples=[]
    for i in range(13230):
        t=i/44100
        attack=1-math.exp(-t/0.0015)
        value=sum(a*math.sin(2*math.pi*freq*h*(1+0.0001*h*h)*t)*math.exp(-t*(8+1.7*h))
                  for h,a in enumerate([1,.48,.28,.16,.1,.055],1))
        value+=.025*rng.uniform(-1,1)*math.exp(-t/.006)
        tail=min(1,max(0,(.300-t)/.030))
        samples.append(value*attack*tail*tail)
    peak=max(abs(v) for v in samples)
    pcm=b"".join(struct.pack("<h",round(v/peak*.74*32767)) for v in samples)
    with wave.open(str(ROOT/f"combo_{note}.wav"),"wb") as out:
        out.setnchannels(1);out.setsampwidth(2);out.setframerate(44100);out.writeframes(pcm)
    print(f"combo_{note}.wav: PCM16 mono 44100 Hz, 300 ms")
