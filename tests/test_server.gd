# Scénarios précis joués contre le serveur (sans ordinateurs).
# Lancer : Godot --headless --path . --script res://tests/test_server.gd
extends SceneTree

const GameServer = preload("res://scripts/game_server.gd")

var failures := 0
var server: GameServer
var last_take := {}
var ejected := []


func _initialize() -> void:
	Engine.time_scale = 10.0
	_run.call_deferred()


func _run() -> void:
	# 1. Tape par erreur : seuls les tapeurs ramassent.
	_new_server([[1, 2, 3], [20, 21, 22], [40, 41, 42], [5, 6, 7]])
	_play_from(0)                     # centre : 2 (rang 1)
	server.request_slap(2, _top())
	server.request_slap(3, _top())
	await _wait(GameServer.SLAP_WINDOW + GameServer.REVEAL_TIME + 0.2)
	_expect(last_take.get("reason") == "false_slap", "tape par erreur détectée")
	_expect(last_take.get("shares", {}).keys() == [2, 3], "seuls les tapeurs se partagent : %s" % [last_take])

	# 2. Tape valide : les non-tapeurs se partagent.
	_new_server([[1, 3], [14, 3], [8, 9], [10, 11]])  # 1 et 14 sont deux 2
	_play_from(0)
	server.request_play(1)            # paire
	server.request_slap(0, _top())
	server.request_slap(1, _top())
	await _wait(GameServer.SLAP_WINDOW + GameServer.REVEAL_TIME + 0.2)
	_expect(last_take.get("reason") == "slap", "tape valide")
	_expect(last_take.get("shares", {}).keys() == [2, 3], "non-tapeurs perdants : %s" % [last_take])

	# 3. Paire recouverte, tape dans le délai de grâce : éjection.
	_new_server([[1, 3], [14, 3], [8, 9], [10, 11]])
	_play_from(0)
	server.request_play(1)            # paire 2-2
	server.request_play(2)            # recouverte par un 9
	await _wait(GameServer.CARD_TRAVEL + GameServer.COVER_GRACE * 0.5)
	server.request_slap(3, _top())
	_expect(ejected == [[2, 8]], "carte éjectée vers son propriétaire : %s" % [ejected])
	_expect(server.rules.piles[2][-1] == 8, "la carte éjectée est sous le tas du joueur 2")

	# 4. Paire recouverte, tape trop tard : tape par erreur.
	_new_server([[1, 3], [14, 3], [8, 9], [10, 11]])
	_play_from(0)
	server.request_play(1)
	server.request_play(2)
	await _wait(GameServer.CARD_TRAVEL + GameServer.COVER_GRACE + 0.2)
	ejected.clear()
	server.request_slap(3, _top())
	await _wait(GameServer.SLAP_WINDOW + GameServer.REVEAL_TIME + 0.2)
	_expect(ejected.is_empty() and last_take.get("reason") == "false_slap", "tape trop tardive = erreur : %s" % [last_take])

	# 5. Feinte : taper à côté ne compte pas, la tape suivante sur la carte compte.
	_new_server([[1, 3], [14, 3], [8, 9], [10, 11]])
	var missed := []
	server.slap_missed.connect(func(p, _pos): missed.append(p))
	_play_from(0)
	server.request_slap(2, Vector2(0.5, 0.5))
	_expect(missed == [2] and server.state == GameServer.State.TURN, "feinte à côté : sans effet")
	server.request_play(1)            # paire
	server.request_slap(2, Vector2(0.5, 0.5))
	_expect(server.state == GameServer.State.TURN, "feinte pendant une paire : toujours sans effet")
	server.request_slap(2, _top())
	_expect(server.state == GameServer.State.SLAP, "retape sur la carte : prise en compte")
	var hand := server._slap_positions[0]
	server.request_slap(3, hand + Vector2(0.06, 0.0))
	_expect(server._slap_order == [2, 3], "tape sur une main déjà posée : prise en compte")

	print("OK" if failures == 0 else "%d ÉCHEC(S)" % failures)
	quit(failures)


# Serveur avec des tas imposés ; le joueur 0 commence.
func _new_server(piles: Array) -> void:
	if server:
		server.queue_free()
	server = GameServer.new()
	root.add_child(server)
	server.rules.num_players = 4
	server.rules.piles.clear()
	for pile in piles:
		var typed: Array[int] = []
		typed.assign(pile)
		server.rules.piles.append(typed)
	server.rules.center.clear()
	server.pile_taken.connect(func(shares, reason): last_take = {"shares": shares, "reason": reason})
	server.card_ejected.connect(func(p, card): ejected.append([p, card]))
	last_take = {}
	ejected.clear()
	server._start_turn(0)


func _play_from(p: int) -> void:
	server.request_play(p)


func _wait(seconds: float) -> Signal:
	return create_timer(seconds).timeout


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("ÉCHEC : " + label)


func _top() -> Vector2:
	return server.top_card_position()
