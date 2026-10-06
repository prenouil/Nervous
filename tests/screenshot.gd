# Lance la partie et enregistre des captures d'écran.
# Lancer : Godot --path . --script res://tests/screenshot.gd -- <dossier> [secondes]
# Produit : <dossier>/time.png après [secondes], plus slap.png et pickup.png
# au premier ramassage d'au moins 3 cartes (pendant les tapes et pendant le vol des cartes).
# Et judged.png pendant le premier verdict (mains qui se retirent, cartes en rouge).
# Et nervous.png pendant la première annonce « NERVOUS !!! » (si elle arrive avant la fin).
extends SceneTree

var _out := "user://"
var _wait := 4.0
var _shots := {}
var _done_time := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_wait = float(args[1])
	change_scene_to_file("res://scenes/main.tscn")


func _process(delta: float) -> bool:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # ne pas capturer la souris de l'utilisateur
	var server := current_scene.get_node_or_null("GameServer") if current_scene else null
	if server and not server.slap_registered.is_connected(_on_slap):
		server.slap_registered.connect(_on_slap)
		server.pile_taken.connect(_on_pile_taken)
		server.slap_judged.connect(func(_s, _r, _h): if not _shots.has("judged"): _capture_later("judged", 0.9))
		server.player_nervous.connect(func(_p, _o): if not _shots.has("nervous"): _capture_later("nervous", 0.35))
	_wait -= delta
	if _wait <= 0.0 and not _done_time:
		_done_time = true
		_capture("time")
	if _done_time and _shots.get(OS.get_environment("SHOT_UNTIL") if OS.has_environment("SHOT_UNTIL") else "judged", false) and _shots.get("pickup", false):
		quit()
	return false


func _on_slap(_player: int, order: int, _pos: Vector2) -> void:
	if order == 3 and not _shots.has("slap"):
		_capture_later("slap", 0.12)


func _on_pile_taken(shares: Dictionary, _reason: String) -> void:
	var total := 0
	for p in shares:
		total += shares[p]
	if total >= 3 and not _shots.has("pickup"):
		_capture_later("pickup", 0.75)


func _capture_later(name: String, seconds: float) -> void:
	_shots[name] = false
	create_timer(seconds).timeout.connect(func(): _capture(name))


func _capture(name: String) -> void:
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	_shots[name] = true
