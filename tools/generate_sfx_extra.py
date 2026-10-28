"""Efectos de sonido nuevos: variantes de golpes y sonidos de interfaz y mapa.

Uso:  python tools/generate_sfx_extra.py
Reutiliza los sintetizadores de generate_sfx.py. Escribe en assets/sfx/:
  <sonido>_v1 … _v4   variantes de golpes, paradas, esquivas, gritos… (Sfx elige una al azar)
  month_turn, travel_hop, letter, achievement, level_up, chains, execution, story, plot, shout
Cualquiera puede reemplazarse por un sonido grabado con el mismo nombre.
"""
import importlib.util
import math
import os
import random

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("generate_sfx", os.path.join(_HERE, "generate_sfx.py"))
gs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gs)

RATE = gs.RATE
mix, gain, normalize, fade_out = gs.mix, gs.gain, gs.normalize, gs.fade_out
env_exp, noise, svf, tone, attack_env = gs.env_exp, gs.noise, gs.svf, gs.tone, gs.attack_env
metal_ping, thump, brass = gs.metal_ping, gs.thump, gs.brass

VARIANTS = 4   # sonido_v1 … sonido_v4, además del original


def _env(track, decay):
    return [s * e for s, e in zip(track, env_exp(len(track), decay))]


def sfx_shout(rng):
    """«¡Ha!» sin palabras: sierra con formantes de vocal abierta y un golpe de aire."""
    dur = rng.uniform(0.22, 0.32)
    f0 = rng.uniform(150, 230)
    f = lambda t: f0 * (1.1 - 0.25 * min(1.0, t / dur))
    voice = tone(f, dur, dur * 2, shape="saw", vibrato=0.01)
    a = svf(voice, 750, q=2.2)
    b = svf(voice, 1200, q=2.5)
    c = svf(voice, 2600, q=3.0)
    v = mix(a, gain(b, 0.8), gain(c, 0.3))
    v = attack_env(v, 0.015)
    air = _env(svf(noise(0.12, rng), 1800, q=0.7), 0.03)
    return fade_out(mix(gain(air, 0.6), v), 0.06)


# --- Interfaz y mapa ---

def sfx_month_turn(rng):
    # Pasar página del registro y una campanilla suave.
    swish = svf(noise(0.35, rng), lambda t: 900 + 3000 * math.sin(math.pi * t / 0.35), q=1.2)
    swish = [s * math.sin(math.pi * i / len(swish)) ** 2 for i, s in enumerate(swish)]
    chime = mix(tone(1318.5, 1.0, 0.35), gain(tone(1975.5, 1.0, 0.25), 0.5))
    return mix(gain(swish, 0.8), gain(chime, 0.35), offsets=[0.0, 0.2])


def sfx_travel_hop(rng):
    # Cascos al trote y el crujido de la silla.
    tracks, offs = [], []
    t = 0.0
    for k in range(6):
        clop = mix(tone(rng.uniform(320, 460), 0.1, 0.015), gain(_env(svf(noise(0.05, rng), 2200, q=0.8), 0.008), 0.6))
        tracks.append(gain(clop, 0.9 if k % 2 == 0 else 0.6))
        offs.append(t)
        t += 0.13 if k % 2 == 0 else 0.21
    creak = svf(noise(0.25, rng), lambda x: 500 + 300 * x, q=4.0)
    tracks.append(gain(_env(creak, 0.08), 0.4))
    offs.append(0.3)
    return mix(*tracks, offsets=offs)


def sfx_letter(rng):
    # Pergamino que se despliega y el lacre que se quiebra.
    rustle = svf(noise(0.45, rng), 3200, q=0.6)
    rustle = [s * (0.5 + 0.5 * math.sin(i / RATE * 60)) * math.sin(math.pi * i / len(rustle)) for i, s in enumerate(rustle)]
    crack = mix(_env(svf(noise(0.04, rng), 2500, q=1.0), 0.006), gain(thump(rng, 260, 140, 0.08), 0.4))
    return mix(gain(rustle, 0.6), crack, offsets=[0.0, 0.42])


def sfx_achievement(rng):
    # Fanfarria breve y brillante con campanillas.
    notes = [(659.25, 0.12), (783.99, 0.12), (987.77, 0.12), (1318.5, 0.6)]
    tracks, offs, t = [], [], 0.0
    for f, d in notes:
        tracks.append(mix(brass(f, d + 0.05), gain(tone(f * 2, d + 0.5, 0.3), 0.25)))
        offs.append(t)
        t += d
    sparkle = [gain(tone(rng.uniform(2500, 4200), 0.4, 0.08), 0.15) for _ in range(6)]
    return mix(*tracks, *sparkle, offsets=offs + [t - 0.5 + k * 0.06 for k in range(6)])


def sfx_level_up(rng):
    # Arpa que sube y un brillo final.
    degrees = [0, 4, 7, 12, 16, 19, 24]
    tracks, offs = [], []
    for k, d in enumerate(degrees):
        f = 392.0 * 2 ** (d / 12)
        pl = mix(tone(f, 0.9, 0.35), gain(tone(f * 2, 0.6, 0.18), 0.3), gain(tone(f * 3, 0.4, 0.1), 0.15))
        tracks.append(gain(pl, 0.5))
        offs.append(k * 0.07)
    tracks.append(gain(tone(3135.96, 1.0, 0.4), 0.15))
    offs.append(0.5)
    return mix(*tracks, offsets=offs)


def sfx_chains(rng):
    # Grilletes: eslabones que entrechocan y una cerradura.
    tracks, offs = [], []
    for k in range(10):
        tracks.append(gain(metal_ping(rng, rng.uniform(2200, 3400), 0.25, 0.03), rng.uniform(0.2, 0.5)))
        offs.append(k * 0.045 + rng.uniform(0, 0.03))
    lock = mix(thump(rng, 400, 180, 0.12), gain(metal_ping(rng, 1500, 0.3, 0.05), 0.6))
    tracks.append(lock)
    offs.append(0.7)
    return mix(*tracks, offsets=offs)


def sfx_execution(rng):
    # Redoble de tambor y golpe seco.
    tracks, offs = [], []
    n = 22
    for k in range(n):
        hit = _env(svf(noise(0.08, rng), 2600, q=0.7), 0.02)
        tracks.append(gain(mix(hit, gain(tone(190, 0.08, 0.02), 0.5)), 0.25 + 0.5 * k / n))
        offs.append(k * 0.055)
    tracks.append(gain(thump(rng, 110, 32, 1.1), 1.6))
    offs.append(n * 0.055 + 0.25)
    return mix(*tracks, offsets=offs)


def sfx_story(rng):
    # Campana grave lejana: empieza un capítulo.
    ratios = [(0.5, 0.5, 2.0), (1.0, 1.0, 1.6), (1.19, 0.4, 1.0), (1.5, 0.35, 0.8), (2.0, 0.3, 0.6)]
    parts = [gain(tone(220 * r, 2.5, d), a) for r, a, d in ratios]
    return mix(*parts)


def sfx_plot(rng):
    # Intriga: cuerda grave pellizcada y un susurro.
    pluck = mix(tone(110, 1.2, 0.5), gain(tone(116.5, 1.2, 0.45), 0.6), gain(tone(220, 0.8, 0.2), 0.3))
    whisper = svf(noise(0.7, rng), 2600, q=1.5)
    whisper = [s * math.sin(math.pi * i / len(whisper)) ** 2 for i, s in enumerate(whisper)]
    return mix(gain(pluck, 0.8), gain(whisper, 0.25), offsets=[0.0, 0.15])


NEW_SOUNDS = {
    "shout": sfx_shout,
    "month_turn": sfx_month_turn,
    "travel_hop": sfx_travel_hop,
    "letter": sfx_letter,
    "achievement": sfx_achievement,
    "level_up": sfx_level_up,
    "chains": sfx_chains,
    "execution": sfx_execution,
    "story": sfx_story,
    "plot": sfx_plot,
}

# Sonidos con variantes (las originales siguen como «_v0» implícita).
VARIED = {
    "hit": gs.sfx_hit, "clash": gs.sfx_clash, "crit": gs.sfx_crit, "whoosh": gs.sfx_whoosh, "guard": gs.sfx_guard,
    "push": gs.sfx_push, "melee": gs.sfx_melee, "arrows": gs.sfx_arrows, "shout": sfx_shout,
}

PEAKS = {"whoosh": 0.6, "month_turn": 0.55, "travel_hop": 0.6, "letter": 0.6, "story": 0.6, "plot": 0.6, "shout": 0.7}


# Cada variante suena algo más grave o aguda y más apagada o brillante (fijo por variante).
VARIANT_PITCH = [0.9, 1.07, 0.96, 1.13]
VARIANT_TONE = [1600, None, 3200, None]   # corte de un paso bajo suave; None = sin filtrar


def _resample(track, factor):
    """Cambia tono y duración a la vez (como acelerar o frenar la cinta)."""
    n = int(len(track) / factor)
    out = []
    for i in range(n):
        x = i * factor
        j = int(x)
        frac = x - j
        a = track[j]
        b = track[j + 1] if j + 1 < len(track) else 0.0
        out.append(a + (b - a) * frac)
    return out


def _vary(track, v):
    track = _resample(track, VARIANT_PITCH[(v - 1) % len(VARIANT_PITCH)])
    cutoff = VARIANT_TONE[(v - 1) % len(VARIANT_TONE)]
    if cutoff:
        track = mix(gain(svf(track, cutoff, q=0.5, mode="low"), 0.7), gain(track, 0.3))
    return track


def _write(name, track):
    track = fade_out(normalize(track, PEAKS.get(name.split("_v")[0], 0.9)))
    gs.write_wav(os.path.join(gs.OUT_DIR, name + ".wav"), track)
    print("%-16s %.2fs" % (name, len(track) / RATE))


def main():
    os.makedirs(gs.OUT_DIR, exist_ok=True)
    for name, fn in NEW_SOUNDS.items():
        _write(name, fn(random.Random(name)))
    for name, fn in VARIED.items():
        for v in range(1, VARIANTS + 1):
            _write("%s_v%d" % (name, v), _vary(fn(random.Random("%s_v%d" % (name, v))), v))


if __name__ == "__main__":
    main()
