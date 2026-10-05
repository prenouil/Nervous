# Fait jouer 4 ordinateurs entre eux en accéléré et vérifie les règles.
# Lancer : Godot --headless --path . --script res://tests/test_simulation.gd
extends SceneTree

const GameServer = preload("res://scripts/game_server.gd")
const BotPlayer = preload("res://scripts/bot_player.gd")
const REACTIONS := [0.2, 0.3, 0.45, 0.6]
const MAX_GAME_SECONDS := 3000.0

var server: GameServer
var elapsed := 0.0
var plays := 0
var pickups := 0


func _initialize() -> void:
	Engine.time_scale = 20.0
	server = GameServer.new()
	root.add_child(server)
	for i in 4:
		var bot := BotPlayer.new()
		root.add_child(bot)
		bot.setup(i, server, REACTIONS[i])
	server.card_played.connect(func(_p, _c, _n):
		plays += 1
		_check_cards())
	server.pile_taken.connect(func(p, n, reason):
		pickups += 1
		print("  joueur %d ramasse %d cartes (%s) -> %s" % [p, n, reason, server.rules.counts()])
		_check_cards())
	server.game_over.connect(func(loser):
		_check_cards()
		print("OK : partie terminée en %d cartes jouées, %d ramassages. Perdant : joueur %d. Tas : %s"
			% [plays, pickups, loser, server.rules.counts()])
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
