# Lance la partie, attend quelques secondes et enregistre une capture d'écran.
# Lancer : Godot --path . --script res://tests/screenshot.gd -- <fichier.png> [secondes]
extends SceneTree

var _wait := 4.0
var _out := "user://screenshot.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_wait = float(args[1])
	change_scene_to_file("res://scenes/main.tscn")


func _process(delta: float) -> bool:
	_wait -= delta
	if _wait <= 0.0:
		root.get_texture().get_image().save_png(_out)
		quit()
	return false
