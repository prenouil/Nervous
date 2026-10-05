# Autorité du jeu : seul ce nœud applique les règles et décide de l'ordre des tapes.
# Les joueurs (humain, ordinateurs, et plus tard joueurs en ligne) ne font qu'envoyer
# des demandes (request_play / request_slap) et réagissent aux signaux émis.
extends Node

const GameRules = preload("res://scripts/game_rules.gd")

signal game_started(counts: Array)
signal turn_started(player: int, duration: float)
signal card_played(player: int, card: int, center_count: int)
signal slap_window_opened   # une paire vient d'apparaître : taper devient légal
signal slap_window_closed   # la paire a été recouverte depuis trop longtemps : taper n'est plus légal
signal slap_registered(player: int, order: int)
signal card_ejected(player: int, card: int)  # carte qui recouvrait la paire, renvoyée sous le tas de son propriétaire
signal pile_taken(shares: Dictionary, reason: String)  # { joueur: cartes }, reason : "slap", "false_slap" ou "timeout"
signal game_over(loser: int)

const TURN_TIME := 5.0        # temps pour jouer sa carte
const CARD_TRAVEL := 0.35     # durée du vol de la carte vers le centre
const COVER_GRACE := 0.5      # temps pour taper encore une paire après l'atterrissage de la carte qui la recouvre
const SLAP_WINDOW := 3.0      # temps pour taper une paire visible, puis temps de jugement après la première tape
const RESOLVE_DELAY := 1.9    # pause après un ramassage, le temps de l'animation

# TURN : on joue les cartes. Une paire visible n'arrête pas le jeu : elle peut être recouverte.
# SLAP : quelqu'un a tapé, sa main bloque le tas. Les autres peuvent taper aussi,
#        puis le serveur juge si la première tape était valide.
enum State { IDLE, TURN, SLAP, RESOLVING, OVER }

var rules := GameRules.new()
var rng := RandomNumberGenerator.new()
var state: State = State.IDLE
var current_player := -1

var _clock := 0.0
var _turn_left := 0.0
var _pair_open := false       # taper est légal (paire visible, ou recouverte depuis peu)
var _pair_player := -1        # joueur qui a posé la deuxième carte de la paire
var _pair_expire := 0.0       # paire visible que personne ne tape : fin du délai
var _covered := false         # la paire est recouverte par une carte
var _cover_player := -1
var _cover_expire := 0.0      # fin du délai de grâce après l'atterrissage de la carte qui recouvre
var _slap_valid := false
var _slap_left := 0.0
var _slap_order: Array[int] = []


func start_game(players := 4) -> void:
	rng.randomize()
	rules.setup(players, rng)
	game_started.emit(rules.counts())
	_start_turn(rng.randi_range(0, players - 1))


func _process(delta: float) -> void:
	_clock += delta
	if state == State.TURN:
		_turn_left -= delta
		if _pair_open and _covered and _clock > _cover_expire:
			_close_pair()
		elif _pair_open and not _covered and _clock > _pair_expire:
			# Paire visible que personne n'a tapée : tout le monde est « dernier ».
			_slap_valid = true
			_resolve_slap()
			return
		if _turn_left <= 0.0:
			_on_turn_timeout()
	elif state == State.SLAP:
		_slap_left -= delta
		if _slap_left <= 0.0:
			_resolve_slap()


func request_play(p: int) -> void:
	if state != State.TURN or p != current_player or rules.count(p) == 0:
		return
	var card := rules.play(p)
	card_played.emit(p, card, rules.center.size())
	if rules.is_pair():
		_pair_open = true
		_covered = false
		_pair_player = p
		_pair_expire = _clock + CARD_TRAVEL + SLAP_WINDOW
		slap_window_opened.emit()
	elif _pair_open and not _covered:
		# Recouverte : on peut encore taper jusqu'à peu après l'atterrissage de cette carte.
		_covered = true
		_cover_player = p
		_cover_expire = _clock + CARD_TRAVEL + COVER_GRACE
	elif _pair_open:
		_close_pair()  # recouverte deux fois
	if rules.is_over() and not _pair_open:
		_end_game()
	else:
		_start_turn(rules.next_player_from(p))


func request_slap(p: int) -> void:
	if state == State.TURN:
		# Première tape : la main bloque le tas, plus personne ne peut jouer.
		state = State.SLAP
		_slap_valid = _pair_open
		_slap_order.clear()
		_slap_left = SLAP_WINDOW
		if _pair_open and _covered:
			# La carte qui recouvrait la paire est éjectée et rend la tape légale.
			card_ejected.emit(_cover_player, rules.eject_top_to(_cover_player))
		_pair_open = false
	elif state != State.SLAP or p in _slap_order:
		return
	_slap_order.append(p)
	slap_registered.emit(p, _slap_order.size())
	if _slap_order.size() == rules.num_players:
		_resolve_slap()


func _close_pair() -> void:
	_pair_open = false
	slap_window_closed.emit()


func _start_turn(p: int) -> void:
	state = State.TURN
	current_player = p
	_turn_left = TURN_TIME
	turn_started.emit(p, TURN_TIME)


# Tape valide : le dernier à taper ramasse ; ceux qui n'ont pas tapé sont tous « derniers »
# et se partagent le tas (le premier d'entre eux à partir de celui qui a posé la paire rejoue).
# Tape par erreur : tous les tapeurs se partagent le tas, le premier fautif rejoue.
func _resolve_slap() -> void:
	state = State.RESOLVING
	_pair_open = false
	var losers: Array[int] = []
	var reason := "slap"
	if not _slap_valid:
		reason = "false_slap"
		losers = _slap_order.duplicate()
	elif _slap_order.size() == rules.num_players:
		losers.append(_slap_order[-1])
	else:
		for i in rules.num_players:
			var p := (_pair_player + i) % rules.num_players
			if not p in _slap_order:
				losers.append(p)
	_slap_order.clear()
	pile_taken.emit(rules.give_center_to(losers, rng), reason)
	_after(RESOLVE_DELAY, func(): _continue_with(losers[0]))


# Temps écoulé : le joueur ramasse le tas du centre, puis on passe au suivant.
func _on_turn_timeout() -> void:
	state = State.RESOLVING
	_pair_open = false
	var p := current_player
	var losers: Array[int] = [p]
	pile_taken.emit(rules.give_center_to(losers, rng), "timeout")
	_after(RESOLVE_DELAY, func(): _continue_with(rules.next_player_from(p)))


func _continue_with(p: int) -> void:
	if rules.is_over():
		_end_game()
	elif rules.count(p) == 0:
		_start_turn(rules.next_player_from(p))
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
