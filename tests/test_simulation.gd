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
var false_slaps := 0
var ejections := 0
var nervous := 0


func _initialize() -> void:
	Engine.time_scale = float(OS.get_environment("SIM_SPEED")) if OS.has_environment("SIM_SPEED") else 20.0
	server = GameServer.new()
	root.add_child(server)
	var players := int(OS.get_environment("SIM_PLAYERS")) if OS.has_environment("SIM_PLAYERS") else 4
	for i in players:
		var bot := BotPlayer.new()
		root.add_child(bot)
		bot.setup(i, server)
	server.card_played.connect(func(_p, _c, _n, _pos, _yaw):
		plays += 1
		_check_cards())
	server.pile_taken.connect(func(shares, reason):
		pickups += 1
		if reason == "false_slap": false_slaps += 1
		print("  ramassage %s (%s) -> %s" % [shares, reason, server.rules.counts()])
		_check_cards())
	server.slap_window_opened.connect(func(): pairs += 1)
	server.slap_window_closed.connect(func(): covered += 1)
	server.card_ejected.connect(func(_p, _c): ejections += 1)
	server.player_nervous.connect(func(_p, _o): nervous += 1)
	server.game_over.connect(func(loser):
		_check_cards()
		print("OK : partie terminée en %d cartes jouées, %d ramassages, %d paires dont %d recouvertes, %d éjections, %d tapes par erreur, %d nerveux. Perdant : joueur %d. Tas : %s"
			% [plays, pickups, pairs, covered, ejections, false_slaps, nervous, loser, server.rules.counts()])
		quit(0 if loser >= 0 else 1))
	server.start_game.call_deferred(players)


func _check_cards() -> void:
	if server.rules.total_cards() != server.rules.cards_in_play:
		push_error("Cartes perdues : %d au lieu de %d" % [server.rules.total_cards(), server.rules.cards_in_play])
		quit(1)


func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed > MAX_GAME_SECONDS:
		push_error("La partie ne se termine pas")
		quit(2)
	return false
