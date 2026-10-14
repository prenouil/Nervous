# Connexion réseau d'une partie entre amis (autoload « Net »).
# L'hôte fait tourner le serveur de jeu ; les amis s'y connectent par son adresse.
# Ce module gère la connexion, attribue les sièges et lance la partie chez tout le monde.
#
# Lancement de test (deux fenêtres sur le même PC) :
#   hôte : Godot --path . -- --host --players=4 --humans=2
#   ami  : Godot --path . -- --join=127.0.0.1
extends Node

signal status_changed(text: String)

const PORT := 7777
const MAX_PLAYERS := 6
const BOT_NAMES := ["Léon", "Margot", "Igor", "Zoé", "Bruno"]
const MAIN_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"

var active := false          # une partie en réseau est en cours (ou en préparation)
var is_host := false
var seat_count := 0
var local_seat := 0
var bot_seats: Array[int] = []
var names: Array[String] = []
var seat_of_peer := {}       # hôte : identifiant réseau -> siège

var _human_seats: Array[int] = []
var _ready_peers := {}
var _host_ready := false
var _on_all_ready := Callable()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var players := _arg_value(args, "--players", 4)
	var humans := _arg_value(args, "--humans", 2)
	for arg in args:
		if arg == "--host":
			host.call_deferred(players, humans)
		elif arg.begins_with("--join="):
			join.call_deferred(arg.trim_prefix("--join="))


# --- Hôte ----------------------------------------------------------------------------

func host(players: int, humans: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS - 1)
	if error != OK:
		status_changed.emit("Impossible d'ouvrir le port %d (déjà utilisé ?)" % PORT)
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	seat_count = clampi(players, 2, MAX_PLAYERS)
	local_seat = 0
	# Sièges des humains répartis autour de la table ; l'hôte est en bas (siège 0).
	_human_seats.clear()
	humans = clampi(humans, 1, seat_count)
	for i in humans:
		_human_seats.append(roundi(float(i) * seat_count / humans) % seat_count)
	seat_of_peer.clear()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	status_changed.emit("En attente de %d ami(s) sur le port %d…" % [humans - 1, PORT])
	if humans == 1:
		_launch()
	return OK


func _on_peer_connected(peer_id: int) -> void:
	var free_seats := _human_seats.filter(func(s): return s != 0 and not s in seat_of_peer.values())
	if free_seats.is_empty():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)  # partie complète
		return
	seat_of_peer[peer_id] = free_seats[0]
	var missing := _human_seats.size() - 1 - seat_of_peer.size()
	status_changed.emit("Un ami est connecté ✅" + ("" if missing == 0 else " — encore %d attendu(s)…" % missing))
	if missing == 0:
		_launch()


func _on_peer_disconnected(peer_id: int) -> void:
	seat_of_peer.erase(peer_id)
	status_changed.emit("Un ami s'est déconnecté.")


# Tout le monde est là : on fixe les sièges et les noms, et chacun charge la table.
func _launch() -> void:
	bot_seats.clear()
	names.clear()
	var bot_index := 0
	var human_index := 1
	for seat in seat_count:
		if seat in _human_seats:
			names.append("Joueur %d" % human_index)
			human_index += 1
		else:
			bot_seats.append(seat)
			names.append(BOT_NAMES[bot_index])
			bot_index += 1
	for peer_id in seat_of_peer:
		_start_client.rpc_id(peer_id, seat_count, seat_of_peer[peer_id], bot_seats, names)
	_ready_peers.clear()
	_host_ready = false
	get_tree().change_scene_to_file(MAIN_SCENE)


# La table de l'hôte appelle ceci : la partie démarre quand tout le monde a chargé la table.
func when_all_ready(start: Callable) -> void:
	_on_all_ready = start
	_host_ready = true
	_check_all_ready()


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	_check_all_ready()


func _check_all_ready() -> void:
	if _host_ready and _ready_peers.size() >= seat_of_peer.size() and _on_all_ready.is_valid():
		var start := _on_all_ready
		_on_all_ready = Callable()
		start.call()


# --- Ami -----------------------------------------------------------------------------

func join(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)
	if error != OK:
		status_changed.emit("Adresse invalide : %s" % address)
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	multiplayer.connected_to_server.connect(func(): status_changed.emit("Connecté à l'hôte, en attente du lancement…"))
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	status_changed.emit("Connexion à %s…" % address)
	return OK


@rpc("authority", "call_remote", "reliable")
func _start_client(p_seat_count: int, p_local_seat: int, p_bot_seats: Array, p_names: Array) -> void:
	seat_count = p_seat_count
	local_seat = p_local_seat
	bot_seats.assign(p_bot_seats)
	names.assign(p_names)
	get_tree().change_scene_to_file(MAIN_SCENE)


# La table d'un ami appelle ceci quand elle est chargée.
func scene_ready() -> void:
	if not is_host:
		_client_ready.rpc_id(1)


func _on_connection_failed() -> void:
	status_changed.emit("Connexion impossible.")
	leave()


func _on_server_disconnected() -> void:
	leave()
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Commun --------------------------------------------------------------------------

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for signal_name in ["peer_connected", "peer_disconnected", "connected_to_server", "connection_failed", "server_disconnected"]:
		for connection in multiplayer.get_signal_connection_list(signal_name):
			multiplayer.disconnect(signal_name, connection.callable)
	active = false
	is_host = false
	seat_of_peer.clear()


func _arg_value(args: PackedStringArray, key: String, default: int) -> int:
	for arg in args:
		if arg.begins_with(key + "="):
			return int(arg.trim_prefix(key + "="))
	return default
