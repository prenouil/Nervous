# Joueur ordinateur. Il ne voit que les signaux du serveur et lui envoie des demandes,
# exactement comme le fera un joueur en ligne.
extends Node

const GameServer = preload("res://scripts/game_server.gd")

var seat := 0
var reaction := 0.4   # temps de réaction de base pour taper, en secondes
var server: GameServer
var rng := RandomNumberGenerator.new()


func setup(p_seat: int, p_server: GameServer, p_reaction: float) -> void:
	seat = p_seat
	server = p_server
	reaction = p_reaction
	rng.randomize()
	server.turn_started.connect(_on_turn_started)
	server.slap_window_opened.connect(_on_slap_window_opened)


func _on_turn_started(player: int, _duration: float) -> void:
	if player == seat:
		_after(rng.randf_range(0.8, 1.8), func(): server.request_play(seat))


func _on_slap_window_opened() -> void:
	var delay := GameServer.CARD_TRAVEL + reaction + rng.randf_range(0.0, 0.35)
	_after(delay, func(): server.request_slap(seat))


func _after(seconds: float, callback: Callable) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = seconds
	add_child(timer)
	timer.timeout.connect(func():
		timer.queue_free()
		callback.call())
	timer.start()
