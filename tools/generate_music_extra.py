"""Amplía la banda sonora: piezas por contexto y por cultura, ambientes de lugares y fanfarrias.

Uso:  python tools/generate_music_extra.py [grupo ...]
Grupos: culturas, contextos, combate, fanfarrias, ambientes (sin argumentos: todos).
Reutiliza los instrumentos y la mezcla de generate_music.py (mismo bucle sin corte y mismas reglas):
  map_<cultura>, castle_<cultura>      variaciones por cultura del reino donde está el jugador
  map_b, castle_b, travel_*, court_*, mourning_*, captivity_*
  duel_b/_c y battle_b/_c              cada una con su capa "_tension"
  sting_victory_*                      fanfarrias de una sola vez (no se repiten en bucle)
  amb_castle, amb_road, amb_crowd, amb_rain, amb_snow, amb_sea, amb_dungeon
Cualquier .ogg puede reemplazarse por una grabación con el mismo nombre.
"""
import importlib.util
import os
import sys

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("generate_music", os.path.join(_HERE, "generate_music.py"))
gm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gm)

SR = gm.SR
hz, Key, Track = gm.hz, gm.Key, gm.Track
harp, lute, pad, flute, drone, horn = gm.harp, gm.lute, gm.pad, gm.flute, gm.drone, gm.horn
frame_drum, war_drum, snare, tambourine = gm.frame_drum, gm.war_drum, gm.snare, gm.tambourine
melody, phrase_repeat, chord_tones, write_stems = gm.melody, gm.phrase_repeat, gm.chord_tones, gm.write_stems
_t, _noise_band, _attack, _release = gm._t, gm._noise_band, gm._attack, gm._release

gm.MODES.update({
    "lydian": [0, 2, 4, 6, 7, 9, 11],
    "hijaz": [0, 1, 4, 5, 7, 8, 10],   # frigio dominante: la cadencia andaluza
})

# Orden = NameCatalog.Culture (el juego busca map_<clave> / castle_<clave>).
CULTURES = ["franca", "inglesa", "castellana", "imperial", "romana", "prusiana", "italiana", "borgonona", "aragonesa"]


# --- Instrumentos nuevos ---

def shawm(rng, f, dur):
    """Chirimía / gaita: lengüeta doble, nasal, con formantes altos."""
    length = dur + 0.2
    t = _t(int(length * SR))
    vib = 1.0 + 0.004 * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.15) / 0.3, 0, 1)
    out = np.zeros_like(t)
    for h in range(1, 16):
        fh = f * h
        if fh > SR / 2.3:
            break
        formant = np.exp(-((fh - 1250) / 650) ** 2) + 0.6 * np.exp(-((fh - 2700) / 800) ** 2) + 0.25
        out += formant / h ** 0.6 * np.sin(2 * np.pi * fh * t * vib)
    env = np.ones_like(t)
    a = int(0.03 * SR)
    env[:a] = np.linspace(0, 1, a)
    r0 = int(dur * SR)
    env[r0:] = np.linspace(1, 0, len(env) - r0)
    return out * env * 0.5


def choir(rng, f, dur, attack=0.9, release=1.4):
    """Coro sin palabras («ah»): armónicos pesados por los formantes de la vocal."""
    length = dur + release
    t = _t(int(length * SR))
    out = np.zeros_like(t)
    for d in (-0.005, 0.0, 0.005):
        ph = rng.uniform(0, 6.28)
        vib = 1.0 + 0.003 * np.sin(2 * np.pi * 4.8 * t + ph)
        for h in range(1, 14):
            fh = f * h
            if fh > SR / 2.3:
                break
            g = np.exp(-((fh - 700) / 260) ** 2) + 0.7 * np.exp(-((fh - 1150) / 300) ** 2) + 0.25 * np.exp(-((fh - 2500) / 500) ** 2) + 0.05
            out += g / h ** 0.5 * np.sin(2 * np.pi * fh * (1 + d) * t * vib + ph * h)
    out /= 3.0
    env = np.ones_like(t)
    a = int(attack * SR)
    env[:a] = np.linspace(0, 1, a)
    r0 = int(dur * SR)
    env[r0:] = np.linspace(1, 0, len(env) - r0) ** 2
    return out * env


def bell(rng, f, dur=4.0):
    """Campana: parciales inarmónicos con caídas largas."""
    t = _t(int(dur * SR))
    out = np.zeros_like(t)
    for r, a, d in ((0.5, 0.6, 2.4), (1.0, 1.0, 1.8), (1.19, 0.5, 1.2), (1.5, 0.45, 1.0), (2.0, 0.35, 0.8), (2.74, 0.25, 0.5), (3.76, 0.15, 0.35)):
        out += a * np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    return _attack(out, 0.002)


def oud(rng, f, dur):
    return harp(rng, f, dur, decay=0.7, pluck_pos=0.08, bright=0.9)


def recorder(rng, f, dur):
    return flute(rng, f, dur, breath=0.03)


def low_brass(rng, f, dur):
    return horn(rng, f, dur) * 1.1


def castanets(rng, accent=1.0):
    t = _t(int(0.08 * SR))
    click = _noise_band(rng, len(t), 1800, 7000) * np.exp(-t / 0.008)
    return (click + 0.4 * np.sin(2 * np.pi * 2300 * t) * np.exp(-t / 0.01)) * accent


LEADS = {"flute": (flute, 0.13), "shawm": (shawm, 0.11), "recorder": (recorder, 0.12), "horn": (horn, 0.12),
         "oud": (oud, 0.2), "lute": (lute, 0.2), "choir": (choir, 0.09), "brass": (low_brass, 0.12)}

RHYTHMS = {
    4: [[(0, 1), (1, 0.5), (1.5, 0.5), (2, 1), (3, 1)], [(0, 1.5), (1.5, 0.5), (2, 1), (3, 0.5), (3.5, 0.5)],
        [(0, 2), (2, 1), (3, 1)], [(0, 0.5), (0.5, 0.5), (1, 1), (2, 2)]],
    3: [[(0, 1), (1, 1), (2, 1)], [(0, 2), (2, 1)], [(0, 1.5), (1.5, 0.5), (2, 1)], [(0, 0.5), (0.5, 0.5), (1, 1), (2, 1)]],
}

# Percusión por estilo: lista de (pulso dentro del compás, intensidad, instrumento).
PERC = {
    "frame4": [(0, 1.0, "frame"), (1.5, 0.6, "frame"), (2, 0.8, "frame"), (3, 0.5, "frame")],
    "frame3": [(0, 1.0, "frame"), (1, 0.5, "frame"), (2, 0.6, "frame")],
    "tabor4": [(0, 1.0, "frame"), (1, 0.5, "snare"), (2, 0.8, "frame"), (3, 0.5, "snare"), (3.5, 0.3, "snare")],
    "tamb3": [(0, 1.0, "frame"), (1, 0.6, "tamb"), (2, 0.6, "tamb"), (2.5, 0.4, "tamb")],
    "cast3": [(0, 1.0, "frame"), (0.5, 0.5, "cast"), (1, 0.7, "cast"), (2, 0.7, "cast"), (2.5, 0.5, "cast")],
    "march4": [(0, 1.0, "war"), (1, 0.4, "snare"), (1.5, 0.3, "snare"), (2, 0.8, "war"), (3, 0.4, "snare"), (3.5, 0.5, "snare")],
    "stately4": [(0, 1.0, "war"), (2, 0.6, "war")],
    "none": [],
}


def _perc(rng, kind, accent):
    return {"frame": frame_drum, "snare": snare, "tamb": tambourine, "war": war_drum, "cast": castanets}[kind](rng, accent)


# Estilo de cada cultura: tónica (MIDI), modo, compás, tempo, instrumentos y percusión.
STYLES = {
    "franca": dict(root=50, mode="dorian", meter=3, bpm=100, lead="flute", accomp="harp", drone=True, perc="frame3",
                   prog=[0, -1, 3, 0, 0, 2, -1, 0, 3, 2, -1, 0, 0, -1, 3, 0]),
    "inglesa": dict(root=55, mode="mixolydian", meter=4, bpm=92, lead="shawm", accomp="lute", drone=True, perc="tabor4",
                    prog=[0, -1, 3, 0, 0, 4, -1, 0, 3, 0, 4, -1, 0, -1, 3, 0]),
    "castellana": dict(root=52, mode="hijaz", meter=3, bpm=104, lead="oud", accomp="oud", drone=False, perc="tamb3",
                       prog=[0, 6, 5, 4, 0, 6, 5, 4, 3, 2, 1, 0, 0, 6, 5, 0]),
    "imperial": dict(root=50, mode="dorian", meter=4, bpm=76, lead="brass", accomp="harp", drone=True, perc="stately4",
                     prog=[0, 3, 0, 4, 0, 5, 3, 4, 0, 3, 6, 0, 5, 3, 4, 0]),
    "romana": dict(root=48, mode="mixolydian", meter=4, bpm=80, lead="horn", accomp="lute", drone=True, perc="frame4",
                   prog=[0, 3, 4, 0, 0, 6, 3, 0, 4, 3, 0, 6, 0, 3, 4, 0]),
    "prusiana": dict(root=45, mode="aeolian", meter=4, bpm=88, lead="choir", accomp="lute", drone=True, perc="march4",
                     prog=[0, 5, 6, 0, 0, 3, 4, 0, 5, 6, 0, 0, 3, 4, 0, 0]),
    "italiana": dict(root=57, mode="lydian", meter=3, bpm=112, lead="recorder", accomp="lute", drone=False, perc="tamb3",
                     prog=[0, 1, 0, 4, 0, 1, 3, 4, 0, 1, 0, 4, 3, 1, 4, 0]),
    "borgonona": dict(root=53, mode="ionian", meter=3, bpm=84, lead="flute", accomp="harp", drone=False, perc="frame3",
                      prog=[0, 3, 4, 0, 5, 3, 4, 0, 0, 3, 1, 4, 5, 3, 4, 0]),
    "aragonesa": dict(root=50, mode="aeolian", meter=3, bpm=120, lead="shawm", accomp="oud", drone=False, perc="cast3",
                      prog=[0, 6, 5, 4, 0, 6, 5, 4, 0, 3, 4, 0, 0, 6, 5, 4]),
}


def compose(name, seed, style, kind="map"):
    """Pieza modal en bucle. kind = "map" (exterior, con pulso) o "castle" (interior, más lenta y quieta)."""
    rng = np.random.default_rng(seed)
    key = Key(style["root"], style["mode"])
    prog = style["prog"] if kind == "map" else style["prog"][:12]
    bpm = style["bpm"] if kind == "map" else int(style["bpm"] * 0.72)
    meter = style["meter"]
    tr = Track(bpm=bpm, bars=len(prog), beats_per_bar=meter)
    bpb = tr.bpb
    lead_fn, lead_gain = LEADS[style["lead"]]
    acc_fn = {"harp": harp, "lute": lute, "oud": oud}[style["accomp"]]
    if style.get("drone"):
        tr.add(drone(rng, hz(key.midi(0, -1)), tr.length), 0, 0.045 if kind == "map" else 0.06, -0.1)
        tr.add(drone(rng, hz(key.midi(4, -1)), tr.length), 0, 0.03, 0.1)
    for bar, c in enumerate(prog):
        b0 = bar * bpb
        # Bajo y pulsos del acompañamiento.
        tr.add(acc_fn(rng, hz(key.midi(c, -1)), tr.beat), b0, 0.2, -0.15)
        if kind == "map":
            pattern = [c + 2, c + 4, c + 7, c + 4, c + 2, c + 4] if meter == 3 else [c + 2, c + 4, c + 7, c + 4, c + 2, c + 4, c + 7, c + 9]
            for k, d in enumerate(pattern):
                if k == 0:
                    continue
                tr.add(acc_fn(rng, hz(key.midi(d, 0)), tr.beat * 0.5), b0 + k * 0.5, 0.11, -0.35)
            for onset, acc, inst in PERC[style["perc"]]:
                if onset < bpb:
                    tr.add(_perc(rng, inst, acc), b0 + onset, 0.15, 0.12)
        else:
            for k, d in enumerate([c, c + 4, c + 7][:meter]):
                tr.add(harp(rng, hz(key.midi(d, -1)), tr.beat, decay=2.2), b0 + k, 0.15, -0.25)
        for i, d in enumerate(chord_tones(c)):
            tr.add(pad(rng, hz(key.midi(d, 0)), bpb * tr.beat, attack=0.6 if kind == "map" else 1.2, brightness=3.0),
                   b0, 0.04 if kind == "map" else 0.05, -0.4 + 0.4 * i)
    rest = 0.08 if kind == "map" else 0.22
    mel = melody(rng, prog, bpb, RHYTHMS[meter], 7, 4, 15, rest_chance=rest)
    first_bar = 1 if kind == "map" else 3
    mel = [n for n in mel if n[0] >= first_bar * bpb]
    if len(prog) >= 16:
        mel = phrase_repeat(mel, (first_bar, first_bar + 4), 12, bpb)
    octave = 1 if style["lead"] in ("recorder",) else (-1 if style["lead"] in ("brass", "choir") else 0)
    for beat, length, d in mel:
        tr.add(lead_fn(rng, hz(key.midi(d, octave)), length * tr.beat * 0.92), beat, lead_gain * (0.85 if kind == "castle" else 1.0), 0.25)
    wet = 0.24 if kind == "map" else 0.4
    write_stems(name, {name: tr.render(rng, reverb=2.0 if kind == "map" else 3.2, wet=wet)})


def group_cultures():
    for i, c in enumerate(CULTURES):
        compose("map_" + c, 100 + i, STYLES[c], "map")
        compose("castle_" + c, 200 + i, STYLES[c], "castle")


# --- Contextos sin cultura ---

GENERIC = {
    "map_b": (dict(root=52, mode="ionian", meter=4, bpm=88, lead="flute", accomp="lute", drone=False, perc="frame4",
                   prog=[0, 4, 5, 3, 0, 4, 3, 4, 5, 3, 0, 4, 3, 4, 0, 0]), "map"),
    "castle_b": (dict(root=55, mode="dorian", meter=3, bpm=78, lead="recorder", accomp="harp", drone=True, perc="none",
                      prog=[0, 3, 0, 6, 0, 3, 4, 0, 5, 3, 4, 0]), "castle"),
    "travel_a": (dict(root=55, mode="mixolydian", meter=4, bpm=104, lead="flute", accomp="lute", drone=False, perc="frame4",
                      prog=[0, 0, -1, 0, 3, 0, -1, 0, 0, 3, 4, 0]), "map"),
    "travel_b": (dict(root=50, mode="dorian", meter=3, bpm=108, lead="recorder", accomp="lute", drone=True, perc="tamb3",
                      prog=[0, 3, 0, 4, 0, 3, -1, 0, 0, 3, 4, 0]), "map"),
    "travel_c": (dict(root=57, mode="aeolian", meter=4, bpm=96, lead="shawm", accomp="oud", drone=True, perc="tabor4",
                      prog=[0, 6, 5, 6, 0, 3, 4, 0, 0, 6, 5, 4]), "map"),
    "court_a": (dict(root=53, mode="lydian", meter=3, bpm=80, lead="flute", accomp="harp", drone=False, perc="none",
                     prog=[0, 1, 4, 0, 5, 1, 4, 0, 0, 1, 3, 4, 5, 1, 4, 0]), "castle"),
    "court_b": (dict(root=60, mode="ionian", meter=4, bpm=72, lead="recorder", accomp="harp", drone=False, perc="none",
                     prog=[0, 5, 3, 4, 0, 5, 1, 4, 0, 3, 4, 0, 5, 3, 4, 0]), "castle"),
}


def mourning(name, seed, root, mode):
    rng = np.random.default_rng(seed)
    key = Key(root, mode)
    prog = [0, 5, 3, 4, 0, 5, 6, 0, 3, 4, 0, 0]
    tr = Track(bpm=56, bars=len(prog))
    bpb = tr.bpb
    tr.add(drone(rng, hz(key.midi(0, -2)), tr.length), 0, 0.05, 0.0)
    for bar, c in enumerate(prog):
        for i, d in enumerate(chord_tones(c)):
            tr.add(choir(rng, hz(key.midi(d, 0)), bpb * tr.beat), bar * bpb, 0.06, -0.4 + 0.4 * i)
        tr.add(pad(rng, hz(key.midi(c, -1)), bpb * tr.beat, attack=1.2, brightness=2.0), bar * bpb, 0.08, 0.0)
        if bar % 2 == 0:
            tr.add(bell(rng, hz(key.midi(0, 0))), bar * bpb, 0.12, 0.3)
    mel = melody(rng, prog, bpb, [[(0, 4)], [(0, 3), (3, 1)], [(0, 2), (2, 2)]], 7, 4, 12, rest_chance=0.3)
    for beat, length, d in [n for n in mel if n[0] >= 2 * bpb]:
        tr.add(flute(rng, hz(key.midi(d, 0)), length * tr.beat * 0.95, breath=0.05), beat, 0.08, -0.25)
    write_stems(name, {name: tr.render(rng, reverb=3.8, wet=0.45)})


def captivity(name, seed, root, mode):
    rng = np.random.default_rng(seed)
    key = Key(root, mode)
    prog = [0, 1, 0, 0, 5, 1, 0, 0, 3, 1, 0, 0]
    tr = Track(bpm=58, bars=len(prog))
    bpb = tr.bpb
    tr.add(drone(rng, hz(key.midi(0, -2)), tr.length), 0, 0.07, -0.1)
    for bar, c in enumerate(prog):
        tr.add(pad(rng, hz(key.midi(c, -1)), bpb * tr.beat, attack=1.5, brightness=1.6), bar * bpb, 0.08, 0.0)
        # gotas: notas agudas sueltas con mucho eco
        for _ in range(rng.integers(1, 3)):
            d = c + int(rng.choice([0, 2, 4, 7]))
            tr.add(harp(rng, hz(key.midi(d, 2)), tr.beat * 0.3, decay=1.0, bright=0.6), bar * bpb + float(rng.uniform(0, bpb - 0.5)), 0.07, float(rng.uniform(-0.6, 0.6)))
        if bar % 4 == 3:
            tr.add(war_drum(rng, 0.4), bar * bpb + 3, 0.12, 0.0)
    write_stems(name, {name: tr.render(rng, reverb=4.0, wet=0.5)})


def group_contexts():
    for i, (name, (style, kind)) in enumerate(GENERIC.items()):
        compose(name, 300 + i, style, kind)
    mourning("mourning_a", 401, 50, "aeolian")
    mourning("mourning_b", 402, 52, "phrygian")
    captivity("captivity_a", 411, 45, "phrygian")
    captivity("captivity_b", 412, 47, "aeolian")


# --- Duelos y batallas nuevos (con capa de tensión) ---

def duel_variant(name, seed, root, mode, bpm, ostinato, prog, lead="oud"):
    rng = np.random.default_rng(seed)
    key = Key(root, mode)
    base = Track(bpm=bpm, bars=len(prog))
    tens = Track(bpm=bpm, bars=len(prog))
    bpb = base.bpb
    base.add(drone(rng, hz(key.midi(0, -1)), base.length), 0, 0.05, -0.1)
    pluck = {"oud": oud, "lute": lute, "harp": harp}[lead]
    for bar, c in enumerate(prog):
        for k, d in enumerate(ostinato):
            base.add(pluck(rng, hz(key.midi(c + d, 0)), base.beat * 0.5), bar * bpb + k * 0.5, 0.15 if k % 2 else 0.2, -0.3)
        for i, d in enumerate(chord_tones(c)):
            base.add(pad(rng, hz(key.midi(d, 0)), bpb * base.beat, attack=0.4, brightness=3.0), bar * bpb, 0.035, -0.4 + 0.4 * i)
        for onset, acc in ((0, 1.0), (1, 0.5), (2, 0.8), (2.5, 0.5), (3.5, 0.6)):
            base.add(frame_drum(rng, acc), bar * bpb + onset, 0.2, 0.0)
        for onset, acc in ((0, 1.0), (1, 0.6), (1.75, 0.5), (2, 1.0), (3, 0.6), (3.5, 0.8)):
            tens.add(war_drum(rng, acc), bar * bpb + onset, 0.3, 0.0)
        for onset in (0, 2):
            tens.add(shawm(rng, hz(key.midi(c + 4, 0)), base.beat * 0.9), bar * bpb + onset, 0.07, 0.25)
        for k in range(8):
            tens.add(snare(rng, 0.3 if k % 2 else 0.55), bar * bpb + k * 0.5 + 0.25, 0.06, 0.3)
    write_stems(name, {name: base.render(rng, reverb=1.6, wet=0.2), name + "_tension": tens.render(rng, reverb=1.6, wet=0.2)})


def battle_variant(name, seed, root, mode, bpm, prog):
    rng = np.random.default_rng(seed)
    key = Key(root, mode)
    base = Track(bpm=bpm, bars=len(prog))
    tens = Track(bpm=bpm, bars=len(prog))
    bpb = base.bpb
    for bar, c in enumerate(prog):
        for k in range(8):
            d = c if k % 4 != 3 else c + 4
            base.add(pad(rng, hz(key.midi(d, -1)), base.beat * 0.42, attack=0.01, release=0.12, brightness=4.0), bar * bpb + k * 0.5, 0.1, -0.25)
        for i, d in enumerate(chord_tones(c)):
            base.add(choir(rng, hz(key.midi(d, 0)), bpb * base.beat, attack=0.5), bar * bpb, 0.05, -0.4 + 0.4 * i)
        for onset, acc in ((0, 1.0), (1, 0.5), (2, 0.9), (3, 0.5), (3.5, 0.6)):
            base.add(war_drum(rng, acc), bar * bpb + onset, 0.28, 0.0)
        for k in range(16):
            tens.add(snare(rng, 0.7 if k % 4 == 0 else 0.35), bar * bpb + k * 0.25, 0.08, 0.25)
        for onset in (0, 2):
            for d, g in ((c, 0.1), (c + 4, 0.08)):
                tens.add(horn(rng, hz(key.midi(d, -1)), base.beat * 0.8), bar * bpb + onset, g, 0.15)
    call = [(0, 0.5, 0), (0.5, 0.5, 2), (1, 1, 4), (2, 2, 7)]
    answer = [(0, 1, 7), (1, 0.5, 4), (1.5, 0.5, 2), (2, 2, 0)]
    for bar, motif in ((0, call), (2, answer), (8, call), (10, answer)):
        for onset, length, d in motif:
            base.add(low_brass(rng, hz(key.midi(d, -1)), length * base.beat * 0.95), bar * bpb + onset, 0.13, 0.3)
    write_stems(name, {name: base.render(rng, reverb=2.0, wet=0.25), name + "_tension": tens.render(rng, reverb=2.0, wet=0.25)})


def group_combat():
    duel_variant("duel_b", 501, 57, "aeolian", 120, [0, 2, 1, 0, 4, 2, 1, -1], [0, 0, 5, 6, 0, 0, 3, 4, 0, 0, 5, 6, 3, 4, 0, 0])
    duel_variant("duel_c", 502, 50, "hijaz", 108, [0, 1, 0, 3, 2, 1, 0, -1], [0, 1, 0, 0, 6, 5, 4, 0, 0, 1, 0, 0, 5, 4, 1, 0], lead="lute")
    battle_variant("battle_b", 511, 45, "dorian", 100, [0, 3, 0, 4, 0, 6, 3, 4, 0, 3, 5, 4, 0, 6, 4, 0])
    battle_variant("battle_c", 512, 48, "phrygian", 92, [0, 1, 0, 6, 0, 1, 5, 0, 3, 1, 0, 6, 5, 1, 0, 0])


# --- Fanfarrias (una sola vez, sin bucle) ---

def sting(name, seed, root, notes, drum_roll=True):
    rng = np.random.default_rng(seed)
    key = Key(root, "ionian")
    tr = Track(bpm=100, bars=3)
    if drum_roll:
        for k in range(12):
            tr.add(snare(rng, 0.25 + 0.05 * k), k * 0.125, 0.08, 0.2)
    beat = 1.5
    for onset, length, d in notes:
        for octave, g in ((0, 0.16), (-1, 0.1)):
            tr.add(horn(rng, hz(key.midi(d, octave)), length * tr.beat), beat + onset, g, 0.0)
    end = beat + max(o + l for o, l, _ in notes)
    for i, d in enumerate([0, 2, 4, 7]):
        tr.add(choir(rng, hz(key.midi(d, 0)), 2.2 * tr.beat, attack=0.2, release=1.5), end - 2.0, 0.05, -0.3 + 0.2 * i)
    tr.add(war_drum(rng, 1.0), end - 2.0, 0.35, 0.0)
    tr.add(bell(rng, hz(key.midi(0, 1)), 3.0), end - 2.0, 0.08, 0.3)
    # Sin plegar: una fanfarria termina con su cola de reverberación.
    rendered = _render_oneshot(rng, tr.buf)
    write_stems(name, {name: rendered}, target_rms_db=-16.0)


def _render_oneshot(rng, dry, reverb=2.4, wet=0.3):
    ir_len = int(reverb * SR)
    t = _t(ir_len)
    out = np.zeros((len(dry) + ir_len, 2))
    n = len(out)
    for ch in range(2):
        ir = _noise_band(rng, ir_len, 120, 6000) * np.exp(-t / (reverb / 6.9))
        ir[: int(0.012 * SR)] = 0
        w = np.fft.irfft(np.fft.rfft(dry[:, ch], n) * np.fft.rfft(ir, n), n)
        w /= np.max(np.abs(w)) + 1e-9
        out[:, ch] = wet * w * np.max(np.abs(dry[:, ch]))
        out[: len(dry), ch] += dry[:, ch]
    # recorta el silencio del final
    energy = np.max(np.abs(out), axis=1)
    last = np.nonzero(energy > 1e-4)[0]
    end = int(last[-1]) + 1 if len(last) else len(out)
    out = out[:end]
    fade = min(len(out), int(0.3 * SR))
    out[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return out


def group_stings():
    sting("sting_victory_a", 601, 60, [(0, 0.5, 0), (0.5, 0.5, 2), (1, 0.5, 4), (1.5, 2.5, 7)])
    sting("sting_victory_b", 602, 62, [(0, 0.75, 4), (0.75, 0.25, 4), (1, 1, 7), (2, 2.5, 9)])
    sting("sting_victory_c", 603, 58, [(0, 0.5, 0), (0.5, 0.25, 4), (0.75, 0.25, 4), (1, 0.5, 7), (1.5, 2.5, 11)], drum_roll=False)


# --- Ambientes de lugares (bucles de fondo) ---

def _stereo_add(out, sig, start_s, g, pan):
    s = int(start_s * SR)
    e = min(len(out), s + len(sig))
    if e <= s:
        return
    out[s:e, 0] += sig[: e - s] * g * np.cos((pan + 1) * np.pi / 4)
    out[s:e, 1] += sig[: e - s] * g * np.sin((pan + 1) * np.pi / 4)


def _murmur(rng, n, voices=8):
    """Gentío que habla: ruido con formantes y una modulación silábica distinta por voz."""
    t = _t(n)
    out = np.zeros(n)
    for _ in range(voices):
        rate = rng.uniform(3.0, 5.5)
        syll = np.clip(np.sin(2 * np.pi * rate * t + rng.uniform(0, 6.28)) + rng.uniform(-0.3, 0.4), 0, None) ** 1.5
        phrase = np.clip(np.sin(2 * np.pi * rng.uniform(0.08, 0.2) * t + rng.uniform(0, 6.28)) + 0.3, 0, None)
        lo = rng.uniform(250, 500)
        out += _noise_band(rng, n, lo, lo * 3.2) * syll * phrase
    return out / voices


def _metal(rng, f, dur, decay):
    t = _t(int(dur * SR))
    out = np.zeros_like(t)
    for k, r in enumerate((1.0, 2.31, 3.47, 4.62, 6.13)):
        out += np.sin(2 * np.pi * f * r * rng.uniform(0.99, 1.01) * t) * np.exp(-t / (decay / (1 + 0.45 * k))) / (1 + 0.6 * k)
    return out


def _loop_safe(out, fade_s=1.5):
    """Funde el final con el principio para que el bucle no tenga corte."""
    k = int(fade_s * SR)
    ramp = np.linspace(0, 1, k)[:, None]
    head = out[:k].copy()
    out[:k] = head * ramp + out[-k:] * (1 - ramp)
    return out[:-k]


def amb_castle():
    rng = np.random.default_rng(701)
    length = 34.0
    n = int(length * SR)
    out = np.zeros((n, 2))
    for ch in range(2):
        out[:, ch] = _murmur(rng, n) * 0.45 + _noise_band(rng, n, 60, 250) * 0.08
    # forja a lo lejos: martillo sobre yunque a ritmo de trabajo
    s = 1.0
    while s < length - 1:
        for k in range(rng.integers(3, 7)):
            _stereo_add(out, _metal(rng, rng.uniform(1300, 1500), 0.6, 0.12), s + k * 0.55, 0.05, -0.6)
        s += rng.uniform(5, 9)
    # gallinas / cascos / un perro
    for _ in range(5):
        st = rng.uniform(0, length - 1)
        for k in range(rng.integers(2, 4)):
            tt = _t(int(0.07 * SR))
            clop = np.sin(2 * np.pi * rng.uniform(380, 520) * tt) * np.exp(-tt / 0.012)
            _stereo_add(out, clop, st + k * 0.28, 0.06, rng.uniform(-0.5, 0.5))
    write_stems("amb_castle", {"amb_castle": _loop_safe(out)}, target_rms_db=-25.0)


def _caw(rng):
    dur = rng.uniform(0.25, 0.4)
    t = _t(int(dur * SR))
    f = 420 + 60 * np.sin(np.pi * t / dur)
    sig = np.zeros_like(t)
    for h in range(1, 12):
        g = np.exp(-((f * h - 1400) / 700) ** 2) + 0.2
        sig += g / h * np.sign(np.sin(2 * np.pi * f * h * t))
    sig += 0.4 * _noise_band(rng, len(t), 800, 3000)
    return sig * np.sin(np.pi * t / dur) ** 0.6


def amb_road():
    rng = np.random.default_rng(702)
    length = 36.0
    n = int(length * SR)
    t = _t(n)
    out = np.zeros((n, 2))
    for ch in range(2):
        gust = 0.55 + 0.3 * np.sin(2 * np.pi * t * 2 / length + ch) + 0.15 * np.sin(2 * np.pi * t * 7 / length)
        out[:, ch] = _noise_band(rng, n, 120, 800) * gust * 0.45
    for _ in range(6):
        st = rng.uniform(0, length - 2)
        for k in range(rng.integers(1, 4)):
            _stereo_add(out, _caw(rng), st + k * 0.5, 0.05, rng.uniform(-0.8, 0.8))
    # carreta que cruje
    for _ in range(4):
        st = rng.uniform(0, length - 3)
        for k in range(6):
            tt = _t(int(0.18 * SR))
            creak = np.sin(2 * np.pi * (180 + 90 * tt / 0.18) * tt) * _noise_band(rng, len(tt), 300, 1500) * np.sin(np.pi * tt / 0.18)
            _stereo_add(out, creak, st + k * 0.42, 0.05, -0.3)
    write_stems("amb_road", {"amb_road": _loop_safe(out)}, target_rms_db=-25.0)


def amb_crowd():
    rng = np.random.default_rng(703)
    length = 30.0
    n = int(length * SR)
    t = _t(n)
    out = np.zeros((n, 2))
    for ch in range(2):
        out[:, ch] = _murmur(rng, n, voices=14) * (0.6 + 0.25 * np.sin(2 * np.pi * t * 3 / length + ch))
    # vítores que suben y bajan
    for _ in range(4):
        st = rng.uniform(0, length - 4)
        d = rng.uniform(2.0, 3.5)
        tt = _t(int(d * SR))
        cheer = _noise_band(rng, len(tt), 400, 2600) * np.sin(np.pi * tt / d) ** 2
        _stereo_add(out, cheer, st, 0.35, rng.uniform(-0.3, 0.3))
    write_stems("amb_crowd", {"amb_crowd": _loop_safe(out)}, target_rms_db=-23.0)


def amb_rain():
    rng = np.random.default_rng(704)
    length = 30.0
    n = int(length * SR)
    out = np.zeros((n, 2))
    for ch in range(2):
        out[:, ch] = _noise_band(rng, n, 1500, 9000) * 0.35 + _noise_band(rng, n, 200, 1200) * 0.15
    for _ in range(int(length * 25)):
        tt = _t(int(0.01 * SR))
        drop = _noise_band(rng, len(tt), 2500, 7000) * np.exp(-tt / 0.002)
        _stereo_add(out, drop, rng.uniform(0, length - 0.02), rng.uniform(0.05, 0.2), rng.uniform(-0.9, 0.9))
    write_stems("amb_rain", {"amb_rain": _loop_safe(out)}, target_rms_db=-24.0)


def amb_snow():
    rng = np.random.default_rng(705)
    length = 34.0
    n = int(length * SR)
    t = _t(n)
    out = np.zeros((n, 2))
    for ch in range(2):
        howl_f = 380 + 120 * np.sin(2 * np.pi * t * 3 / length + ch)
        howl = np.sin(2 * np.pi * np.cumsum(howl_f) / SR) * 0.12 * (0.5 + 0.5 * np.sin(2 * np.pi * t * 2 / length + ch))
        out[:, ch] = _noise_band(rng, n, 200, 1400) * (0.5 + 0.35 * np.sin(2 * np.pi * t * 4 / length + 2 * ch)) * 0.5 + howl * 0.4
    write_stems("amb_snow", {"amb_snow": _loop_safe(out)}, target_rms_db=-24.0)


def amb_sea():
    rng = np.random.default_rng(706)
    length = 32.0
    n = int(length * SR)
    t = _t(n)
    out = np.zeros((n, 2))
    period = length / 5
    for ch in range(2):
        swell = np.clip(np.sin(2 * np.pi * (t + ch * 0.6) / period), 0, None) ** 2
        out[:, ch] = _noise_band(rng, n, 80, 1800) * (0.15 + 0.6 * swell) + _noise_band(rng, n, 2000, 7000) * swell ** 3 * 0.2
    for _ in range(5):
        st = rng.uniform(0, length - 1)
        d = rng.uniform(0.25, 0.45)
        tt = _t(int(d * SR))
        gull = np.sin(2 * np.pi * (1800 - 700 * tt / d) * tt) * np.sin(np.pi * tt / d)
        _stereo_add(out, gull, st, 0.04, rng.uniform(-0.8, 0.8))
    write_stems("amb_sea", {"amb_sea": _loop_safe(out)}, target_rms_db=-24.0)


def amb_dungeon():
    rng = np.random.default_rng(707)
    length = 30.0
    n = int(length * SR)
    out = np.zeros((n, 2))
    for ch in range(2):
        out[:, ch] = _noise_band(rng, n, 40, 180) * 0.25
    for _ in range(22):
        tt = _t(int(0.4 * SR))
        drip = np.sin(2 * np.pi * (1200 + 800 * np.exp(-tt * 30)) * tt) * np.exp(-tt / 0.05)
        _stereo_add(out, drip, rng.uniform(0, length - 0.5), 0.1, rng.uniform(-0.7, 0.7))
    for _ in range(3):
        st = rng.uniform(0, length - 2)
        for k in range(5):
            _stereo_add(out, _metal(rng, rng.uniform(2000, 2600), 0.3, 0.04), st + k * 0.07 + rng.uniform(0, 0.04), 0.03, 0.5)
    write_stems("amb_dungeon", {"amb_dungeon": _loop_safe(out)}, target_rms_db=-27.0)


def group_ambience():
    amb_castle()
    amb_road()
    amb_crowd()
    amb_rain()
    amb_snow()
    amb_sea()
    amb_dungeon()


def group_dark():
    mourning("mourning_b", 402, 52, "phrygian")
    captivity("captivity_a", 411, 45, "phrygian")
    captivity("captivity_b", 412, 47, "aeolian")


GROUPS = {"culturas": group_cultures, "contextos": group_contexts, "oscuras": group_dark, "combate": group_combat,
          "fanfarrias": group_stings, "ambientes": group_ambience}


if __name__ == "__main__":
    names = sys.argv[1:] or list(GROUPS)
    for g in names:
        GROUPS[g]()
