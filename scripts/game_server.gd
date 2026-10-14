# Autorité du jeu : seul ce nœud applique les règles et décide de l'ordre des tapes.
# Les joueurs (humain, ordinateurs, et plus tard joueurs en ligne) ne font qu'envoyer
# des demandes (request_play / request_slap) et réagissent aux signaux émis.
extends Node

const GameRules = preload("res://scripts/game_rules.gd")
const Cards = preload("res://scripts/cards.gd")
const Table = preload("res://scripts/table.gd")

signal game_started(counts: Array)
signal turn_started(player: int, duration: float)
signal card_played(player: int, card: int, center_count: int, pos: Vector2, yaw: float)  # pos, yaw : où la carte atterrit
signal slap_window_opened   # une paire vient d'apparaître : taper devient légal
signal slap_window_closed   # la paire a été recouverte depuis trop longtemps : taper n'est plus légal
signal slap_registered(player: int, order: int, pos: Vector2)  # tape qui touche le tas
signal slap_missed(player: int, pos: Vector2)                # tape à côté (feinte) : sans effet, la main remonte
signal card_ejected(player: int, card: int)  # carte qui recouvrait la paire, renvoyée sous le tas de son propriétaire
signal pile_taken(shares: Dictionary, reason: String)  # { joueur: cartes }, reason : "slap", "false_slap", "nervous" ou "timeout"
signal slap_judged(shares: Dictionary, reason: String, highlighted: int, order: Array)  # verdict annoncé avant le ramassage ; highlighted : nombre de cartes du dessus en cause ; order : ordre réel des tapes (corrigé de la latence)
signal hand_moved(player: int, pos: Vector2)     # position de la main droite d'un joueur, pour l'afficher chez les autres
signal player_nervous(player: int, order: int)  # main restée trop loin dans le cercle : NERVOUS !
signal speed_changed(level: int)  # la partie s'accélère (au début d'une nouvelle manche)
signal player_replaced(player: int)  # un ami est parti : un ordinateur joue à sa place
signal game_over(loser: int)

const TURN_TIME := 5.0        # temps pour jouer sa carte (au niveau 0)
const CARD_TRAVEL := 0.35     # durée du vol de la carte vers le centre (au niveau 0)
const SPEED_STEP := 0.9       # à chaque niveau, ces deux durées sont multipliées par ce facteur
const LEVEL_DURATION := 60.0  # une minute de jeu = un niveau de plus (appliqué entre deux manches)
const COVER_GRACE := 0.5      # temps pour taper encore une paire après l'atterrissage de la carte qui la recouvre
const SLAP_WINDOW := 3.0      # temps pour taper une paire visible, puis temps de jugement après la première tape
# Verdict : on attend la fin du tremblement, puis les mains se retirent une à une
# (dans l'ordre inverse des tapes), puis on laisse le temps de lire avant de distribuer.
const SETTLE_TIME := 2.2         # fin du tremblement après les tapes
const HAND_LIFT_INTERVAL := 0.35 # entre deux mains qui se retirent
const REVEAL_READ := 1.6         # temps de lecture du verdict
const NERVOUS_SETTLE := 0.3      # après l'annonce NERVOUS, le verdict arrive presque aussitôt
const NERVOUS_READ := 1.2        # et se lit plus vite
const RESOLVE_DELAY := 1.9    # pause après un ramassage, le temps de l'animation
const NERVOUS_GRACE := 0.5   # main qui franchit la ligne du cercle : temps pour taper
const THROW_EXIT_GRACE := 1.0  # carte lâchée dans le cercle : temps pour en ressortir
const NERVOUS_CONTAGION := 0.5  # après un premier nerveux, temps pendant lequel d'autres peuvent l'être aussi
const NERVOUS_SHOW := 1.2    # durée de l'annonce « NERVOUS !!! » avant le verdict
const PILE_SPREAD_MIN := 0.03 # dispersion des cartes au centre : rayon au début...
const PILE_SPREAD_MAX := 0.12 # ...et rayon maximal, atteint après quelques cartes

# TURN : on joue les cartes. Une paire visible n'arrête pas le jeu : elle peut être recouverte.
# SLAP : quelqu'un a tapé, sa main bloque le tas. Les autres peuvent taper aussi,
#        puis le serveur juge si la première tape était valide.
# NERVOUS : une main est restée trop loin dans le cercle ; le jeu s'arrête, d'autres peuvent être nerveux.
enum State { IDLE, TURN, SLAP, NERVOUS, RESOLVING, OVER }

var rules := GameRules.new()
var rng := RandomNumberGenerator.new()
var state: State = State.IDLE
var current_player := -1
var speed_level := 0
var turn_time := TURN_TIME
var card_travel := CARD_TRAVEL
var _start_clock := 0.0

# Réseau. Chez un ami, ce nœud est un relais (remote) : il envoie ses demandes à l'hôte et
# répète localement les annonces reçues. Chez l'hôte, il envoie chaque annonce aux amis.
var remote := false
var _seat_of_peer := {}       # hôte : identifiant réseau -> siège
var _last_hand_sent := {}     # limite l'envoi des positions de main (par siège)

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
var _slap_positions: Array[Vector2] = []  # mains posées sur le tas
var _slap_times: Array[float] = []        # heure de chaque tape, corrigée de la latence
var _closed_pair_time := -1.0             # dernière paire fermée (pour les tapes d'amis en retard)
var _closed_center_size := 0
var _closed_covered := false
var _closed_cover_player := -1
var latency_override := {}                # tests : siège -> latence simulée (secondes)
var _center_layout: Array[Vector3] = []   # pour chaque carte du centre : x, z, orientation
var _cross_start: Array[float] = []       # instant où la main a franchi la ligne du cercle (-1 : pas franchie)
var _hand_pos: Array[Vector2] = []        # dernière position connue de la main droite
var _holding: Array[bool] = []            # le joueur tient sa carte, prêt à la jeter
var _throw_exit: Array[bool] = []         # carte lâchée dans le cercle : sortir de la ligne est permis
var _nervous: Array[int] = []
var _nervous_time := 0.0


func start_game(players := 4) -> void:
	rng.randomize()
	rules.setup(players, rng)
	_start_clock = _clock
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
		for p in _cross_start.size():
			var grace := THROW_EXIT_GRACE if _throw_exit[p] else NERVOUS_GRACE
			if _cross_start[p] >= 0.0 and _clock - _cross_start[p] > grace:
				_declare_nervous(p)  # ligne franchie sans taper à temps
				return
		if _turn_left <= 0.0:
			_on_turn_timeout()
	elif state == State.NERVOUS:
		if _clock - _nervous_time >= NERVOUS_SHOW:
			_resolve_nervous()
	elif state == State.SLAP:
		_slap_left -= delta
		if _slap_left <= 0.0:
			_resolve_slap()


func request_play(p: int) -> void:
	if remote:
		_send_request("request_play", [])
		return
	if state != State.TURN or p != current_player or rules.count(p) == 0:
		return
	var card := rules.play(p)
	if OS.has_environment("NET_LOG"):
		print("[serveur] carte jouée par le siège ", p)
	var count := rules.center.size()
	# La carte atterrit de plus en plus loin du centre à mesure que le tas grossit.
	var spread := lerpf(PILE_SPREAD_MIN, PILE_SPREAD_MAX, clampf(count / 6.0, 0.0, 1.0))
	var pos := Vector2.from_angle(rng.randf() * TAU) * spread * sqrt(rng.randf())
	var yaw := Table.seat_angle(p, rules.num_players) + rng.randf_range(-0.8, 0.8)  # orientée à peu près comme le joueur qui la jette
	_center_layout.append(Vector3(pos.x, pos.y, yaw))
	card_played.emit(p, card, count, pos, yaw)
	if rules.is_pair():
		_pair_open = true
		_covered = false
		_pair_player = p
		_pair_expire = _clock + card_travel + SLAP_WINDOW
		slap_window_opened.emit()
	elif _pair_open and not _covered:
		# Recouverte : on peut encore taper jusqu'à peu après l'atterrissage de cette carte.
		_covered = true
		_cover_player = p
		_cover_expire = _clock + card_travel + COVER_GRACE
	elif _pair_open:
		_close_pair()  # recouverte deux fois
	if rules.is_over() and not _pair_open:
		_end_game()
	else:
		_start_turn(rules.next_player_from(p))


# Tape à la position pos (x, z) de la main. Elle ne compte que si elle touche la carte
# du dessus (ou, pendant le délai de grâce, la carte du dessus de la paire recouverte)
# ou une main déjà posée sur le tas. Sinon c'est une feinte : la main remonte.
func request_slap(p: int, pos: Vector2) -> void:
	if remote:
		_send_request("request_slap", [pos])
		return
	_ensure_players()
	if (state != State.TURN and state != State.SLAP) or p in _slap_order:
		return
	_cross_start[p] = -1.0  # avoir tapé (même à côté) dispense d'être nerveux
	if not _hits_pile(pos):
		slap_missed.emit(p, pos)
		return
	# Heure « réelle » de la tape : un ami à distance a vu la carte et tapé plus tôt
	# que l'arrivée de sa demande (un aller-retour réseau, plafonné).
	var slap_time := _clock - latency(p)
	if state == State.TURN:
		# Paire recouverte dont le délai de grâce vient d'expirer, mais tape partie à temps.
		var late_but_valid := not _pair_open and _closed_pair_time >= 0.0 \
			and slap_time <= _closed_pair_time and rules.center.size() == _closed_center_size
		if late_but_valid:
			_pair_open = true
			_covered = _closed_covered
			_cover_player = _closed_cover_player
		# Première tape : la main bloque le tas, plus personne ne peut jouer.
		state = State.SLAP
		_clear_crossings()
		_slap_valid = _pair_open
		_slap_order.clear()
		_slap_times.clear()
		_slap_positions.clear()
		_slap_left = SLAP_WINDOW
		if _pair_open and _covered:
			# La carte qui recouvrait la paire est éjectée et rend la tape légale.
			card_ejected.emit(_cover_player, rules.eject_top_to(_cover_player))
			_center_layout.pop_back()
		_pair_open = false
	_slap_order.append(p)
	_slap_times.append(slap_time)
	_slap_positions.append(pos)
	slap_registered.emit(p, _slap_order.size(), pos)
	if _slap_order.size() == rules.num_players:
		_resolve_slap()


# Position de la main droite d'un joueur. Une main qui franchit la ligne du cercle
# doit taper dans les NERVOUS_GRACE secondes ; si elle ressort avant ou reste trop
# longtemps sans taper, le joueur est nerveux.
func update_hand(p: int, pos: Vector2) -> void:
	if remote:
		_send_hand(pos)
		return
	_ensure_players()
	_emit_hand(p, pos)
	_hand_pos[p] = pos
	var crossed := Table.intrusion(pos) > Table.LINE_TOLERANCE
	if state == State.NERVOUS:
		if crossed and _clock - _nervous_time <= NERVOUS_CONTAGION:
			_declare_nervous(p)
	elif state == State.TURN and not _holding[p]:  # en train de jeter sa carte : franchir la ligne est permis
		if crossed and _cross_start[p] < 0.0:
			_cross_start[p] = _clock
		elif not crossed and _cross_start[p] >= 0.0:
			if _throw_exit[p]:
				_cross_start[p] = -1.0  # sortie du cercle après avoir jeté sa carte : c'est permis
				_throw_exit[p] = false
			else:
				_declare_nervous(p)  # main ramenée sans avoir tapé


# Le joueur saisit sa carte (seulement pendant son tour) : il peut franchir la ligne en la jetant.
func grab_card(p: int) -> void:
	if remote:
		_send_request("grab_card", [])
		return
	_ensure_players()
	if state == State.TURN and p == current_player:
		_holding[p] = true
		_cross_start[p] = -1.0


# Le joueur lâche sa carte : si sa main est dans le cercle, il a THROW_EXIT_GRACE secondes pour en sortir.
func release_card(p: int) -> void:
	if remote:
		_send_request("release_card", [])
		return
	_ensure_players()
	if not _holding[p]:
		return
	_holding[p] = false
	var crossed := Table.intrusion(_hand_pos[p]) > Table.LINE_TOLERANCE
	_throw_exit[p] = crossed
	_cross_start[p] = _clock if crossed else -1.0


func _declare_nervous(p: int) -> void:
	if p in _nervous:
		return
	if state == State.TURN:
		state = State.NERVOUS
		_nervous_time = _clock
		_pair_open = false
		_nervous.clear()
		_clear_crossings()
	elif state != State.NERVOUS:
		return
	_nervous.append(p)
	player_nervous.emit(p, _nervous.size())


# Les nerveux se partagent le tas ; le premier d'entre eux rejoue.
func _resolve_nervous() -> void:
	state = State.RESOLVING
	var losers: Array[int] = _nervous.duplicate()
	_nervous.clear()
	_center_layout.clear()
	var shares := rules.give_center_to(losers, rng)
	var slappers := 0
	slap_judged.emit(shares, "nervous", 0, [])
	_after(reveal_time(slappers, "nervous"), func():
		pile_taken.emit(shares, "nervous")
		_after(RESOLVE_DELAY, func(): _continue_with(losers[0])))


# Tableaux par joueur, créés à la première utilisation.
func _ensure_players() -> void:
	if _hand_pos.size() == rules.num_players:
		return
	_cross_start.resize(rules.num_players)
	_holding.resize(rules.num_players)
	_throw_exit.resize(rules.num_players)
	_hand_pos.resize(rules.num_players)
	_clear_crossings()


func _clear_crossings() -> void:
	for p in _cross_start.size():
		_cross_start[p] = -1.0
		_holding[p] = false
		_throw_exit[p] = false


# Position (x, z) de la carte du dessus du centre, ou null si le centre est vide.
func top_card_position():
	if _center_layout.is_empty():
		return null
	var top := _center_layout[-1]
	return Vector2(top.x, top.y)


func _hits_pile(pos: Vector2) -> bool:
	var n := _center_layout.size()
	if n > 0 and _hand_touches_card(pos, _center_layout[n - 1]):
		return true
	if n > 1 and _pair_open and _covered and _hand_touches_card(pos, _center_layout[n - 2]):
		return true
	for hand in _slap_positions:
		if hand.distance_to(pos) <= Table.HAND_RADIUS * 2.0:
			return true
	return false


# La paume (disque) touche-t-elle la carte (rectangle orienté) ?
func _hand_touches_card(pos: Vector2, card: Vector3) -> bool:
	# Passage dans le repère de la carte. Sur la table, x et z sont l'abscisse et l'ordonnée,
	# et une rotation de yaw autour de l'axe vertical tourne (x, z) de -yaw.
	var local := (pos - Vector2(card.x, card.y)).rotated(card.z)
	var half := Vector2(Cards.CARD_W, Cards.CARD_L) / 2.0
	var closest := local.clamp(-half, half)
	return local.distance_to(closest) <= Table.HAND_RADIUS


func _close_pair() -> void:
	# On garde de quoi accepter une tape d'ami partie juste avant la fermeture.
	_closed_pair_time = _clock
	_closed_center_size = rules.center.size()
	_closed_covered = _covered
	_closed_cover_player = _cover_player
	_pair_open = false
	slap_window_closed.emit()


func _start_turn(p: int) -> void:
	_ensure_players()
	state = State.TURN
	current_player = p
	# Un ami à distance reçoit son tour en retard et sa carte arrive en retard : on le
	# compense pour que le réseau ne lui fasse pas perdre son tour.
	_turn_left = turn_time + latency(p)
	turn_started.emit(p, turn_time)


# Tape valide : le dernier à taper ramasse ; ceux qui n'ont pas tapé sont tous « derniers »
# et se partagent le tas (le premier d'entre eux à partir de celui qui a posé la paire rejoue).
# Tape par erreur : tous les tapeurs se partagent le tas, le premier fautif rejoue.
func _resolve_slap() -> void:
	state = State.RESOLVING
	_clear_crossings()
	_pair_open = false
	_closed_pair_time = -1.0
	# Ordre des tapes corrigé de la latence de chacun (peut différer de l'ordre d'arrivée).
	var order := _corrected_slap_order()
	var losers: Array[int] = []
	var reason := "slap"
	if not _slap_valid:
		reason = "false_slap"
		losers = order.duplicate()
	elif order.size() == rules.num_players:
		losers.append(order[-1])
	else:
		for i in rules.num_players:
			var p := (_pair_player + i) % rules.num_players
			if not p in order:
				losers.append(p)
	var slappers := order.size()
	_slap_order.clear()
	_slap_times.clear()
	_slap_positions.clear()
	_center_layout.clear()
	var shares := rules.give_center_to(losers, rng)
	slap_judged.emit(shares, reason, 2 if _slap_valid else 1, order)
	_after(reveal_time(slappers, reason), func():
		pile_taken.emit(shares, reason)
		_after(RESOLVE_DELAY, func(): _continue_with(losers[0])))


# Temps écoulé : le joueur ramasse le tas du centre, puis on passe au suivant.
func _on_turn_timeout() -> void:
	state = State.RESOLVING
	_clear_crossings()
	_pair_open = false
	var p := current_player
	var losers: Array[int] = [p]
	_center_layout.clear()
	pile_taken.emit(rules.give_center_to(losers, rng), "timeout")
	_after(RESOLVE_DELAY, func(): _continue_with(rules.next_player_from(p)))


func _continue_with(p: int) -> void:
	_update_speed()
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


# Durée entre le verdict et la distribution du tas.
static func reveal_time(slappers: int, reason := "slap") -> float:
	var read := NERVOUS_READ if reason == "nervous" else REVEAL_READ
	return settle_time(reason) + slappers * HAND_LIFT_INTERVAL + read


# Attente avant le verdict : la fin du tremblement des tapes (courte pour un NERVOUS).
static func settle_time(reason: String) -> float:
	return NERVOUS_SETTLE if reason == "nervous" else SETTLE_TIME


# Entre deux manches : un niveau de plus par minute de jeu écoulée. Chaque niveau réduit
# de 10 % le temps pour jouer et la durée du vol (et du retournement) des cartes.
func _update_speed() -> void:
	var level := int((_clock - _start_clock) / LEVEL_DURATION)
	if level <= speed_level or state == State.OVER:
		return
	speed_level = level
	turn_time = TURN_TIME * speed_factor()
	card_travel = CARD_TRAVEL * speed_factor()
	speed_changed.emit(speed_level)


func speed_factor() -> float:
	return pow(SPEED_STEP, speed_level)


# --- Réseau ---------------------------------------------------------------------------

const HAND_SEND_INTERVAL := 0.05  # positions de main : 20 envois par seconde au plus
const MAX_LATENCY_COMPENSATION := 0.25  # on ne rattrape jamais plus de 250 ms
const NET_REQUESTS := ["request_play", "request_slap", "grab_card", "release_card"]


# Hôte : chaque annonce est aussi envoyée à tous les amis connectés.
func host_network(seat_of_peer: Dictionary) -> void:
	_seat_of_peer = seat_of_peer
	game_started.connect(func(a): _broadcast("game_started", [a]))
	turn_started.connect(func(a, b): _broadcast("turn_started", [a, b]))
	card_played.connect(func(a, b, c, d, e): _broadcast("card_played", [a, b, c, d, e]))
	slap_registered.connect(func(a, b, c): _broadcast("slap_registered", [a, b, c]))
	slap_missed.connect(func(a, b): _broadcast("slap_missed", [a, b]))
	card_ejected.connect(func(a, b): _broadcast("card_ejected", [a, b]))
	pile_taken.connect(func(a, b): _broadcast("pile_taken", [a, b]))
	slap_judged.connect(func(a, b, c, d): _broadcast("slap_judged", [a, b, c, d]))
	player_nervous.connect(func(a, b): _broadcast("player_nervous", [a, b]))
	speed_changed.connect(func(a): _broadcast("speed_changed", [a]))
	player_replaced.connect(func(a): _broadcast("player_replaced", [a]))
	game_over.connect(func(a): _broadcast("game_over", [a]))


func _broadcast(event: String, args: Array) -> void:
	if _networked():
		_net_event.rpc(event, args)


# Ami : annonce reçue de l'hôte, répétée localement pour l'affichage.
@rpc("authority", "call_remote", "reliable")
func _net_event(event: String, args: Array) -> void:
	if OS.has_environment("NET_LOG"):
		print("[ami] reçu : ", event, " ", args)
	if event == "speed_changed":
		speed_level = args[0]
		turn_time = TURN_TIME * speed_factor()
		card_travel = CARD_TRAVEL * speed_factor()
	emit_signal.callv([event] + args)


# Ami : demande envoyée à l'hôte (le siège est déduit de la connexion par l'hôte).
func _send_request(method: String, args: Array) -> void:
	_net_request.rpc_id(1, method, args)


@rpc("any_peer", "call_remote", "reliable")
func _net_request(method: String, args: Array) -> void:
	if OS.has_environment("NET_LOG"):
		print("[hôte] demande de ", multiplayer.get_remote_sender_id(), " : ", method, " ", args)
	var seat: int = _seat_of_peer.get(multiplayer.get_remote_sender_id(), -1)
	if seat >= 0 and method in NET_REQUESTS:
		callv(method, [seat] + args)


# Positions de main : envoi fréquent, perte tolérée (la suivante corrige).
func _send_hand(pos: Vector2) -> void:
	if _hand_throttled(-1):
		return
	_net_hand.rpc_id(1, pos)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_hand(pos: Vector2) -> void:
	var seat: int = _seat_of_peer.get(multiplayer.get_remote_sender_id(), -1)
	if seat >= 0:
		update_hand(seat, pos)


func _emit_hand(p: int, pos: Vector2) -> void:
	hand_moved.emit(p, pos)
	if _networked() and not remote and not _hand_throttled(p):
		_net_hand_moved.rpc(p, pos)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_hand_moved(p: int, pos: Vector2) -> void:
	hand_moved.emit(p, pos)


func _hand_throttled(key: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_hand_sent.get(key, -1.0)) < HAND_SEND_INTERVAL:
		return true
	_last_hand_sent[key] = now
	return false


func _networked() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


# Aller-retour réseau d'un joueur (0 pour l'hôte et les ordinateurs), plafonné.
func latency(seat: int) -> float:
	if latency_override.has(seat):
		return minf(latency_override[seat], MAX_LATENCY_COMPENSATION)
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or remote:
		return 0.0
	for peer_id in _seat_of_peer:
		if _seat_of_peer[peer_id] == seat:
			var connection := enet.get_peer(peer_id)
			if connection == null:
				return 0.0
			var rtt_ms := connection.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			return minf(rtt_ms / 1000.0, MAX_LATENCY_COMPENSATION)
	return 0.0


func _corrected_slap_order() -> Array[int]:
	var indices := range(_slap_order.size())
	indices.sort_custom(func(a, b): return _slap_times[a] < _slap_times[b])
	var order: Array[int] = []
	for i in indices:
		order.append(_slap_order[i])
	return order


# Hôte : un ami est parti en pleine partie. Sa main est libérée (plus de carte tenue ni de
# ligne franchie) ; un ordinateur, créé par la table, jouera à sa place.
func replace_by_bot(seat: int) -> void:
	_ensure_players()
	_holding[seat] = false
	_throw_exit[seat] = false
	_cross_start[seat] = -1.0
	player_replaced.emit(seat)
