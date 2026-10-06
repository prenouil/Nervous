# Musique d'ambiance : chargée une seule fois au lancement (autoload), elle commence dès
# le menu, boucle en continu et ne s'arrête jamais, même en changeant de scène.
extends AudioStreamPlayer

const MUSIC_PATH := "res://sounds/ambient.wav"
const MUSIC_VOLUME := -17.0  # discrète


func _ready() -> void:
	if not ResourceLoader.exists(MUSIC_PATH):
		return
	stream = load(MUSIC_PATH)
	volume_db = -60.0
	play()
	create_tween().tween_property(self, "volume_db", MUSIC_VOLUME, 3.0)
