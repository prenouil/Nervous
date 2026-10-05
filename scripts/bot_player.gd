# Joueur ordinateur. Il ne voit que les signaux du serveur et lui envoie des demandes,
# exactement comme le fera un joueur en ligne.
extends Node

const GameServer = preload("res://scripts/game_server.gd")
const Cards = preload("res://scripts/cards.gd")

const PLAY_DELAY := Vector2(0.6, 1.5)       # temps pour jouer sa carte
const HESITATION := Vector2(0.1, 1.0)       # malus quand les deux cartes du dessus se ressemblent
const CLOSE_RANKS := 2                      # écart de valeur considéré comme « proche »
const REACTION_RANGE := Vector2(0.25, 0.8)  # temps de réaction pour taper, après l'arrivée de la carte
const OWN_CARD_MALUS := Vector2(0.2, 0.5)   # celui qui a joué la carte la voit mal : il réagit plus tard
const MISTAKE_CHANCE := 0.1                 # chance (par ordinateur) de taper par erreur quand les cartes se ressemblent
const FOLLOW_CHANCE := 0.1                  # chance de suivre par réflexe une tape par erreur, retirée à chaque tape
const FOLLOW_CHANCE_OWN_CARD := 0.2         # idem pour celui qui a joué la carte (il l'a mal vue)

var seat := 0
var server: GameServer
var rng := RandomNumberGenerator.new()
var _center: Array[int] = []   # cartes visibles au centre, vues via les signaux
var _last_player := -1         # joueur qui a posé la dernière carte
var _pair_visible := false     # d'après ce que l'ordinateur a vu, taper est légal
var _play_token := 0           # invalide une action prévue devenue obsolète
var _slap_token := 0
var _slap_scheduled := false  # une tape est déjà prévue ou envoyée


func setup(p_seat: int, p_server: GameServer) -> void:
	seat = p_seat
	server = p_server
	rng.randomize()
	server.turn_started.connect(_on_turn_started)
	server.card_played.connect(_on_card_played)
	server.card_ejected.connect(func(_p, _card): _center.pop_back())
	server.pile_taken.connect(_on_pile_taken)
	server.slap_window_opened.connect(_on_slap_window_opened)
	server.slap_window_closed.connect(_cancel_slap)
	server.slap_registered.connect(_on_slap_registered)


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


func _on_card_played(player: int, card: int, _center_count: int) -> void:
	_center.append(card)
	_last_player = player
	# Les cartes se ressemblent : parfois on tape par erreur (sauf celui qui vient de jouer).
	if player != seat and _top_cards_look_alike() and rng.randf() < MISTAKE_CHANCE:
		_schedule_slap(GameServer.CARD_TRAVEL + _reaction_time())


# Deux cartes qui se ressemblent sans former une paire (valeurs voisines et même symbole)
# font hésiter : faut-il taper ?
func _top_cards_look_alike() -> bool:
	var n := _center.size()
	if n < 2:
		return false
	var a := _center[n - 1]
	var b := _center[n - 2]
	if Cards.forms_pair(a, b):
		return false
	return absi(Cards.rank(a) - Cards.rank(b)) <= CLOSE_RANKS and Cards.suit(a) == Cards.suit(b)


func _reaction_time() -> float:
	var delay := rng.randf_range(REACTION_RANGE.x, REACTION_RANGE.y)
	if _last_player == seat:
		delay += rng.randf_range(OWN_CARD_MALUS.x, OWN_CARD_MALUS.y)
	return delay


func _on_slap_window_opened() -> void:
	_pair_visible = true
	_schedule_slap(GameServer.CARD_TRAVEL + _reaction_time())


# Quelqu'un tape alors qu'on ne voit pas de paire : chaque nouvelle tape peut
# entraîner un réflexe (plus il y a de tapeurs, plus on est tenté).
func _on_slap_registered(player: int, _order: int) -> void:
	if player == seat or _pair_visible or _slap_scheduled:
		return
	var chance := FOLLOW_CHANCE_OWN_CARD if _last_player == seat else FOLLOW_CHANCE
	if rng.randf() < chance:
		_schedule_slap(rng.randf_range(REACTION_RANGE.x, REACTION_RANGE.y))


func _on_pile_taken(_shares: Dictionary, _reason: String) -> void:
	_center.clear()
	_cancel_slap()


func _cancel_slap() -> void:
	_pair_visible = false
	_slap_scheduled = false
	_slap_token += 1


func _schedule_slap(delay: float) -> void:
	_slap_token += 1
	_slap_scheduled = true
	var token := _slap_token
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
