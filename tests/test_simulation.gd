# Fait jouer 4 ordinateurs entre eux en accéléré et vérifie les règles.
# Lancer : Godot --headless --path . --script res://tests/test_simulation.gd
extends SceneTree

const GameServer = preload("res://scripts/game_server.gd")
const BotPlayer = preload("res://scripts/bot_player.gd")
const MAX_GAME_SECONDS := 3000.0

var server: GameServer
var elapsed := 0.0
var plays := 0
var pickups := 0
var pairs := 0
var covered := 0


func _initialize() -> void:
	Engine.time_scale = float(OS.get_environment("SIM_SPEED")) if OS.has_environment("SIM_SPEED") else 20.0
	server = GameServer.new()
	root.add_child(server)
	for i in 4:
		var bot := BotPlayer.new()
		root.add_child(bot)
		bot.setup(i, server)
	server.card_played.connect(func(_p, _c, _n):
		plays += 1
		_check_cards())
	server.pile_taken.connect(func(shares, reason):
		pickups += 1
		print("  ramassage %s (%s) -> %s" % [shares, reason, server.rules.counts()])
		_check_cards())
	server.slap_window_opened.connect(func(): pairs += 1)
	server.slap_window_closed.connect(func(): covered += 1)
	server.game_over.connect(func(loser):
		_check_cards()
		print("OK : partie terminée en %d cartes jouées, %d ramassages, %d paires dont %d recouvertes. Perdant : joueur %d. Tas : %s"
			% [plays, pickups, pairs, covered, loser, server.rules.counts()])
		quit(0 if loser >= 0 else 1))
	server.start_game.call_deferred(4)


func _check_cards() -> void:
	if server.rules.total_cards() != 52:
		push_error("Cartes perdues : %d au lieu de 52" % server.rules.total_cards())
		quit(1)


func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > MAX_GAME_SECONDS:
		push_error("La partie ne se termine pas")
		quit(2)
	return false
