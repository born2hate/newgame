"""Синтез всех звуков и музыки игры. Запуск: python3 tools/make_audio.py
Нужны numpy, scipy, soundfile. Результат — OGG в audio/sfx и audio/music."""
import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
rng = np.random.default_rng(7)
OUT = "audio"


def t_(dur):
    return np.arange(int(dur * SR)) / SR


def env(n, a=0.005, d=0.1, s=0.0, r=0.05, hold=0.0):
    """ADSR-огибающая длиной n сэмплов."""
    a_n, d_n, h_n, r_n = int(a * SR), int(d * SR), int(hold * SR), int(r * SR)
    e = np.concatenate([
        np.linspace(0, 1, max(a_n, 1)),
        np.linspace(1, s, max(d_n, 1)),
        np.full(h_n, s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    if len(e) < n:
        e = np.concatenate([e, np.zeros(n - len(e))])
    return e[:n]


def expdecay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def lowpass(x, fc, order=2):
    b, a = signal.butter(order, min(fc / (SR / 2), 0.99), "low")
    return signal.lfilter(b, a, x)


def highpass(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band")
    return signal.lfilter(b, a, x)


def sweep(f0, f1, dur, curve=1.0):
    """Синус с плавным изменением частоты."""
    t = t_(dur)
    k = (t / dur) ** curve
    f = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def bell(freq, dur, bright=1.0, tau=0.6):
    """FM-колокольчик."""
    t = t_(dur)
    mod = np.sin(2 * np.pi * freq * 3.5 * t) * bright * 2.0 * np.exp(-t / (tau * 0.3))
    car = np.sin(2 * np.pi * freq * t + mod)
    return car * np.exp(-t / tau) * env(len(t), a=0.002, d=0.0, s=1.0, r=0.01, hold=dur)


def marimba(freq, dur=0.8):
    t = t_(dur)
    x = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.35)
    x += 0.35 * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-t / 0.05)
    x += 0.15 * np.sin(2 * np.pi * freq * 10 * t) * np.exp(-t / 0.015)
    return x * env(len(t), a=0.003, d=0, s=1, r=0.02, hold=dur)


def bubble(f0=400, f1=1200, dur=0.09):
    t = t_(dur)
    k = t / dur
    f = f0 * (f1 / f0) ** k
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * k) ** 0.6
    return x


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def place(buf, x, at):
    i = int(at * SR)
    end = min(len(buf), i + len(x))
    buf[i:end] += x[: end - i]
    return buf


_ir_cache = {}


def reverb(x, decay=1.6, mix=0.3, tone=5000, stereo=True):
    key = (decay, tone)
    if key not in _ir_cache:
        n = int(decay * 1.5 * SR)
        irs = []
        for _ in range(2):
            ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (decay / 6.9 * SR))
            ir = lowpass(ir, tone)
            ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
            irs.append(ir / np.sqrt(np.sum(ir ** 2)))
        _ir_cache[key] = irs
    irs = _ir_cache[key]
    tail = len(irs[0])
    dry = np.concatenate([x, np.zeros(tail)])
    chans = []
    for ir in irs if stereo else irs[:1]:
        wet = signal.fftconvolve(x, ir)
        wet = np.pad(wet, (0, max(0, len(dry) - len(wet))))[: len(dry)]
        chans.append(dry * (1 - mix) + wet * mix * 1.4)
    return np.stack(chans, axis=1) if stereo else chans[0]


def trim_silence(x, thr=1e-4):
    mono = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=1)
    idx = np.where(mono > thr)[0]
    return x[: idx[-1] + int(0.02 * SR)] if len(idx) else x


def save(name, x, peak_db=-3.0, folder="sfx"):
    x = trim_silence(x)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * 10 ** (peak_db / 20)
    fade = int(0.005 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)[:, None] if x.ndim == 2 else np.linspace(1, 0, fade)
    # libsndfile падает на больших буферах Vorbis — пишем кусками
    x = x.astype(np.float32)
    ch = 1 if x.ndim == 1 else x.shape[1]
    with sf.SoundFile(f"{OUT}/{folder}/{name}.ogg", "w", SR, ch, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(x), 8192):
            f.write(x[i:i + 8192])
    print(f"{folder}/{name}.ogg  {len(x) / SR:.2f}s")


def note(n):
    """MIDI -> Гц."""
    return 440.0 * 2 ** ((n - 69) / 12)


# ---------------------------------------------------------------- UI

def sfx_tap():
    x = sweep(1500, 900, 0.045, 0.5) * expdecay(int(0.045 * SR), 0.012)
    click = highpass(noise(0.006), 2500) * expdecay(int(0.006 * SR), 0.0015)
    x = place(x, click * 0.3, 0)
    save("tap", reverb(x, 0.4, 0.12), -8)


def sfx_open():
    b = np.zeros(int(0.35 * SR))
    place(b, bubble(300, 700, 0.08), 0)
    place(b, bubble(450, 1100, 0.07) * 0.8, 0.06)
    save("open", reverb(b, 0.8, 0.25), -8)


def sfx_close():
    b = np.zeros(int(0.3 * SR))
    place(b, bubble(900, 400, 0.08), 0)
    save("close", reverb(b, 0.6, 0.2), -10)


def sfx_error():
    t = t_(0.28)
    x = np.zeros(len(t))
    for i, f in enumerate([220, 165]):
        seg = t_(0.12)
        sq = signal.square(2 * np.pi * f * seg) * 0.5 + np.sin(2 * np.pi * f * seg)
        place(x, lowpass(sq, 1200) * env(len(seg), 0.005, 0.1, 0.0, 0.01), i * 0.13)
    save("error", reverb(x, 0.5, 0.15), -6)


# ---------------------------------------------------------------- игровые события

def sfx_collect():
    b = np.zeros(int(1.2 * SR))
    for i, (f0, f1) in enumerate([(350, 900), (420, 1100), (500, 1400)]):
        place(b, bubble(f0, f1, 0.07) * (0.9 - i * 0.15), i * 0.045)
    place(b, bell(note(84), 0.9, 0.6, 0.35) * 0.45, 0.1)
    place(b, bell(note(91), 0.9, 0.6, 0.3) * 0.3, 0.16)
    save("collect", reverb(b, 1.2, 0.3))


def sfx_pearls():
    b = np.zeros(int(1.4 * SR))
    for i, n in enumerate([88, 91, 96, 100]):
        place(b, bell(note(n), 1.0, 0.9, 0.3) * (0.6 - i * 0.08), i * 0.05)
    save("pearls", reverb(b, 1.4, 0.35))


def sfx_build():
    b = np.zeros(int(1.4 * SR))
    thud = lowpass(noise(0.25), 180) * expdecay(int(0.25 * SR), 0.06) * 3
    thud += np.sin(2 * np.pi * np.cumsum(np.linspace(110, 45, int(0.25 * SR))) / SR) * expdecay(int(0.25 * SR), 0.08)
    place(b, thud, 0)
    t = t_(0.9)
    clank = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / tau) * a
                for f, tau, a in [(523, 0.3, 0.5), (1187, 0.2, 0.4), (1873, 0.12, 0.3), (2711, 0.07, 0.25), (3637, 0.05, 0.2)])
    place(b, clank * 0.5, 0.01)
    for i in range(4):
        tick = bandpass(noise(0.015), 1500, 5000) * expdecay(int(0.015 * SR), 0.003)
        place(b, tick * 0.4, 0.35 + i * 0.07)
    place(b, bell(note(79), 0.8, 0.5, 0.3) * 0.35, 0.62)
    place(b, bell(note(86), 0.8, 0.5, 0.3) * 0.3, 0.7)
    save("build", reverb(b, 1.3, 0.3))


def sfx_upgrade():
    b = np.zeros(int(1.8 * SR))
    for i, n in enumerate([72, 76, 79, 84, 88]):
        place(b, bell(note(n), 1.1, 0.7, 0.4) * 0.55, i * 0.075)
    sh = highpass(noise(0.9), 6000) * env(int(0.9 * SR), 0.3, 0.0, 1.0, 0.5, 0.1) * 0.06
    place(b, sh, 0.1)
    save("upgrade", reverb(b, 1.8, 0.35))


def sfx_levelup():
    b = np.zeros(int(1.6 * SR))
    for i, n in enumerate([79, 83, 86, 91]):
        place(b, marimba(note(n), 0.6) * 0.6, i * 0.06)
    place(b, bell(note(95), 1.2, 0.8, 0.5) * 0.4, 0.26)
    save("levelup", reverb(b, 1.6, 0.35))


def sfx_crate():
    b = np.zeros(int(2.4 * SR))
    creak_t = t_(0.35)
    f = 90 + 40 * np.sin(2 * np.pi * 3 * creak_t) + creak_t * 60
    creak = signal.sawtooth(2 * np.pi * np.cumsum(f) / SR)
    creak = bandpass(creak, 300, 1800) * env(len(creak_t), 0.03, 0.0, 1.0, 0.1, 0.2) * 0.35
    place(b, creak, 0)
    whoosh = bandpass(noise(0.6), 400, 3000) * env(int(0.6 * SR), 0.35, 0.0, 1.0, 0.25, 0.0) * 0.5
    place(b, whoosh, 0.2)
    for i, n in enumerate([72, 76, 79, 84]):
        place(b, bell(note(n), 1.6, 0.6, 0.7) * 0.45, 0.55 + i * 0.02)
    for i in range(18):
        place(b, bell(note(rng.integers(88, 104)), 0.5, 1.0, 0.12) * 0.18, 0.6 + rng.random() * 0.9)
    save("crate", reverb(b, 2.0, 0.35))


def sfx_reward():
    b = np.zeros(int(2.2 * SR))
    seq = [(67, 0), (72, 0.12), (76, 0.24), (79, 0.36)]
    for n, at in seq:
        place(b, marimba(note(n), 0.5) * 0.5, at)
    for n in [72, 76, 79, 84]:
        place(b, bell(note(n), 1.6, 0.5, 0.8) * 0.3, 0.5)
    bass = np.sin(2 * np.pi * note(48) * t_(1.2)) * expdecay(int(1.2 * SR), 0.5) * 0.5
    place(b, bass, 0.5)
    save("reward", reverb(b, 2.0, 0.35))


def sfx_purchase():
    b = np.zeros(int(2.0 * SR))
    for i in range(24):
        n = [84, 88, 91, 96, 100, 103][i % 6]
        place(b, bell(note(n), 0.6, 1.0, 0.15) * 0.25, i * 0.035)
    for n in [72, 79, 84, 88]:
        place(b, bell(note(n), 1.5, 0.5, 0.7) * 0.3, 0.1)
    save("purchase", reverb(b, 1.8, 0.4))


def sfx_alarm():
    b = np.zeros(int(1.6 * SR))
    for k in range(2):
        tt = t_(0.55)
        f = 620 + 280 * np.sin(np.pi * tt / 0.55)
        s = signal.square(2 * np.pi * np.cumsum(f) / SR) * 0.4 + np.sin(2 * np.pi * np.cumsum(f) / SR)
        place(b, lowpass(s, 2500) * env(len(tt), 0.02, 0.0, 1.0, 0.05, 0.45), k * 0.6)
    hiss = highpass(noise(1.2), 2000) * env(int(1.2 * SR), 0.01, 0.3, 0.3, 0.6, 0.2) * 0.25
    place(b, hiss, 0)
    save("alarm", reverb(b, 1.0, 0.25), -4)


def sfx_arrive():
    b = np.zeros(int(1.8 * SR))
    hiss = bandpass(noise(0.7), 1500, 8000) * env(int(0.7 * SR), 0.01, 0.6, 0.0, 0.05) * 0.5
    place(b, hiss, 0)
    for i, n in enumerate([76, 81]):
        place(b, bell(note(n), 1.2, 0.5, 0.6) * 0.5, 0.45 + i * 0.18)
    save("arrive", reverb(b, 1.6, 0.35))


def sfx_sonar():
    b = np.zeros(int(3.0 * SR))
    ping = np.sin(2 * np.pi * 1320 * t_(0.6)) * env(int(0.6 * SR), 0.004, 0.0, 1.0, 0.4, 0.05)
    place(b, ping * 0.7, 0)
    place(b, ping * 0.25, 0.7)
    place(b, ping * 0.1, 1.4)
    save("sonar", reverb(b, 2.5, 0.5, tone=3000))


def sfx_launch():
    b = np.zeros(int(3.0 * SR))
    tt = t_(2.2)
    f = 45 + 50 * (tt / 2.2) ** 1.5
    eng = signal.sawtooth(2 * np.pi * np.cumsum(f) / SR) + 0.6 * np.sin(2 * np.pi * np.cumsum(f * 0.5) / SR)
    eng = lowpass(eng, 400) * env(len(tt), 0.3, 0.0, 1.0, 1.0, 0.9) * 0.6
    place(b, eng, 0)
    wh = bandpass(noise(1.5), 200, 1500) * env(int(1.5 * SR), 0.6, 0.0, 1.0, 0.8, 0.1) * 0.4
    place(b, wh, 0.6)
    for i in range(20):
        place(b, bubble(rng.uniform(250, 600), rng.uniform(800, 1800), 0.06) * 0.25, 0.4 + rng.random() * 1.8)
    ping = np.sin(2 * np.pi * 1320 * t_(0.5)) * env(int(0.5 * SR), 0.004, 0.0, 1.0, 0.35, 0.05)
    place(b, ping * 0.35, 1.9)
    save("launch", reverb(b, 2.0, 0.35, tone=3500))


def sfx_bubbles():
    b = np.zeros(int(1.0 * SR))
    for i in range(7):
        place(b, bubble(rng.uniform(300, 600), rng.uniform(900, 1600), rng.uniform(0.05, 0.09)) * 0.5, rng.random() * 0.6)
    save("bubbles", reverb(b, 1.0, 0.3), -8)


# ---------------------------------------------------------------- фон и музыка

def ambient_loop(dur=40.0):
    n = int(dur * SR)
    brown = np.cumsum(rng.standard_normal(n + SR))
    brown = highpass(brown, 20)[SR:]
    brown = lowpass(brown, 260) / np.std(brown)
    lfo = 0.7 + 0.3 * np.sin(2 * np.pi * np.arange(n) / SR / 9.0)
    base = brown * lfo * 0.35
    out = np.stack([base, np.roll(base, 3000)], axis=1)
    for _ in range(int(dur * 1.2)):
        bb = bubble(rng.uniform(250, 500), rng.uniform(700, 1500), rng.uniform(0.05, 0.1)) * rng.uniform(0.04, 0.12)
        pan = rng.random()
        at = rng.random() * (dur - 0.2)
        i = int(at * SR)
        out[i:i + len(bb), 0] += bb * (1 - pan)
        out[i:i + len(bb), 1] += bb * pan
    for _ in range(3):
        tt = t_(3.0)
        f = rng.uniform(90, 140) + 40 * np.sin(np.pi * tt / 3.0)
        w = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / 3.0) ** 2 * 0.05
        at = rng.random() * (dur - 3)
        i = int(at * SR)
        out[i:i + len(w)] += w[:, None]
    return make_seamless(out, 2.0)


def make_seamless(x, xfade):
    """Хвост переносим в начало с кроссфейдом — петля без щелчка."""
    k = int(xfade * SR)
    head, body, tail = x[:k], x[k:-k], x[-k:]
    ramp = np.linspace(0, 1, k)[:, None] if x.ndim == 2 else np.linspace(0, 1, k)
    return np.concatenate([tail * (1 - ramp) + head * ramp, body])


def pad_voice(freq, dur, detune=0.006):
    t = t_(dur)
    x = np.zeros(len(t))
    for d in (-detune, 0, detune):
        f = freq * (1 + d)
        for h in range(1, 9):
            x += np.sin(2 * np.pi * f * h * t + rng.random() * 6.28) / h
    return x


def music_loop():
    bpm = 72
    beat = 60 / bpm
    bar = beat * 4
    # Am9 - Fmaj7 - Cmaj7 - G6 (по 2 такта), дважды; во второй раз — выше мелодия
    chords = [
        ([45, 57, 60, 64, 67, 71], 45),
        ([41, 57, 60, 64, 65, 69], 41),
        ([48, 55, 59, 60, 64, 67], 48),
        ([43, 55, 59, 62, 64, 67], 43),
    ]
    bars = 16
    total = bars * bar
    L = np.zeros(int((total + 4) * SR))
    R = np.zeros_like(L)
    pent = [57, 60, 62, 64, 67, 69, 72, 74, 76, 79]
    for rep in range(2):
        for ci, (notes, root) in enumerate(chords):
            start = (rep * 8 + ci * 2) * bar
            dur = 2 * bar
            # пэд
            pad = np.zeros(int((dur + 1.5) * SR))
            for n in notes[1:]:
                pad[: int(dur * SR)] += pad_voice(note(n), dur) * 0.12
            pad = lowpass(pad, 900 + 300 * rep) * env(len(pad), 1.2, 0.0, 1.0, 1.5, dur - 1.2)
            place(L, pad, start)
            place(R, np.roll(pad, 400), start)
            # бас
            for b in range(2):
                bs = np.sin(2 * np.pi * note(root - 12) * t_(bar)) + 0.3 * np.sin(2 * np.pi * note(root) * t_(bar))
                bs *= env(len(bs), 0.05, 0.4, 0.6, 0.5, bar - 1.0) * 0.35
                place(L, bs, start + b * bar)
                place(R, bs, start + b * bar)
            # арпеджио маримбы восьмыми
            chord_pcs = {n % 12 for n in notes}
            for step in range(16):
                if rng.random() < (0.35 if rep == 0 else 0.2):
                    continue
                cand = [p for p in pent if p % 12 in chord_pcs] or pent
                n = cand[rng.integers(len(cand))] + (12 if rep == 1 and rng.random() < 0.4 else 0)
                vel = rng.uniform(0.18, 0.32)
                m = marimba(note(n), 0.9) * vel
                at = start + step * beat / 2 + rng.uniform(-0.008, 0.008)
                pan = rng.uniform(0.25, 0.75)
                place(L, m * (1 - pan), at)
                place(R, m * pan, at)
            # колокольчик на сильную долю каждые 2 такта
            bl = bell(note(notes[-1] + 12), 2.5, 0.4, 1.2) * 0.12
            place(L, bl, start)
            place(R, bl, start + 0.01)
    st = np.stack([L, R], axis=1)
    wetL = reverb(st[:, 0], 3.0, 0.35, tone=4500, stereo=False)
    wetR = reverb(st[:, 1], 3.0, 0.35, tone=4500, stereo=False)
    n = min(len(wetL), len(wetR))
    mix = np.stack([wetL[:n], wetR[:n]], axis=1)
    loop_n = int(total * SR)
    body, tail = mix[:loop_n].copy(), mix[loop_n:]
    body[: len(tail)] += tail[: loop_n]
    return body



# ---------------------------------------------------------------- бои, налёты, семья

def sfx_hit():
    b = np.zeros(int(0.5 * SR))
    th = np.sin(2 * np.pi * np.cumsum(np.linspace(180, 60, int(0.18 * SR))) / SR) * env(int(0.18 * SR), 0.002, 0.15, 0.0, 0.02)
    place(b, th * 0.9, 0)
    cr = bandpass(noise(0.08), 1500, 6000) * env(int(0.08 * SR), 0.001, 0.07, 0.0, 0.01) * 0.6
    place(b, cr, 0)
    save("hit", reverb(b, 0.6, 0.15), -5)


def sfx_roar():
    dur = 2.2
    tt = t_(dur)
    f = 70 + 25 * np.sin(2 * np.pi * 3.5 * tt) + 30 * np.exp(-tt * 2)
    gr = signal.sawtooth(2 * np.pi * np.cumsum(f) / SR) + 0.5 * signal.sawtooth(2 * np.pi * np.cumsum(f * 1.5) / SR)
    gr = lowpass(gr, 700) * env(len(tt), 0.15, 0.0, 1.0, 0.8, dur - 1.0)
    rumble = lowpass(noise(dur), 300) * env(len(tt), 0.2, 0.0, 1.0, 0.8, dur - 1.0) * 1.5
    x = gr * 0.6 + rumble
    for i in range(14):
        place(x, bubble(rng.uniform(150, 350), rng.uniform(500, 900), 0.08) * 0.2, rng.random() * 1.8)
    save("roar", reverb(x, 2.2, 0.4, tone=2000), -3)


def sfx_horn():
    b = np.zeros(int(2.4 * SR))
    for k, n in enumerate([50, 50, 53]):
        tt = t_(0.6 if k < 2 else 1.0)
        f = note(n) * (1 + 0.01 * np.sin(2 * np.pi * 5 * tt))
        s = signal.sawtooth(2 * np.pi * np.cumsum(f) / SR) + 0.5 * signal.square(2 * np.pi * np.cumsum(f * 0.5) / SR)
        place(b, lowpass(s, 1400) * env(len(tt), 0.05, 0.0, 1.0, 0.2, len(tt) / SR - 0.3) * 0.5, k * 0.65)
    save("horn", reverb(b, 1.8, 0.35, tone=3000), -4)


def sfx_combo():
    # короткий яркий щипок; высоту поднимает игра (pitch) с каждым сбором подряд
    b = np.zeros(int(0.6 * SR))
    place(b, marimba(note(84), 0.5) * 0.6, 0)
    place(b, bell(note(96), 0.4, 0.8, 0.25) * 0.25, 0.01)
    save("combo", reverb(b, 0.8, 0.2), -6)


def sfx_coin():
    b = np.zeros(int(0.25 * SR))
    place(b, bell(note(100), 0.2, 1.0, 0.08) * 0.5, 0)
    save("coin", b, -12)


def sfx_birth():
    b = np.zeros(int(2.6 * SR))
    for i, n in enumerate([72, 76, 79, 84, 79, 84]):
        place(b, bell(note(n), 1.4, 0.4, 0.8) * 0.35, i * 0.22)
    save("birth", reverb(b, 2.4, 0.45))


def sfx_repair():
    b = np.zeros(int(1.0 * SR))
    for i in range(3):
        cl = bandpass(noise(0.06), 1800, 7000) * env(int(0.06 * SR), 0.001, 0.05, 0.0, 0.01)
        ring = bell(rng.uniform(1700, 2300), 0.3, 1.0, 0.1) * 0.3
        place(b, cl * 0.7 + np.pad(ring, (0, max(0, len(cl) - len(ring))))[:len(cl)], i * 0.18)
        place(b, ring, i * 0.18)
    place(b, bell(note(84), 0.6, 0.5, 0.3) * 0.3, 0.6)
    save("repair", reverb(b, 0.9, 0.2), -5)


def danger_loop():
    """Тревожная тема на время налётов и боссов: пульс баса и стаккато."""
    bpm = 120
    beat = 60 / bpm
    bars = 8
    total = bars * 4 * beat
    x = np.zeros(int((total + 2) * SR))
    roots = [45, 45, 46, 44]
    for bi in range(bars):
        root = roots[bi % 4]
        for st in range(8):
            at = (bi * 4 + st * 0.5) * beat
            bs = signal.sawtooth(2 * np.pi * note(root - 12) * t_(beat * 0.45))
            bs = lowpass(bs, 500) * env(len(bs), 0.005, 0.15, 0.3, 0.05, 0.05) * (0.5 if st % 2 else 0.7)
            place(x, bs, at)
        hit = lowpass(noise(0.25), 200) * env(int(0.25 * SR), 0.002, 0.2, 0.0, 0.02) * 1.2
        place(x, hit, bi * 4 * beat)
        place(x, hit * 0.7, (bi * 4 + 2) * beat)
        for st in [1, 3]:
            hh = highpass(noise(0.05), 6000) * env(int(0.05 * SR), 0.001, 0.04, 0.0, 0.01) * 0.25
            place(x, hh, (bi * 4 + st) * beat)
        if bi % 2 == 1:
            st_n = [root + 12, root + 15, root + 13, root + 12][bi % 4]
            for k in range(4):
                tt = t_(beat * 0.3)
                s = signal.square(2 * np.pi * note(st_n) * tt) * env(len(tt), 0.005, 0.2, 0.0, 0.05) * 0.18
                place(x, lowpass(s, 2500), (bi * 4 + k) * beat)
    wet = reverb(x, 1.5, 0.25, tone=4000, stereo=False)
    loop_n = int(total * SR)
    body, tail = wet[:loop_n].copy(), wet[loop_n:]
    body[: len(tail)] += tail[: loop_n]
    return np.stack([body, body], axis=1)

if __name__ == "__main__":
    for fn in [sfx_tap, sfx_open, sfx_close, sfx_error, sfx_collect, sfx_pearls, sfx_build, sfx_upgrade,
               sfx_levelup, sfx_crate, sfx_reward, sfx_purchase, sfx_alarm, sfx_arrive, sfx_sonar,
               sfx_launch, sfx_bubbles, sfx_hit, sfx_roar, sfx_horn, sfx_combo, sfx_coin, sfx_birth, sfx_repair]:
        fn()
    save("ambient", ambient_loop(), -12, folder="music")
    save("theme", music_loop(), -6, folder="music")
    save("danger", danger_loop(), -6, folder="music")
