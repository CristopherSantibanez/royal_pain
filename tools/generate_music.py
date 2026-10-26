"""Compone la música de ambiente del juego por síntesis (sin muestras externas).

Uso:  python tools/generate_music.py
Requiere numpy y soundfile (pip install numpy soundfile).
Escribe bucles .ogg estéreo en assets/music/. Cada pista es un bucle sin corte: las colas
de las notas y la reverberación se pliegan al inicio. Las pistas de combate tienen una capa
extra "<nombre>_tension.ogg" del mismo largo que el juego sube cuando el combate se pone feo.
Cualquier .ogg puede reemplazarse por música grabada con el mismo nombre.
"""
import os

import numpy as np
import soundfile as sf

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "music")

MODES = {
    "ionian": [0, 2, 4, 5, 7, 9, 11],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
}


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


class Key:
    def __init__(self, root, mode):
        self.root = root
        self.steps = MODES[mode]

    def midi(self, degree, octave=0):
        return self.root + 12 * (octave + degree // 7) + self.steps[degree % 7]


# --- Instrumentos (síntesis aditiva vectorizada) ---

def _t(n):
    return np.arange(n) / SR


def _attack(sig, seconds):
    n = min(len(sig), max(1, int(seconds * SR)))
    sig[:n] *= np.linspace(0.0, 1.0, n)
    return sig


def _release(sig, seconds):
    n = min(len(sig), max(1, int(seconds * SR)))
    sig[-n:] *= np.linspace(1.0, 0.0, n)
    return sig


def harp(rng, f, dur, decay=1.6, pluck_pos=0.13, bright=0.82):
    """Cuerda pulsada (arpa / laúd): parciales levemente inarmónicos que caen a ritmos distintos."""
    length = dur + decay * 2.5
    t = _t(int(length * SR))
    out = np.zeros_like(t)
    for h in range(1, 14):
        fh = f * h * (1.0 + 0.0003 * h * h)
        if fh > SR / 2.3:
            break
        amp = abs(np.sin(np.pi * h * pluck_pos)) * bright ** (h - 1) / h
        out += amp * np.sin(2 * np.pi * fh * t + rng.uniform(0, 6.28)) * np.exp(-t / (decay / (1 + 0.45 * (h - 1))))
    return _release(_attack(out, 0.003), 0.05)


def lute(rng, f, dur):
    return harp(rng, f, dur, decay=0.9, pluck_pos=0.2, bright=0.7)


def pad(rng, f, dur, attack=0.7, release=1.2, brightness=4.0, detune=0.004, vibrato=0.0):
    """Cuerdas / coro suave: tres voces desafinadas con armónicos que se apagan arriba."""
    length = dur + release
    t = _t(int(length * SR))
    out = np.zeros_like(t)
    for d in (-detune, 0.0, detune):
        ph = rng.uniform(0, 6.28)
        vib = 1.0 + vibrato * np.sin(2 * np.pi * 5.2 * t + ph)
        for h in range(1, 11):
            fh = f * h * (1 + d)
            if fh > SR / 2.3:
                break
            out += np.exp(-h / brightness) / h * np.sin(2 * np.pi * fh * t * vib + ph * h)
    out /= 3.0
    env = np.ones_like(t)
    a = int(attack * SR)
    env[:a] = np.linspace(0, 1, a) if a > 0 else 1
    r0 = int(dur * SR)
    env[r0:] = np.linspace(1, 0, len(env) - r0) ** 2
    return out * env


def flute(rng, f, dur, breath=0.05):
    """Flauta dulce: casi senoidal, vibrato que entra tarde y un poco de aire."""
    length = dur + 0.25
    t = _t(int(length * SR))
    vib_depth = 0.006 * np.clip((t - 0.25) / 0.4, 0, 1)
    phase = 2 * np.pi * f * (t + vib_depth / (2 * np.pi * 5.0) * -np.cos(2 * np.pi * 5.0 * t))
    out = np.sin(phase) + 0.22 * np.sin(2 * phase) + 0.07 * np.sin(3 * phase)
    air = np.diff(rng.uniform(-1, 1, len(t) + 1)) * breath
    out = out + air
    env = np.ones_like(t)
    a = int(0.06 * SR)
    env[:a] = np.linspace(0, 1, a)
    r0 = int(dur * SR)
    env[r0:] = np.linspace(1, 0, len(env) - r0)
    return out * env


def drone(rng, f, loop_len):
    """Zanfona que dura exactamente el bucle: frecuencia y ondulación caben en un número entero
    de ciclos, así el final empalma con el principio sin salto."""
    t = _t(int(round(loop_len * SR)))
    f = round(f * loop_len) / loop_len
    wobble = max(1, round(0.37 * loop_len)) / loop_len
    out = np.zeros_like(t)
    for h in range(1, 17):
        fh = f * h
        if fh > SR / 2.3:
            break
        formant = 1.0 + 1.5 * np.exp(-((fh - 1100) / 500) ** 2)
        out += formant / h * np.sin(2 * np.pi * fh * t + rng.uniform(0, 6.28))
    return out * (0.85 + 0.15 * np.sin(2 * np.pi * wobble * t))


def horn(rng, f, dur):
    """Cuerno: los armónicos altos entran con la fuerza del soplido."""
    length = dur + 0.3
    t = _t(int(length * SR))
    swell = np.clip(t / 0.18, 0, 1)
    r0 = int(dur * SR)
    swell[r0:] *= np.linspace(1, 0, len(t) - r0)
    out = np.zeros_like(t)
    for h in range(1, 10):
        out += (1.0 / h) * swell ** (1 + 0.5 * h) * np.sin(2 * np.pi * f * h * t * (1 + 0.002 * np.sin(2 * np.pi * 4.8 * t)))
    return out


def _noise_band(rng, n, lo, hi):
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SR)
    spec[(freqs < lo) | (freqs > hi)] = 0
    out = np.fft.irfft(spec, n)
    return out / (np.max(np.abs(out)) + 1e-9)


def frame_drum(rng, accent=1.0):
    t = _t(int(0.5 * SR))
    body = np.sin(2 * np.pi * (60 + 50 * np.exp(-t * 25)) * t) * np.exp(-t / 0.18)
    slap = _noise_band(rng, len(t), 300, 2500) * np.exp(-t / 0.02)
    return (body + 0.35 * slap) * accent


def war_drum(rng, accent=1.0):
    t = _t(int(1.0 * SR))
    body = np.sin(2 * np.pi * (42 + 55 * np.exp(-t * 18)) * t) * np.exp(-t / 0.42)
    skin = _noise_band(rng, len(t), 80, 900) * np.exp(-t / 0.07)
    return (body + 0.5 * skin) * accent


def snare(rng, accent=1.0):
    t = _t(int(0.3 * SR))
    tone_ = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.04)
    rattle = _noise_band(rng, len(t), 1500, 8000) * np.exp(-t / 0.07)
    return (0.6 * tone_ + rattle) * accent


def tambourine(rng, accent=1.0):
    t = _t(int(0.25 * SR))
    jingle = _noise_band(rng, len(t), 5000, 12000) * np.exp(-t / 0.06)
    for f in (4100, 5300, 6900):
        jingle += 0.3 * np.sin(2 * np.pi * f * t) * np.exp(-t / 0.05)
    return jingle * accent


# --- Mezcla ---

class Track:
    def __init__(self, bpm, bars, beats_per_bar=4, tail=6.0):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bpb = beats_per_bar
        self.length = bars * beats_per_bar * self.beat
        self.buf = np.zeros((int((self.length + tail) * SR), 2))

    def add(self, sig, beat, gain=1.0, pan=0.0):
        start = int(beat * self.beat * SR)
        end = min(len(self.buf), start + len(sig))
        if end <= start:
            return
        left = np.cos((pan + 1) * np.pi / 4)
        right = np.sin((pan + 1) * np.pi / 4)
        self.buf[start:end, 0] += sig[: end - start] * gain * left
        self.buf[start:end, 1] += sig[: end - start] * gain * right

    def render(self, rng, reverb=2.2, wet=0.28):
        dry = self.buf
        ir_len = int(reverb * SR)
        t = _t(ir_len)
        out = np.zeros((len(dry) + ir_len, 2))
        n = len(out)
        for ch in range(2):
            ir = _noise_band(rng, ir_len, 120, 6000) * np.exp(-t / (reverb / 6.9))
            ir[: int(0.012 * SR)] = 0   # pre-delay
            wet_sig = np.fft.irfft(np.fft.rfft(dry[:, ch], n) * np.fft.rfft(ir, n), n)
            wet_sig /= np.max(np.abs(wet_sig)) + 1e-9
            out[:, ch] = wet * wet_sig * np.max(np.abs(dry[:, ch]))
            out[: len(dry), ch] += dry[:, ch]
        # Pliega todo lo que sobra del final al inicio: el bucle no tiene corte.
        loop_n = int(self.length * SR)
        looped = out[:loop_n].copy()
        rest = out[loop_n:]
        while len(rest):
            k = min(len(rest), loop_n)
            looped[:k] += rest[:k]
            rest = rest[k:]
        return looped


def write_stems(name, stems, target_rms_db=-19.0):
    """Normaliza todas las capas con la misma ganancia (para que conserven su balance) y escribe .ogg."""
    os.makedirs(OUT_DIR, exist_ok=True)
    full = sum(stems.values())
    rms = np.sqrt(np.mean(full ** 2)) + 1e-9
    g = 10 ** (target_rms_db / 20) / rms
    peak = np.max(np.abs(full)) * g
    if peak > 0.89:   # deja margen de ~1 dB
        g *= 0.89 / peak
    for stem_name, data in stems.items():
        path = os.path.join(OUT_DIR, stem_name + ".ogg")
        frames = np.clip(data * g, -1, 1).astype(np.float32)
        # libsndfile se cae al codificar Vorbis en un solo bloque grande: se escribe por trozos.
        with sf.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS") as f:
            for i in range(0, len(frames), 8192):
                f.write(frames[i:i + 8192])
        print("%-16s %5.1fs" % (stem_name, len(data) / SR))


# --- Ayudas de composición ---

def chord_tones(chord_degree):
    return [chord_degree, chord_degree + 2, chord_degree + 4]


def melody(rng, prog, bpb, rhythms, start_degree, lo, hi, rest_chance=0.08):
    """Melodía modal: la primera nota de cada compás cae en una nota del acorde y luego avanza por grados."""
    notes = []
    cur = start_degree
    for bar, chord in enumerate(prog):
        pattern = rhythms[rng.integers(len(rhythms))]
        for j, (onset, length) in enumerate(pattern):
            if j == 0:
                cands = [d + 7 * o for d in chord_tones(chord) for o in range(-2, 4)]
                cands = [c for c in cands if lo <= c <= hi]
                cur = min(cands, key=lambda c: abs(c - cur) + rng.uniform(0, 0.6))
            else:
                cur = int(np.clip(cur + rng.choice([-2, -1, -1, 1, 1, 2]), lo, hi))
            if j > 0 and rng.uniform() < rest_chance:
                continue
            notes.append((bar * bpb + onset, length, cur))
    return notes


def phrase_repeat(notes, src_bars, dst_bar, bpb):
    """Copia los compases src_bars (rango) a partir de dst_bar: da forma A ... A a la melodía."""
    a, b = src_bars
    out = [n for n in notes if not (dst_bar * bpb <= n[0] < (dst_bar + b - a) * bpb)]
    for (beat, length, deg) in notes:
        if a * bpb <= beat < b * bpb:
            out.append((beat - a * bpb + dst_bar * bpb, length, deg))
    return sorted(out)


# --- Pistas ---

def track_menu():
    rng = np.random.default_rng(11)
    key = Key(50, "dorian")   # Re dórico
    prog = [0, -1, 3, 0, 0, 2, -1, 3, 5, 2, 3, -1, 0, -1, 3, 0]
    tr = Track(bpm=72, bars=len(prog))
    bpb = tr.bpb
    tr.add(drone(rng, hz(key.midi(0, -1)), tr.length), 0, 0.05, -0.1)
    tr.add(drone(rng, hz(key.midi(4, -1)), tr.length), 0, 0.035, 0.1)
    for bar, c in enumerate(prog):
        for i, d in enumerate(chord_tones(c)):
            tr.add(pad(rng, hz(key.midi(d, 1)), bpb * tr.beat, attack=1.0, release=1.5), bar * bpb, 0.07, -0.5 + 0.5 * i)
        tr.add(pad(rng, hz(key.midi(c, -1)), bpb * tr.beat, brightness=2.5), bar * bpb, 0.09, 0.0)
        tones = [c, c + 2, c + 4, c + 7, c + 9, c + 7, c + 4, c + 2]
        for k, d in enumerate(tones):
            tr.add(harp(rng, hz(key.midi(d, 0)), tr.beat * 0.5), bar * bpb + k * 0.5, 0.16 if k else 0.2, -0.3)
    rhythms = [[(0, 1.5), (1.5, 0.5), (2, 2)], [(0, 1), (1, 1), (2, 1.5), (3.5, 0.5)], [(0, 3), (3, 1)], [(0, 2), (2, 1), (3, 1)]]
    mel = melody(rng, prog, bpb, rhythms, 7, 5, 16)
    mel = [n for n in mel if n[0] >= 4 * bpb]          # la flauta entra en el compás 5
    mel = phrase_repeat(mel, (4, 8), 12, bpb)
    for beat, length, d in mel:
        tr.add(flute(rng, hz(key.midi(d, 0)), length * tr.beat * 0.95), beat, 0.13, 0.25)
    for bar in range(8, len(prog)):
        tr.add(frame_drum(rng, 0.8), bar * bpb, 0.18, 0.0)
        tr.add(frame_drum(rng, 0.5), bar * bpb + 2.5, 0.18, 0.0)
    write_stems("menu", {"menu": tr.render(rng, reverb=3.0, wet=0.35)})


def track_map():
    rng = np.random.default_rng(23)
    key = Key(55, "mixolydian")   # Sol mixolidio
    prog = [0, -1, 3, 0, 0, 4, -1, 0, 3, 0, 4, -1, 0, -1, 3, 0]
    tr = Track(bpm=84, bars=len(prog))
    bpb = tr.bpb
    for bar, c in enumerate(prog):
        tr.add(lute(rng, hz(key.midi(c, -1)), tr.beat), bar * bpb, 0.22, -0.2)
        tr.add(lute(rng, hz(key.midi(c + 4, -1)), tr.beat), bar * bpb + 2, 0.16, -0.2)
        pick = [c + 2, c + 4, c + 7, c + 4, c + 2, c + 4, c + 7, c + 9]
        for k, d in enumerate(pick):
            if k in (0, 4):
                continue
            tr.add(lute(rng, hz(key.midi(d, 0)), tr.beat * 0.5), bar * bpb + k * 0.5, 0.12, -0.35)
        for i, d in enumerate(chord_tones(c)):
            tr.add(pad(rng, hz(key.midi(d, 0)), bpb * tr.beat, attack=0.5, brightness=3.0), bar * bpb, 0.04, -0.4 + 0.4 * i)
        # tamboril y pandereta
        for onset, acc in ((0, 1.0), (1.0, 0.5), (1.5, 0.6), (2, 0.8), (3, 0.5), (3.5, 0.6)):
            tr.add(frame_drum(rng, acc), bar * bpb + onset, 0.16, 0.15)
        for onset in (1, 3):
            tr.add(tambourine(rng, 0.7), bar * bpb + onset, 0.05, 0.4)
    rhythms = [[(0, 1), (1, 0.5), (1.5, 0.5), (2, 1), (3, 1)], [(0, 1.5), (1.5, 0.5), (2, 1), (3, 0.5), (3.5, 0.5)],
               [(0, 2), (2, 1), (3, 1)], [(0, 0.5), (0.5, 0.5), (1, 1), (2, 2)]]
    mel = melody(rng, prog, bpb, rhythms, 9, 7, 18)
    mel = phrase_repeat(mel, (0, 4), 12, bpb)
    for beat, length, d in mel:
        tr.add(flute(rng, hz(key.midi(d, 0)), length * tr.beat * 0.9, breath=0.07), beat, 0.12, 0.3)
    write_stems("map", {"map": tr.render(rng, reverb=1.8, wet=0.22)})


def track_castle():
    rng = np.random.default_rng(37)
    key = Key(57, "aeolian")   # La eólico
    prog = [0, 5, 2, 6, 0, 5, 3, 4, 0, 5, 6, 0]
    tr = Track(bpm=66, bars=len(prog))
    bpb = tr.bpb
    for bar, c in enumerate(prog):
        tr.add(pad(rng, hz(key.midi(c, -2)), bpb * tr.beat, attack=0.8, brightness=2.0, vibrato=0.002), bar * bpb, 0.12, 0.0)
        for i, d in enumerate(chord_tones(c)):
            tr.add(pad(rng, hz(key.midi(d, 0)), bpb * tr.beat, attack=1.2, release=1.8, brightness=2.5), bar * bpb, 0.045, -0.4 + 0.4 * i)
        for k, d in enumerate([c, c + 4, c + 7, c + 9]):
            tr.add(harp(rng, hz(key.midi(d, -1)), tr.beat, decay=2.2), bar * bpb + k, 0.17, -0.25)
    rhythms = [[(0, 2), (2, 2)], [(0, 3), (3, 1)], [(0, 1.5), (1.5, 0.5), (2, 2)]]
    mel = melody(rng, prog, bpb, rhythms, 7, 4, 14, rest_chance=0.2)
    mel = [n for n in mel if n[0] >= 4 * bpb]
    for beat, length, d in mel:
        tr.add(flute(rng, hz(key.midi(d, 0)), length * tr.beat * 0.95, breath=0.04), beat, 0.09, 0.3)
    write_stems("castle", {"castle": tr.render(rng, reverb=3.2, wet=0.4)})


def track_duel():
    rng = np.random.default_rng(41)
    key = Key(52, "phrygian")   # Mi frigio
    prog = [0, 0, 1, 0, 0, 0, 5, 1, 0, 0, 1, 0, 5, 1, 0, 0]
    base = Track(bpm=112, bars=len(prog))
    tens = Track(bpm=112, bars=len(prog))
    bpb = base.bpb
    base.add(drone(rng, hz(key.midi(0, -1)), base.length), 0, 0.06, -0.1)
    base.add(drone(rng, hz(key.midi(4, -1)), base.length), 0, 0.04, 0.1)
    ostinato = [0, 0, 1, 0, 2, 1, 0, -1]
    for bar, c in enumerate(prog):
        for k, d in enumerate(ostinato):
            tr_deg = c + d
            base.add(lute(rng, hz(key.midi(tr_deg, 0)), base.beat * 0.5), bar * bpb + k * 0.5, 0.16 if k % 2 else 0.2, -0.3)
        for i, d in enumerate(chord_tones(c)):
            base.add(pad(rng, hz(key.midi(d, 0)), bpb * base.beat, attack=0.4, brightness=3.0), bar * bpb, 0.035, -0.4 + 0.4 * i)
        for onset, acc in ((0, 1.0), (1.5, 0.6), (2, 0.8), (3, 0.5), (3.5, 0.7)):
            base.add(frame_drum(rng, acc), bar * bpb + onset, 0.2, 0.0)
        # Capa de tensión: tambores de guerra, cuerdas graves cortantes y caja.
        for onset, acc in ((0, 1.0), (0.75, 0.5), (1.5, 0.7), (2, 1.0), (2.75, 0.5), (3.5, 0.8)):
            tens.add(war_drum(rng, acc), bar * bpb + onset, 0.32, 0.0)
        for onset in (0, 1.5, 3):
            tens.add(pad(rng, hz(key.midi(c, -1)), base.beat * 0.4, attack=0.01, release=0.15, brightness=5.0), bar * bpb + onset, 0.16, -0.2)
            tens.add(pad(rng, hz(key.midi(c + 4, -1)), base.beat * 0.4, attack=0.01, release=0.15, brightness=5.0), bar * bpb + onset, 0.11, 0.2)
        for k in range(8):
            tens.add(snare(rng, 0.35 if k % 2 else 0.6), bar * bpb + k * 0.5 + 0.25, 0.07, 0.3)
    write_stems("duel", {"duel": base.render(rng, reverb=1.6, wet=0.2), "duel_tension": tens.render(rng, reverb=1.6, wet=0.2)})


def track_battle():
    rng = np.random.default_rng(53)
    key = Key(50, "aeolian")   # Re eólico
    prog = [0, 5, 6, 0, 0, 5, 3, 4, 5, 6, 0, 0, 3, 4, 0, 0]
    base = Track(bpm=96, bars=len(prog))
    tens = Track(bpm=96, bars=len(prog))
    bpb = base.bpb
    for bar, c in enumerate(prog):
        for k in range(8):
            d = c if k % 4 != 3 else c + 4
            base.add(pad(rng, hz(key.midi(d, -1)), base.beat * 0.42, attack=0.01, release=0.12, brightness=4.0),
                     bar * bpb + k * 0.5, 0.11, -0.25)
        for i, d in enumerate(chord_tones(c)):
            base.add(pad(rng, hz(key.midi(d, 0)), bpb * base.beat, attack=0.6, brightness=3.0, vibrato=0.002), bar * bpb, 0.05, -0.4 + 0.4 * i)
        for onset, acc in ((0, 1.0), (1, 0.6), (2, 0.9), (2.5, 0.5), (3, 0.6)):
            base.add(war_drum(rng, acc), bar * bpb + onset, 0.28, 0.0)
        for k in range(16):
            tens.add(snare(rng, 0.7 if k % 4 == 0 else 0.35), bar * bpb + k * 0.25, 0.08, 0.25)
        for onset in (0, 2):
            for d, g in ((c, 0.1), (c + 2, 0.07), (c + 4, 0.08)):
                tens.add(horn(rng, hz(key.midi(d, 0)), base.beat * 0.8), bar * bpb + onset, g, 0.15)
        tens.add(war_drum(rng, 1.0), bar * bpb + 3.5, 0.3, 0.0)
    # Llamadas de cuerno (en la capa base, para que siempre suenen).
    call = [(0, 0.75, 0), (0.75, 0.25, 0), (1, 1, 4), (2, 2, 7)]
    answer = [(0, 0.75, 7), (0.75, 0.25, 6), (1, 1, 4), (2, 2, 0)]
    for bar, motif in ((0, call), (2, answer), (8, call), (10, answer)):
        for onset, length, d in motif:
            base.add(horn(rng, hz(key.midi(d, 0)), length * base.beat * 0.95), bar * bpb + onset, 0.14, 0.3)
    write_stems("battle", {"battle": base.render(rng, reverb=2.0, wet=0.25), "battle_tension": tens.render(rng, reverb=2.0, wet=0.25)})


# --- Ambientes (bucles de fondo sin melodía) ---

def ambience_wind():
    rng = np.random.default_rng(61)
    length = 32.0
    n = int(length * SR)
    t = _t(n)
    out = np.zeros((n, 2))
    for ch in range(2):
        gust = 0.55 + 0.25 * np.sin(2 * np.pi * t * 2 / length + ch) + 0.2 * np.sin(2 * np.pi * t * 5 / length + 2 * ch)
        out[:, ch] = _noise_band(rng, n, 150, 900) * gust * 0.5 + _noise_band(rng, n, 900, 2500) * gust ** 3 * 0.12
    # pájaros lejanos
    for _ in range(9):
        start = rng.uniform(0, length - 1)
        pan = rng.uniform(-0.7, 0.7)
        base_f = rng.uniform(2600, 4200)
        for k in range(rng.integers(2, 5)):
            dur = rng.uniform(0.06, 0.14)
            tt = _t(int(dur * SR))
            chirp = np.sin(2 * np.pi * (base_f + 1500 * tt / dur * rng.choice([-1, 1])) * tt) * np.sin(np.pi * tt / dur) ** 2
            s = int((start + k * 0.16) * SR)
            e = min(n, s + len(chirp))
            out[s:e, 0] += chirp[: e - s] * 0.07 * np.cos((pan + 1) * np.pi / 4)
            out[s:e, 1] += chirp[: e - s] * 0.07 * np.sin((pan + 1) * np.pi / 4)
    write_stems("amb_wind", {"amb_wind": out}, target_rms_db=-24.0)


def ambience_fire():
    rng = np.random.default_rng(67)
    length = 30.0
    n = int(length * SR)
    t = _t(n)
    out = np.zeros((n, 2))
    roar = _noise_band(rng, n, 40, 320) * (0.8 + 0.2 * np.sin(2 * np.pi * t * 3 / length))
    out[:, 0] += roar * 0.5
    out[:, 1] += roar * 0.5
    # chasquidos de la leña
    for _ in range(int(length * 7)):
        s = int(rng.uniform(0, length - 0.05) * SR)
        dur = int(rng.uniform(0.002, 0.012) * SR)
        click = rng.standard_normal(dur) * np.exp(-np.arange(dur) / (dur / 3))
        g = rng.uniform(0.05, 0.4) ** 1.5
        pan = rng.uniform(-0.5, 0.5)
        out[s:s + dur, 0] += click * g * np.cos((pan + 1) * np.pi / 4)
        out[s:s + dur, 1] += click * g * np.sin((pan + 1) * np.pi / 4)
    write_stems("amb_fire", {"amb_fire": out}, target_rms_db=-26.0)


def main():
    track_menu()
    track_map()
    track_castle()
    track_duel()
    track_battle()
    ambience_wind()
    ambience_fire()


if __name__ == "__main__":
    main()
