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
	_save("breath", _breath())
	_save("siren", _siren())
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


# Respiration en boucle : inspiration aiguë et légère, expiration plus grave et plus forte.
func _breath() -> PackedFloat32Array:
	var out := _buffer(3.4)
	var phases := [[0.0, 1.3, 520.0, 2300.0, 0.55], [1.5, 3.0, 220.0, 1100.0, 1.0]]
	for phase_def in phases:
		var start: float = phase_def[0]
		var stop: float = phase_def[1]
		var low := _lowpass(phase_def[2])
		var high := _lowpass(phase_def[3])
		var gain: float = phase_def[4]
		for i in range(int(start * RATE), int(stop * RATE)):
			var u := (float(i) / RATE - start) / (stop - start)
			var noise := rng.randf_range(-1.0, 1.0)
			var band := high.call(noise - (low.call(noise) as float)) as float
			out[i] = band * pow(sin(PI * u), 1.4) * gain
	return out


# Petite sirène douce : un « ouin-ouin » sinusoïdal qui monte et descend deux fois.
func _siren() -> PackedFloat32Array:
	var duration := 1.8
	var out := _buffer(duration)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var freq := 720.0 + 170.0 * sin(TAU * 1.1 * t - PI / 2.0)
		phase += TAU * freq / RATE
		var tone := sin(phase) + 0.2 * sin(2.0 * phase)
		var env := minf(t / 0.12, 1.0) * minf((duration - t) / 0.35, 1.0)
		out[i] = tone * env
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
