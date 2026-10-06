# Déclenche la fin de partie (victoire puis défaite) pour vérifier qu'elle ne provoque pas d'erreur.
# Lancer : Godot --headless --path . --script res://tests/test_end_screen.gd
extends SceneTree

var _step := 0
var _time := 0.0


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")


func _process(delta: float) -> bool:
	_time += delta
	if _step == 0 and _time > 2.0:
		current_scene._on_game_over(1)   # Léon perd : victoire
		_step = 1
	elif _step == 1 and _time > 3.0:
		var leftovers := get_nodes_in_group("fx").size()
		current_scene._on_game_over(0)   # tu perds : défaite
		print("OK" if leftovers == 0 else "effets restants : %d" % leftovers)
		_step = 2
	elif _step == 2 and _time > 4.0:
		quit()
	return false
