"""Genera los efectos de sonido del juego por síntesis (sin muestras externas).

Uso:  python tools/generate_sfx.py
Escribe archivos .wav (44.1 kHz, mono, 16 bits) en assets/sfx/. Cualquiera de ellos
puede reemplazarse por un sonido grabado con el mismo nombre sin tocar el código.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")


# --- Utilidades básicas ---

def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(*tracks, offsets=None):
    """Suma pistas; offsets en segundos para cada una."""
    offsets = offsets or [0.0] * len(tracks)
    length = max(int(o * RATE) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * length
    for t, o in zip(tracks, offsets):
        start = int(o * RATE)
        for i, s in enumerate(t):
            out[start + i] += s
    return out


def gain(track, g):
    return [s * g for s in track]


def normalize(track, peak=0.9):
    m = max(abs(s) for s in track) or 1.0
    return [s * peak / m for s in track]


def fade_out(track, seconds=0.01):
    n = min(len(track), int(seconds * RATE))
    for i in range(n):
        track[len(track) - n + i] *= 1.0 - i / n
    return track


def env_exp(n, decay):
    """Envolvente exponencial: decay = segundos hasta caer a ~1/e."""
    return [math.exp(-i / (decay * RATE)) for i in range(n)]


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * RATE))]


def svf(track, cutoff, q=0.7, mode="band"):
    """Filtro de variable de estado (Chamberlin). cutoff puede ser número o función(t)->Hz."""
    low = band = 0.0
    out = []
    damp = 1.0 / q
    for i, x in enumerate(track):
        fc = cutoff(i / RATE) if callable(cutoff) else cutoff
        f = 2.0 * math.sin(math.pi * min(fc, RATE / 6) / RATE)
        low += f * band
        high = x - low - damp * band
        band += f * high
        out.append(band if mode == "band" else low if mode == "low" else high)
    return out


def tone(freq, seconds, decay, shape="sine", vibrato=0.0):
    """Tono con caída exponencial. freq puede ser función(t)->Hz para barridos."""
    n = int(seconds * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq(t) if callable(freq) else freq
        f *= 1.0 + vibrato * math.sin(2 * math.pi * 5.5 * t)
        phase += 2 * math.pi * f / RATE
        if shape == "sine":
            s = math.sin(phase)
        elif shape == "saw":
            s = 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
        else:  # square suave
            s = math.tanh(3.0 * math.sin(phase))
        out.append(s * math.exp(-t / decay))
    return out


def attack_env(track, seconds):
    n = min(len(track), int(seconds * RATE))
    for i in range(n):
        track[i] *= i / n
    return track


# --- Sonidos ---

def metal_ping(rng, base=1180.0, seconds=0.9, decay=0.22):
    """Resonancia metálica: parciales inarmónicos como una hoja de acero."""
    ratios = [1.0, 2.31, 3.47, 4.62, 6.13]
    parts = []
    for k, r in enumerate(ratios):
        f = base * r * rng.uniform(0.985, 1.015)
        parts.append(gain(tone(f, seconds, decay / (1 + k * 0.45)), 1.0 / (1 + k * 0.6)))
    transient = svf(noise(0.03, rng), 4500, q=0.8, mode="high")
    transient = [s * e for s, e in zip(transient, env_exp(len(transient), 0.006))]
    return mix(*parts, gain(transient, 1.6))


def thump(rng, start=170.0, end=55.0, seconds=0.35):
    body = tone(lambda t: end + (start - end) * math.exp(-t * 30), seconds, 0.09)
    n = noise(seconds, rng)
    n = svf(n, 900, q=0.6, mode="low")
    n = [s * e for s, e in zip(n, env_exp(len(n), 0.03))]
    return mix(body, gain(n, 0.8))


def sfx_clash(rng):
    return mix(metal_ping(rng, 1180), gain(metal_ping(rng, 1530, decay=0.15), 0.6), offsets=[0, 0.012])


def sfx_hit(rng):
    flesh = svf(noise(0.25, rng), 1400, q=0.9)
    flesh = [s * e for s, e in zip(flesh, env_exp(len(flesh), 0.04))]
    return mix(thump(rng), gain(flesh, 1.4), gain(metal_ping(rng, 900, 0.3, 0.05), 0.25))


def sfx_crit(rng):
    boom = thump(rng, 120, 38, 0.8)
    return mix(sfx_clash(rng), gain(sfx_hit(rng), 1.2), gain(boom, 1.3), offsets=[0, 0.01, 0])


def sfx_whoosh(rng, seconds=0.38):
    n = noise(seconds, rng)
    f = svf(n, lambda t: 500 + 2600 * math.sin(math.pi * t / seconds), q=1.6)
    return [s * math.sin(math.pi * i / len(f)) ** 2 for i, s in enumerate(f)]


def sfx_guard(rng):
    # Escudo de madera reforzada: resonancias graves y cortas.
    wood = mix(tone(210, 0.4, 0.06), gain(tone(337, 0.4, 0.045), 0.7), gain(tone(521, 0.4, 0.03), 0.4))
    n = svf(noise(0.15, rng), 1800, q=0.7)
    n = [s * e for s, e in zip(n, env_exp(len(n), 0.015))]
    return mix(wood, gain(n, 1.2), gain(metal_ping(rng, 1650, 0.4, 0.07), 0.2))


def sfx_disarm(rng):
    # La espada sale volando y rebota en el suelo.
    hits = [sfx_clash(rng)]
    offs = [0.0]
    t = 0.32
    for k in range(4):
        hits.append(gain(metal_ping(rng, rng.uniform(1700, 2300), 0.5, 0.06), 0.55 / (k + 1)))
        offs.append(t)
        t += 0.14 / (k + 1) + 0.05
    return mix(gain(sfx_whoosh(rng, 0.3), 0.5), *hits, offsets=[0.02] + offs)


def sfx_push(rng):
    return mix(thump(rng, 120, 45, 0.4), gain(sfx_whoosh(rng, 0.25), 0.5))


def sfx_click(rng):
    t = tone(1900, 0.05, 0.008)
    n = svf(noise(0.02, rng), 3000, q=0.7)
    n = [s * e for s, e in zip(n, env_exp(len(n), 0.003))]
    return mix(gain(t, 0.6), n)


def brass(freq, seconds):
    """Metal de viento simple: diente de sierra filtrado con ataque suave."""
    t = tone(freq, seconds, seconds * 3, shape="saw", vibrato=0.004)
    t = svf(t, freq * 4, q=0.8, mode="low")
    t = attack_env(t, 0.03)
    return fade_out(t, 0.08)


def sfx_victory(rng):
    notes = [(523.25, 0.18), (659.25, 0.18), (783.99, 0.18), (1046.5, 0.7)]
    tracks, offs, t = [], [], 0.0
    for f, d in notes:
        tracks.append(mix(brass(f, d + 0.05), gain(brass(f * 0.5, d + 0.05), 0.5)))
        offs.append(t)
        t += d
    drum = thump(rng, 140, 50, 0.6)
    return mix(*tracks, gain(drum, 0.9), offsets=offs + [t - 0.7])


def sfx_defeat(rng):
    notes = [(392.0, 0.45), (369.99, 0.45), (311.13, 1.1)]
    tracks, offs, t = [], [], 0.0
    for f, d in notes:
        tracks.append(mix(brass(f * 0.5, d + 0.05), gain(brass(f * 0.75, d + 0.05), 0.4)))
        offs.append(t)
        t += d
    drums = [thump(rng, 100, 40, 0.7) for _ in range(3)]
    return mix(*tracks, *drums, offsets=offs + [0.0, 0.45, 0.9])


def sfx_horn(rng):
    # Cuerno de guerra: quinta grave que sube levemente.
    f = lambda t: 146.8 * (1 + 0.04 * min(1.0, t / 0.25))
    a = svf(tone(f, 1.4, 4.0, shape="saw", vibrato=0.006), 700, q=0.9, mode="low")
    b = svf(tone(lambda t: f(t) * 1.5, 1.4, 4.0, shape="saw", vibrato=0.006), 900, q=0.9, mode="low")
    return fade_out(attack_env(mix(a, gain(b, 0.5)), 0.12), 0.35)


def sfx_arrows(rng):
    # Andanada: varias flechas silban y se clavan escalonadas.
    tracks, offs = [], []
    for _ in range(7):
        o = rng.uniform(0.0, 0.25)
        tracks.append(gain(sfx_whoosh(rng, rng.uniform(0.2, 0.3)), 0.35))
        offs.append(o)
        tk = svf(noise(0.06, rng), 2200, q=1.2)
        tk = [s * e for s, e in zip(tk, env_exp(len(tk), 0.01))]
        tracks.append(mix(gain(tk, 0.8), gain(thump(rng, 260, 120, 0.12), 0.4)))
        offs.append(o + 0.24)
    return mix(*tracks, offsets=offs)


def sfx_melee(rng):
    # Choque de pelotones: varios aceros y golpes superpuestos.
    tracks, offs = [], []
    for _ in range(5):
        tracks.append(gain(metal_ping(rng, rng.uniform(950, 1600), 0.6, 0.12), 0.5))
        offs.append(rng.uniform(0.0, 0.35))
    for _ in range(3):
        tracks.append(gain(thump(rng), 0.7))
        offs.append(rng.uniform(0.0, 0.35))
    rumble = svf(noise(0.8, rng), 350, q=0.6, mode="low")
    rumble = [s * math.sin(math.pi * i / len(rumble)) for i, s in enumerate(rumble)]
    tracks.append(gain(rumble, 1.2))
    offs.append(0.0)
    return mix(*tracks, offsets=offs)


def sfx_rout(rng):
    # Pelotón que rompe filas: cuerno que se quiebra hacia abajo.
    f = lambda t: 220 * (1 - 0.35 * min(1.0, t / 0.8))
    h = svf(tone(f, 0.9, 3.0, shape="saw", vibrato=0.015), 800, q=0.9, mode="low")
    return fade_out(attack_env(h, 0.05), 0.3)


SOUNDS = {
    "clash": sfx_clash,
    "hit": sfx_hit,
    "crit": sfx_crit,
    "whoosh": sfx_whoosh,
    "guard": sfx_guard,
    "disarm": sfx_disarm,
    "push": sfx_push,
    "click": sfx_click,
    "victory": sfx_victory,
    "defeat": sfx_defeat,
    "horn": sfx_horn,
    "arrows": sfx_arrows,
    "melee": sfx_melee,
    "rout": sfx_rout,
}

PEAKS = {"click": 0.5, "whoosh": 0.6}


def write_wav(path, track):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in track))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in SOUNDS.items():
        rng = random.Random(name)   # semilla fija: regenerar da el mismo sonido
        track = fade_out(normalize(fn(rng), PEAKS.get(name, 0.9)))
        write_wav(os.path.join(OUT_DIR, name + ".wav"), track)
        print("%-8s %.2fs" % (name, len(track) / RATE))


if __name__ == "__main__":
    main()
