# Connexion réseau d'une partie entre amis (autoload « Net »).
# L'hôte ouvre un salon et fait tourner le serveur de jeu ; les amis s'y connectent par
# son adresse. Ce module gère le salon (joueurs, pseudos, pings), les vérifications de
# l'hôte (port, box, adresse publique), puis lance la partie chez tout le monde.
#
# Lancement de test (deux fenêtres sur le même PC) :
#   hôte : Godot --path . -- --host --players=4 --humans=2
#   ami  : Godot --path . -- --join=127.0.0.1
extends Node

signal status_changed(text: String)
signal lobby_changed          # liste des joueurs du salon mise à jour
signal checks_changed         # vérifications de l'hôte mises à jour
signal left_lobby(reason: String)

const PORT := 7777
const MAX_PLAYERS := 6
const BOT_NAMES := ["Léon", "Margot", "Igor", "Zoé", "Bruno"]
const MAIN_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const PUBLIC_IP_URL := "https://api.ipify.org"
const UPNP_LEASE := 7200  # durée (s) de l'ouverture du port sur la box

var active := false          # connecté (salon ou partie)
var is_host := false
var in_game := false
var lobby: Array = []        # [{id, name, ping}] ; l'hôte a l'identifiant 1
# Vérifications de l'hôte : état "pending", "ok", "warn" ou "fail", et détails.
var checks := {}

# Partie lancée
var seat_count := 0
var local_seat := 0
var bot_seats: Array[int] = []
var names: Array[String] = []
var seat_of_peer := {}       # hôte : identifiant réseau -> siège

var _ready_peers := {}
var _host_ready := false
var _on_all_ready := Callable()
var _upnp: UPNP
var _upnp_thread: Thread
var _auto_start_humans := 0  # lancement de test : démarre seul quand assez d'amis sont là
var _auto_start_players := 0
var _ping_timer := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--host":
			_auto_start_players = _arg_value(args, "--players", 4)
			_auto_start_humans = _arg_value(args, "--humans", 2)
			host.call_deferred("Hôte")
		elif arg.begins_with("--join="):
			join.call_deferred(arg.trim_prefix("--join="), "Ami")


func _process(delta: float) -> void:
	# L'hôte envoie régulièrement le ping de chacun au salon.
	if not (active and is_host and not in_game):
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 1.0
		for entry in lobby:
			if entry.id != 1:
				entry.ping = _ping_of(entry.id)
		_broadcast_lobby()


# --- Hôte ----------------------------------------------------------------------------

func host(pseudo: String) -> Error:
	leave()
	checks = {
		"port": {"state": "pending", "text": ""},
		"upnp": {"state": "pending", "text": ""},
		"public_ip": {"state": "pending", "text": ""},
		"cgnat": {"state": "pending", "text": ""},
		"firewall": {"state": "warn", "text": ""},
		"local_ip": _local_ip(),
		"external_ip": "",
	}
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS - 1)
	if error != OK:
		_set_check("port", "fail", "Le port %d est déjà utilisé sur ce PC." % PORT)
		status_changed.emit("Impossible d'ouvrir le port %d." % PORT)
		return error
	_set_check("port", "ok", "oui (port %d)" % PORT)
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = true
	in_game = false
	lobby = [{"id": 1, "name": pseudo, "ping": 0}]
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	lobby_changed.emit()
	status_changed.emit("Salon ouvert. Donne ton adresse à tes amis.")
	_start_upnp()
	_fetch_public_ip()
	return OK


func _on_peer_connected(peer_id: int) -> void:
	if in_game or lobby.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)  # partie lancée ou salon plein
		return
	lobby.append({"id": peer_id, "name": "…", "ping": 0})
	_broadcast_lobby()


func _on_peer_disconnected(peer_id: int) -> void:
	lobby = lobby.filter(func(e): return e.id != peer_id)
	seat_of_peer.erase(peer_id)
	_broadcast_lobby()
	status_changed.emit("Un joueur est parti.")


# Un ami envoie son pseudo en arrivant.
@rpc("any_peer", "call_remote", "reliable")
func _register(pseudo: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	for entry in lobby:
		if entry.id == sender:
			entry.name = pseudo.strip_edges().left(16) if not pseudo.strip_edges().is_empty() else "Ami"
	_broadcast_lobby()
	status_changed.emit("%s a rejoint le salon ✅" % _name_of(sender))
	if _auto_start_humans > 0 and lobby.size() >= _auto_start_humans:
		start_match(_auto_start_players - lobby.size())


func _broadcast_lobby() -> void:
	lobby_changed.emit()
	if active and is_host:
		_lobby_update.rpc(lobby)


# Lance la partie : humains répartis autour de la table (l'hôte en bas), ordinateurs ailleurs.
func start_match(bots: int) -> void:
	seat_count = clampi(lobby.size() + bots, 2, MAX_PLAYERS)
	var humans := lobby.size()
	var human_seats: Array[int] = []
	for i in humans:
		human_seats.append(roundi(float(i) * seat_count / humans) % seat_count)
	seat_of_peer.clear()
	names.clear()
	bot_seats.clear()
	for seat in seat_count:
		names.append("")
	for i in humans:
		var entry: Dictionary = lobby[i]
		names[human_seats[i]] = entry.name
		if entry.id != 1:
			seat_of_peer[entry.id] = human_seats[i]
	var bot_index := 0
	for seat in seat_count:
		if names[seat] == "":
			bot_seats.append(seat)
			names[seat] = BOT_NAMES[bot_index]
			bot_index += 1
	local_seat = 0
	in_game = true
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


# --- Vérifications de l'hôte ------------------------------------------------------------

# Ouverture automatique du port sur la box (UPnP). La recherche de la box prend quelques
# secondes : elle tourne à part pour ne pas figer l'écran.
func _start_upnp() -> void:
	_upnp_thread = Thread.new()
	_upnp_thread.start(func():
		var upnp := UPNP.new()
		var found := upnp.discover(2000, 2, "InternetGatewayDevice")
		var result := {"found": false, "mapped": false, "external": ""}
		if found == UPNP.UPNP_RESULT_SUCCESS and upnp.get_gateway() != null and upnp.get_gateway().is_valid_gateway():
			result.found = true
			# Ouverture limitée dans le temps : si le jeu plante, la box referme le port d'elle-même.
			result.mapped = upnp.add_port_mapping(PORT, PORT, "Nervous", "UDP", UPNP_LEASE) == UPNP.UPNP_RESULT_SUCCESS
			result.external = upnp.query_external_address()
		_on_upnp_done.call_deferred(upnp, result))


func _on_upnp_done(upnp: UPNP, result: Dictionary) -> void:
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if not active:
		if result.mapped:
			upnp.delete_port_mapping(PORT, "UDP")
		return
	_upnp = upnp if result.mapped else null
	checks.external_ip = result.external
	if result.mapped:
		_set_check("upnp", "ok", "ouvert automatiquement")
	elif result.found:
		_set_check("upnp", "warn", "Ta box a refusé l'ouverture automatique : ouvre le port à la main (voir la notice).")
	else:
		_set_check("upnp", "warn", "Ouverture automatique impossible (UPnP désactivé ?) : ouvre le port à la main (voir la notice).")
	_update_cgnat()


func _fetch_public_ip() -> void:
	var request := HTTPRequest.new()
	request.timeout = 6.0
	add_child(request)
	request.request_completed.connect(func(result, code, _headers, body):
		request.queue_free()
		var address: String = body.get_string_from_utf8().strip_edges() if result == HTTPRequest.RESULT_SUCCESS and code == 200 else ""
		if address.is_empty():
			_set_check("public_ip", "fail", "Adresse publique introuvable (pas d'accès à internet ?).")
		else:
			_set_check("public_ip", "ok", address)
		_update_cgnat())
	if request.request(PUBLIC_IP_URL) != OK:
		_set_check("public_ip", "fail", "Adresse publique introuvable.")


# IP partagée (CGNAT) : la box a une adresse « vers internet » qui n'est pas l'adresse publique,
# ou une adresse de la plage réservée aux opérateurs. Héberger est alors impossible.
func _update_cgnat() -> void:
	var external: String = checks.external_ip
	var public: String = checks.public_ip.text if checks.public_ip.state == "ok" else ""
	if external.is_empty() or public.is_empty():
		if checks.upnp.state != "pending" and checks.public_ip.state != "pending":
			_set_check("cgnat", "warn", "Impossible à vérifier sans l'ouverture automatique.")
		return
	if external != public or _is_shared_address(external):
		_set_check("cgnat", "fail", "Ton opérateur partage ton adresse IP (CGNAT) : tes amis ne pourront pas te rejoindre. Demande-lui une IPv4 « full stack » ou fixe, ou laisse un ami héberger.")
	else:
		_set_check("cgnat", "ok", "oui")


func _set_check(key: String, state: String, text: String) -> void:
	checks[key] = {"state": state, "text": text}
	checks_changed.emit()


func _is_shared_address(address: String) -> bool:
	var parts := address.split(".")
	if parts.size() != 4:
		return false
	var a := int(parts[0])
	var b := int(parts[1])
	return a == 10 or (a == 100 and b >= 64 and b <= 127) or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)


func _local_ip() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			return address
	return "?"


# --- Ami -----------------------------------------------------------------------------

func join(address: String, pseudo: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), PORT)
	if error != OK:
		status_changed.emit("Adresse invalide : %s" % address)
		return error
	multiplayer.multiplayer_peer = peer
	active = true
	is_host = false
	in_game = false
	lobby.clear()
	multiplayer.connected_to_server.connect(func():
		_register.rpc_id(1, pseudo)
		status_changed.emit("Connecté ! En attente du lancement par l'hôte…"))
	multiplayer.connection_failed.connect(func():
		leave()
		left_lobby.emit("Connexion impossible : vérifie l'adresse, et que l'hôte a bien ouvert son salon."))
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	status_changed.emit("Connexion à %s…" % address)
	return OK


@rpc("authority", "call_remote", "reliable")
func _lobby_update(players: Array) -> void:
	lobby = players
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _start_client(p_seat_count: int, p_local_seat: int, p_bot_seats: Array, p_names: Array) -> void:
	seat_count = p_seat_count
	local_seat = p_local_seat
	bot_seats.assign(p_bot_seats)
	names.assign(p_names)
	in_game = true
	get_tree().change_scene_to_file(MAIN_SCENE)


# La table d'un ami appelle ceci quand elle est chargée.
func scene_ready() -> void:
	if not is_host:
		_client_ready.rpc_id(1)


func _on_server_disconnected() -> void:
	var was_in_game := in_game
	leave()
	if was_in_game:
		get_tree().change_scene_to_file(MENU_SCENE)
	else:
		left_lobby.emit("L'hôte a fermé le salon.")


# --- Commun --------------------------------------------------------------------------

func leave() -> void:
	if _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
		_upnp = null
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for signal_name in ["peer_connected", "peer_disconnected", "connected_to_server", "connection_failed", "server_disconnected"]:
		for connection in multiplayer.get_signal_connection_list(signal_name):
			multiplayer.disconnect(signal_name, connection.callable)
	active = false
	is_host = false
	in_game = false
	lobby.clear()
	seat_of_peer.clear()


func _exit_tree() -> void:
	leave()
	if _upnp_thread != null:
		_upnp_thread.wait_to_finish()


func _name_of(peer_id: int) -> String:
	for entry in lobby:
		if entry.id == peer_id:
			return entry.name
	return "?"


func _ping_of(peer_id: int) -> int:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return 0
	var connection := enet.get_peer(peer_id)
	return connection.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if connection != null else 0


func _arg_value(args: PackedStringArray, key: String, default: int) -> int:
	for arg in args:
		if arg.begins_with(key + "="):
			return int(arg.trim_prefix(key + "="))
	return default
