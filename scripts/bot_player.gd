# Joueur ordinateur. Il ne voit que les signaux du serveur et lui envoie des demandes,
# exactement comme le fera un joueur en ligne.
extends Node

const GameServer = preload("res://scripts/game_server.gd")
const Cards = preload("res://scripts/cards.gd")

const PLAY_DELAY := Vector2(0.1, 1.0)       # temps pour jouer sa carte
const HESITATION := Vector2(0.1, 1.0)       # malus quand les deux cartes du dessus se ressemblent
const CLOSE_RANKS := 2                      # écart de valeur considéré comme « proche »
const REACTION_RANGE := Vector2(0.25, 0.8)  # temps de réaction pour taper, après l'arrivée de la carte

var seat := 0
var server: GameServer
var rng := RandomNumberGenerator.new()
var _center: Array[int] = []   # cartes visibles au centre, vues via les signaux
var _play_token := 0           # invalide une action prévue devenue obsolète
var _slap_token := 0


func setup(p_seat: int, p_server: GameServer) -> void:
	seat = p_seat
	server = p_server
	rng.randomize()
	server.turn_started.connect(_on_turn_started)
	server.card_played.connect(func(_p, card, _n): _center.append(card))
	server.pile_taken.connect(func(_shares, _reason): _center.clear())
	server.slap_window_opened.connect(_on_slap_window_opened)
	server.slap_window_closed.connect(func(): _slap_token += 1)


func _on_turn_started(player: int, _duration: float) -> void:
	_play_token += 1
	if player != seat:
		return
	var delay := rng.randf_range(PLAY_DELAY.x, PLAY_DELAY.y)
	if _top_cards_look_alike():
		delay += rng.randf_range(HESITATION.x, HESITATION.y)
	var token := _play_token
	_after(delay, func():
		if token == _play_token:
			server.request_play(seat))


# Deux cartes qui se ressemblent sans former une paire font hésiter : faut-il taper ?
func _top_cards_look_alike() -> bool:
	var n := _center.size()
	if n < 2:
		return false
	var a := _center[n - 1]
	var b := _center[n - 2]
	if Cards.rank(a) == Cards.rank(b):
		return false
	return absi(Cards.rank(a) - Cards.rank(b)) <= CLOSE_RANKS or Cards.is_red(a) == Cards.is_red(b)


func _on_slap_window_opened() -> void:
	_slap_token += 1
	var token := _slap_token
	var delay := GameServer.CARD_TRAVEL + rng.randf_range(REACTION_RANGE.x, REACTION_RANGE.y)
	_after(delay, func():
		if token == _slap_token:
			server.request_slap(seat))


func _after(seconds: float, callback: Callable) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = seconds
	add_child(timer)
	timer.timeout.connect(func():
		timer.queue_free()
		callback.call())
	timer.start()
