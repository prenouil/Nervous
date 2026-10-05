# Autorité du jeu : seul ce nœud applique les règles et décide de l'ordre des tapes.
# Les joueurs (humain, ordinateurs, et plus tard joueurs en ligne) ne font qu'envoyer
# des demandes (request_play / request_slap) et réagissent aux signaux émis.
extends Node

const GameRules = preload("res://scripts/game_rules.gd")

signal game_started(counts: Array)
signal turn_started(player: int, duration: float)
signal card_played(player: int, card: int, center_count: int)
signal slap_window_opened
signal slap_registered(player: int, order: int)
signal pile_taken(shares: Dictionary, reason: String)  # { joueur: cartes }, reason : "slap" ou "timeout"
signal game_over(loser: int)

const TURN_TIME := 5.0        # temps pour jouer sa carte
const CARD_TRAVEL := 0.35     # durée du vol de la carte vers le centre
const SLAP_WINDOW := 3.0      # temps laissé pour taper, après l'arrivée de la carte
const RESOLVE_DELAY := 1.9    # pause après un ramassage, le temps de l'animation

enum State { IDLE, TURN, SLAP, RESOLVING, OVER }

var rules := GameRules.new()
var rng := RandomNumberGenerator.new()
var state: State = State.IDLE
var current_player := -1

var _time_left := 0.0
var _slap_order: Array[int] = []


func start_game(players := 4) -> void:
	rng.randomize()
	rules.setup(players, rng)
	game_started.emit(rules.counts())
	_start_turn(rng.randi_range(0, players - 1))


func _process(delta: float) -> void:
	if state != State.TURN and state != State.SLAP:
		return
	_time_left -= delta
	if _time_left > 0.0:
		return
	if state == State.TURN:
		_on_turn_timeout()
	else:
		_resolve_slap()


func request_play(p: int) -> void:
	if state != State.TURN or p != current_player or rules.count(p) == 0:
		return
	var card := rules.play(p)
	card_played.emit(p, card, rules.center.size())
	if rules.is_pair():
		state = State.SLAP
		_slap_order.clear()
		_time_left = CARD_TRAVEL + SLAP_WINDOW
		slap_window_opened.emit()
	elif rules.is_over():
		_end_game()
	else:
		_start_turn(rules.next_player_from(p))


func request_slap(p: int) -> void:
	# TODO : règles des tapes par erreur (à définir). Pour l'instant elles sont ignorées.
	if state != State.SLAP or p in _slap_order:
		return
	_slap_order.append(p)
	slap_registered.emit(p, _slap_order.size())
	if _slap_order.size() == rules.num_players:
		_resolve_slap()


func _start_turn(p: int) -> void:
	state = State.TURN
	current_player = p
	_time_left = TURN_TIME
	turn_started.emit(p, TURN_TIME)


# Le dernier à taper ramasse. Ceux qui n'ont pas tapé à temps sont tous « derniers » :
# ils se partagent le tas, et le premier d'entre eux après le joueur actif rejoue.
func _resolve_slap() -> void:
	state = State.RESOLVING
	var losers: Array[int] = []
	if _slap_order.size() == rules.num_players:
		losers.append(_slap_order[-1])
	else:
		for i in rules.num_players:
			var p := (current_player + i) % rules.num_players
			if not p in _slap_order:
				losers.append(p)
	pile_taken.emit(rules.give_center_to(losers, rng), "slap")
	_after(RESOLVE_DELAY, func(): _continue_with(losers[0]))


# Temps écoulé : le joueur ramasse le tas du centre, puis on passe au suivant.
func _on_turn_timeout() -> void:
	state = State.RESOLVING
	var p := current_player
	var losers: Array[int] = [p]
	pile_taken.emit(rules.give_center_to(losers, rng), "timeout")
	_after(RESOLVE_DELAY, func(): _continue_with(rules.next_player_from(p)))


func _continue_with(p: int) -> void:
	if rules.is_over():
		_end_game()
	else:
		_start_turn(p)


func _end_game() -> void:
	state = State.OVER
	current_player = -1
	game_over.emit(rules.loser())


func _after(seconds: float, callback: Callable) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = seconds
	add_child(timer)
	timer.timeout.connect(func():
		timer.queue_free()
		callback.call())
	timer.start()
