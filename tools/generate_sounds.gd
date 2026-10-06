# Synthétise les sons du jeu dans res://sounds/ (fichiers .wav remplaçables par de vrais enregistrements).
# Lancer : Godot --headless --path . --script res://tools/generate_sounds.gd
# puis    : Godot --headless --path . --import
extends SceneTree

const RATE := 22050

var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = 20261006  # mêmes sons à chaque génération
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://sounds"))
	for i in 5:
		_save("flop_%d" % (i + 1), _flop(i))
		_save("flush_%d" % (i + 1), _flush(i))
		_save("slap_%d" % (i + 1), _slap(i))
	for i in 3:
		_save("grunt_%d" % (i + 1), _grunt(i))
	_save("heartbeat", _heartbeat())
	_save("defeat", _defeat())
	_save("victory", _victory())
	_save("buzz", _buzz())
	_save("nervous_cry", _nervous_cry())
	print("Sons générés dans res://sounds/")
	quit()


# --- Sons ----------------------------------------------------------------------

# « Flop » : carte qui tombe à plat sur la table. Claquement de bruit sourd + petit choc grave.
func _flop(v: int) -> PackedFloat32Array:
	var out := _buffer(0.14)
	var lp := _lowpass(1100.0 + v * 450.0)
	var thump_freq := 140.0 + v * 22.0
	var tau := 0.018 + v * 0.004
	for i in out.size():
		var t := float(i) / RATE
		var env := (1.0 - exp(-t / 0.0015)) * exp(-t / tau)
		var noise := lp.call(rng.randf_range(-1.0, 1.0)) as float
		var thump := sin(TAU * thump_freq * t * (1.0 - t * 2.5)) * exp(-t / 0.028)
		out[i] = noise * env * 1.6 + thump * 0.55
	return out


# « Flushhh » : carte qui glisse sur le tapis. Souffle filtré qui monte vite puis s'éteint.
func _flush(v: int) -> PackedFloat32Array:
	var duration := 0.32 + v * 0.07
	var out := _buffer(duration)
	var low := _lowpass(700.0 + v * 120.0)    # retiré du bruit : passe-haut
	var high := _lowpass(2600.0 + v * 700.0)
	var grain := 26.0 + v * 9.0
	for i in out.size():
		var t := float(i) / RATE
		var u := t / duration
		var noise := rng.randf_range(-1.0, 1.0)
		var band := high.call(noise - (low.call(noise) as float)) as float
		var env := sin(PI * 0.5 * minf(u * 5.0, 1.0)) * pow(1.0 - u, 1.7)
		out[i] = band * env * (0.85 + 0.15 * sin(TAU * grain * t))
	return out


# « Boum » + « plarf » : la main qui s'écrase sur le tas. Choc grave + claque de peau.
func _slap(v: int) -> PackedFloat32Array:
	var out := _buffer(0.4)
	var boom_weight: float = [1.0, 0.8, 0.45, 0.3, 0.65][v]
	var smack_weight: float = [0.4, 0.7, 1.0, 1.2, 0.9][v]
	var lp := _lowpass(3200.0 - v * 350.0)
	var lp2 := _lowpass(1800.0)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += TAU * (48.0 + v * 6.0 + 55.0 * exp(-t / 0.04)) / RATE
		var boom := sin(phase) * exp(-t / 0.09)
		var noise := rng.randf_range(-1.0, 1.0)
		var smack := (lp.call(noise) as float) * exp(-t / 0.011)
		var t2 := maxf(0.0, t - 0.009)  # deuxième contact, plus mou : le « plarf »
		var smack2 := (lp2.call(noise) as float) * exp(-t2 / 0.03) * (1.0 if t > 0.009 else 0.0)
		out[i] = boom * boom_weight * 1.2 + smack * smack_weight * 1.8 + smack2 * smack_weight * 0.6
	return out


# Petit bruit de bouche de quelqu'un qui pousse : « hmpf » court, voisé et soufflé.
func _grunt(v: int) -> PackedFloat32Array:
	var duration := 0.2
	var out := _buffer(duration)
	var base_freq := 115.0 + v * 28.0
	var formant := _lowpass(650.0 + v * 120.0)
	var formant2 := _lowpass(650.0 + v * 120.0)
	var breath := _lowpass(1500.0)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var u := t / duration
		phase += base_freq * (1.0 - 0.25 * u) / RATE
		var saw := 2.0 * fposmod(phase, 1.0) - 1.0
		var voiced := formant2.call(formant.call(saw)) as float
		var air := breath.call(rng.randf_range(-1.0, 1.0)) as float
		var env := (1.0 - exp(-t / 0.01)) * exp(-t / 0.055)
		out[i] = (voiced * 2.5 + air * 0.35) * env
	return out


# Battement de cœur : « boum-boum », deux chocs sourds et graves (un battement par fichier).
func _heartbeat() -> PackedFloat32Array:
	var out := _buffer(0.5)
	for beat in [[0.0, 1.0, 58.0], [0.2, 0.7, 50.0]]:
		var start: float = beat[0]
		var gain: float = beat[1]
		var freq: float = beat[2]
		var phase := 0.0
		for i in range(int(start * RATE), out.size()):
			var t := float(i) / RATE - start
			phase += TAU * freq * (1.0 + 0.6 * exp(-t / 0.02)) / RATE
			var env := (1.0 - exp(-t / 0.004)) * exp(-t / 0.055)
			out[i] += (sin(phase) + 0.3 * sin(2.0 * phase)) * env * gain
	return out


# Défaite : courte mélodie triste et lente en la mineur, sur un accord tenu, avec un peu d'écho.
func _defeat() -> PackedFloat32Array:
	var out := _buffer(5.0)
	var melody := [[0.0, 0.7, 329.6], [0.7, 0.7, 293.7], [1.4, 0.7, 261.6], [2.1, 1.9, 246.9]]  # mi ré do si
	for note in melody:
		_add_note(out, note[0], note[1], note[2], 0.55, false)
	for freq in [110.0, 130.8, 164.8]:  # la, do, mi graves
		_add_note(out, 0.0, 4.0, freq, 0.18, false)
	return _echo(out, 0.28, 0.35)


# Victoire : fanfare de cuivres, applaudissements et cris de joie.
func _victory() -> PackedFloat32Array:
	var out := _buffer(5.5)
	var fanfare := [[0.0, 0.14, 392.0], [0.16, 0.14, 523.3], [0.32, 0.14, 659.3], [0.48, 0.45, 784.0],
		[0.96, 0.14, 659.3], [1.12, 1.3, 784.0]]  # sol do mi sol… mi sol
	for note in fanfare:
		_add_note(out, note[0], note[1], note[2], 0.5, true)
	for freq in [261.6, 329.6, 523.3]:  # accord final de do majeur
		_add_note(out, 1.12, 1.3, freq, 0.28, true)
	_add_applause(out, 0.9, 5.4)
	_add_cheers(out, 1.0, 4.2)
	return _echo(out, 0.18, 0.2)


# Note jouée : timbre cuivré (brass) ou doux, avec attaque, vibrato et extinction.
func _add_note(out: PackedFloat32Array, start: float, duration: float, freq: float, gain: float, brass: bool) -> void:
	var release := 0.25 if brass else 0.6
	var first := int(start * RATE)
	var last := mini(out.size(), int((start + duration + release) * RATE))
	var phase := 0.0
	for i in range(first, last):
		var t := float(i) / RATE - start
		var vibrato := 1.0 + 0.006 * sin(TAU * 5.5 * t) * minf(t / 0.3, 1.0)
		phase += TAU * freq * vibrato / RATE
		var wave := 0.0
		if brass:
			var brightness := minf(t / 0.05, 1.0)  # le son s'ouvre à l'attaque
			for h in range(1, 8):
				wave += sin(phase * h) / h * (1.0 if h <= 2 else brightness)
		else:
			for h in [1, 3, 5]:
				wave += sin(phase * h) / (h * h)  # timbre doux, proche d'un triangle
		var attack := minf(t / (0.02 if brass else 0.08), 1.0)
		var tail := 1.0 if t < duration else exp(-(t - duration) / (release * 0.35))
		out[i] += wave * attack * tail * gain


# Applaudissements : beaucoup de petits claquements de bruit, denses au milieu.
func _add_applause(out: PackedFloat32Array, start: float, stop: float) -> void:
	var claps := int((stop - start) * 90.0)
	for c in claps:
		var u := rng.randf()
		var at := start + u * (stop - start)
		var density := sin(PI * u)
		if rng.randf() > density:
			continue
		var lp := _lowpass(rng.randf_range(1800.0, 4500.0))
		var gain := rng.randf_range(0.15, 0.35)
		for i in range(int(at * RATE), mini(out.size(), int((at + 0.03) * RATE))):
			var t := float(i) / RATE - at
			out[i] += (lp.call(rng.randf_range(-1.0, 1.0)) as float) * exp(-t / 0.006) * gain


# Cris de joie : voix aiguës qui montent (« ouaaais ! »), plus un brouhaha de foule.
func _add_cheers(out: PackedFloat32Array, start: float, stop: float) -> void:
	for voice in 6:
		var at := start + rng.randf_range(0.0, 1.0)
		var length := rng.randf_range(0.8, 1.6)
		var base := rng.randf_range(260.0, 480.0)
		var formant := _lowpass(rng.randf_range(900.0, 1500.0))
		var formant2 := _lowpass(rng.randf_range(900.0, 1500.0))
		var phase := 0.0
		for i in range(int(at * RATE), mini(out.size(), int((at + length) * RATE))):
			var t := float(i) / RATE - at
			var u := t / length
			var freq := base * (1.0 + 0.35 * sin(PI * minf(u * 1.6, 1.0))) * (1.0 + 0.02 * sin(TAU * 6.0 * t))
			phase += freq / RATE
			var saw := 2.0 * fposmod(phase, 1.0) - 1.0
			var env := minf(t / 0.05, 1.0) * pow(1.0 - u, 0.8)
			out[i] += (formant2.call(formant.call(saw)) as float) * env * 0.5
	var low := _lowpass(400.0)
	var high := _lowpass(2500.0)
	for i in range(int(start * RATE), mini(out.size(), int(stop * RATE))):
		var u := (float(i) / RATE - start) / (stop - start)
		var noise := rng.randf_range(-1.0, 1.0)
		out[i] += (high.call(noise - (low.call(noise) as float)) as float) * sin(PI * u) * 0.25


# Écho simple : le son se répète, plus faible, après un court délai.
func _echo(samples: PackedFloat32Array, delay: float, feedback: float) -> PackedFloat32Array:
	var offset := int(delay * RATE)
	for i in range(offset, samples.size()):
		samples[i] += samples[i - offset] * feedback
	return samples


# Bourdonnement électrique en boucle (0,5 s, un nombre entier de périodes) : ronflement
# à 100 Hz et petits grésillements.
func _buzz() -> PackedFloat32Array:
	var out := _buffer(0.5)
	var crackle := _lowpass(5000.0)
	var spark := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var hum := 0.0
		for h in range(1, 10):
			hum += sin(TAU * 100.0 * h * t) / h
		if rng.randf() < 0.002:
			spark = rng.randf_range(0.5, 1.0)  # départ d'un grésillement
		spark *= 0.995
		var noise := rng.randf_range(-1.0, 1.0)
		out[i] = hum * 0.35 + (noise - (crackle.call(noise) as float)) * spark * 0.8
	return out


# Cri de secours (si aucune voix de synthèse n'est disponible) : « nèèr-vouuuuuus ! »,
# voix aiguë qui monte sur le « ou » puis retombe, avec un « s » soufflé à la fin.
func _nervous_cry() -> PackedFloat32Array:
	var duration := 1.7
	var out := _buffer(duration)
	var phase := 0.0
	var f1 := _lowpass(500.0)
	var f2 := _lowpass(500.0)
	var hiss := _lowpass(7000.0)
	for i in out.size():
		var t := float(i) / RATE
		var pitch := 260.0 + 140.0 * sin(PI * clampf((t - 0.25) / 1.2, 0.0, 1.0))
		pitch *= 1.0 + 0.03 * sin(TAU * 6.0 * t)
		phase += pitch / RATE
		var saw := 2.0 * fposmod(phase, 1.0) - 1.0
		# « nèr » : son plus ouvert (formant plus aigu) ; « vouuu » : son fermé et sombre.
		var openness := 1.0 if t < 0.25 else 0.35
		var voiced := f2.call(f1.call(saw)) as float
		var bright := saw * 0.15 * openness
		var env := minf(t / 0.03, 1.0) * (1.0 if t < 1.35 else maxf(0.0, 1.0 - (t - 1.35) / 0.15))
		var noise := rng.randf_range(-1.0, 1.0)
		var s := (noise - (hiss.call(noise) as float)) * (1.0 if t > 1.4 and t < 1.65 else 0.0) * 0.6
		out[i] = (voiced * 2.2 + bright) * env + s
	return out


# --- Outils ------------------------------------------------------------------------

func _buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	return out


# Filtre passe-bas à un pôle ; renvoie une fonction qui filtre un échantillon à la fois.
func _lowpass(cutoff: float) -> Callable:
	var coef := 1.0 - exp(-TAU * cutoff / RATE)
	var state := [0.0]
	return func(x: float) -> float:
		state[0] += coef * (x - state[0])
		return state[0]


func _save(name: String, samples: PackedFloat32Array) -> void:
	var peak := 0.0001
	for s in samples:
		peak = maxf(peak, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.9, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.save_to_wav(ProjectSettings.globalize_path("res://sounds/%s.wav" % name))
