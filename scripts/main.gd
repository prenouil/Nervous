# Vue 3D de la partie et contrôles du joueur humain.
# La vue ne connaît pas les règles : elle envoie des demandes au serveur
# et affiche ce que le serveur annonce par ses signaux.
extends Node3D

const GameServer = preload("res://scripts/game_server.gd")
const BotPlayer = preload("res://scripts/bot_player.gd")
const Cards = preload("res://scripts/cards.gd")

const SEATS := 4
const HUMAN := 0
const NAMES := ["Toi", "Léon", "Margot", "Igor"]
const BOT_REACTIONS := [0.0, 0.30, 0.45, 0.65]
const SKIN_COLORS := [
	Color(0.96, 0.78, 0.62), Color(0.55, 0.38, 0.26),
	Color(0.98, 0.82, 0.70), Color(0.80, 0.60, 0.42)]
const HAIR_COLORS := [Color.BLACK, Color(0.15, 0.1, 0.08), Color(0.85, 0.35, 0.1), Color(0.9, 0.85, 0.6)]

const SEAT_RADIUS := 0.55
const CARD_W := 0.11
const CARD_L := 0.155
const CARD_T := 0.0016
const PALM_H := 0.022
const HAND_Y := 0.03
const LEFT_HAND_LOCAL := Vector3(-0.19, HAND_Y, -0.14)
const RIGHT_HAND_LOCAL := Vector3(0.19, HAND_Y, -0.14)
const HEAD_LOCAL := Vector3(0, 0.34, 0.15)

const GRAB_RADIUS := 0.09         # distance au tas pour pouvoir saisir une carte
const SLAP_RADIUS := 0.15         # distance au centre pour pouvoir taper
const PLAY_DRAG_DISTANCE := 0.07  # mouvement minimal vers le centre pour jeter la carte
const CAMERA_SWAY := Vector2(0.10, 0.06)  # amplitude (radians) du suivi de la souris
const TABLE_LIMITS := Rect2(-0.6, -0.45, 1.2, 0.95)  # zone accessible à la main droite (x, z)

var server: GameServer
var camera: Camera3D
var turn_light: SpotLight3D
var font := SystemFont.new()
var white_mat: StandardMaterial3D
var back_mat: StandardMaterial3D

var seat_roots: Array[Node3D] = []
var left_hands: Array[Node3D] = []
var right_hands: Array[Node3D] = []
var stacks: Array[Node3D] = []
var counts: Array[int] = []
var hand_locked: Array[bool] = []
var hand_tweens: Array = []
var center_cards: Array[Node3D] = []

var _camera_pos := Vector3.ZERO
var _camera_base := Basis()
var _sway := Vector2.ZERO
var _shake := 0.0
var _light_pos := Vector3(0, 1.5, 0)
var _light_goal := Vector3(0, 1.5, 0)
var _light_aim := Vector3.ZERO
var _light_aim_goal := Vector3.ZERO

var _held_card: Node3D = null
var _grab_point := Vector3.ZERO
var _human_slapped := false
var _turn_player := -1
var _turn_left := 0.0
var _game_over := false

var hud_counts: Label
var hud_turn: Label
var hud_message: Label
var _message_left := 0.0


func _ready() -> void:
	font.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI", "Arial"])
	white_mat = _mat(Color(0.97, 0.96, 0.92))
	back_mat = _mat(Color(0.15, 0.25, 0.65))
	for i in SEATS:
		counts.append(0)
		hand_locked.append(false)
		hand_tweens.append(null)

	_build_environment()
	_build_table()
	for i in SEATS:
		_build_seat(i)
	_build_camera()
	_build_hud()

	server = GameServer.new()
	server.name = "GameServer"
	add_child(server)
	server.game_started.connect(_on_game_started)
	server.turn_started.connect(_on_turn_started)
	server.card_played.connect(_on_card_played)
	server.slap_registered.connect(_on_slap_registered)
	server.pile_taken.connect(_on_pile_taken)
	server.game_over.connect(_on_game_over)
	for i in range(1, SEATS):
		var bot := BotPlayer.new()
		bot.name = "Bot%d" % i
		add_child(bot)
		bot.setup(i, server, BOT_REACTIONS[i])

	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	server.start_game.call_deferred(SEATS)


# --- Construction de la scène -------------------------------------------------

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


func _box(size: Vector3, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _mat(color)
	inst.position = pos
	parent.add_child(inst)
	return inst


func _sphere(radius: float, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = _mat(color)
	inst.position = pos
	parent.add_child(inst)
	return inst


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.55, 0.6)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.4, 0)
	lamp.omni_range = 3.5
	lamp.light_energy = 1.1
	lamp.light_color = Color(1.0, 0.9, 0.75)
	lamp.shadow_enabled = true
	add_child(lamp)

	# Lumière qui indique à qui c'est de jouer.
	turn_light = SpotLight3D.new()
	turn_light.spot_range = 2.5
	turn_light.spot_angle = 14.0
	turn_light.light_energy = 4.0
	turn_light.light_color = Color(1.0, 0.95, 0.6)
	turn_light.shadow_enabled = true
	add_child(turn_light)


func _build_table() -> void:
	_box(Vector3(1.3, 0.04, 1.3), Color(0.1, 0.42, 0.2), Vector3(0, -0.02, 0), self)
	_box(Vector3(1.42, 0.06, 1.42), Color(0.35, 0.2, 0.1), Vector3(0, -0.035, 0), self)


func _build_seat(i: int) -> void:
	var root := Node3D.new()
	root.name = "Seat%d" % i
	var angle := -i * PI / 2.0  # sens des aiguilles d'une montre vu du dessus
	root.position = Vector3(sin(angle), 0, cos(angle)) * SEAT_RADIUS
	root.rotation.y = angle     # -Z local pointe vers le centre de la table
	add_child(root)
	seat_roots.append(root)

	var left := _make_hand(SKIN_COLORS[i], true)
	left.position = LEFT_HAND_LOCAL
	root.add_child(left)
	left_hands.append(left)

	var right := _make_hand(SKIN_COLORS[i], false)
	right.position = RIGHT_HAND_LOCAL
	root.add_child(right)
	right_hands.append(right)

	var stack := _make_stack()
	left.add_child(stack)
	stacks.append(stack)

	if i != HUMAN:
		var head := _make_head(SKIN_COLORS[i], HAIR_COLORS[i])
		head.position = HEAD_LOCAL
		root.add_child(head)


func _make_hand(skin: Color, is_left: bool) -> Node3D:
	var hand := Node3D.new()
	_box(Vector3(0.075, PALM_H, 0.085), skin, Vector3(0, PALM_H / 2.0, 0), hand)
	for k in 4:
		_box(Vector3(0.015, 0.016, 0.05), skin, Vector3(-0.027 + k * 0.018, 0.008, -0.065), hand)
	var side := 1.0 if is_left else -1.0
	var thumb := _box(Vector3(0.018, 0.016, 0.04), skin, Vector3(side * 0.045, 0.008, -0.01), hand)
	thumb.rotation.y = side * 0.5
	return hand


# Tas de cartes face cachée posé dans la main gauche.
func _make_stack() -> Node3D:
	var stack := Node3D.new()
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(CARD_W, 1.0, CARD_L)
	body.mesh = body_mesh
	body.material_override = white_mat
	stack.add_child(body)
	var top := MeshInstance3D.new()
	var top_mesh := PlaneMesh.new()
	top_mesh.size = Vector2(CARD_W * 0.9, CARD_L * 0.92)
	top.mesh = top_mesh
	top.material_override = back_mat
	stack.add_child(top)
	return stack


func _make_head(skin: Color, hair: Color) -> Node3D:
	var head := Node3D.new()
	head.rotation.x = -0.25  # regarde la table
	_sphere(0.085, skin, Vector3.ZERO, head)
	var hair_mesh := _sphere(0.09, hair, Vector3(0, 0.03, 0.012), head)
	hair_mesh.scale = Vector3(1, 0.65, 1)
	for side in [-1.0, 1.0]:
		_sphere(0.022, Color.WHITE, Vector3(side * 0.032, 0.012, -0.072), head)
		_sphere(0.011, Color.BLACK, Vector3(side * 0.032, 0.012, -0.092), head)
	_sphere(0.014, skin.darkened(0.15), Vector3(0, -0.012, -0.086), head)
	_box(Vector3(0.035, 0.008, 0.01), Color(0.5, 0.1, 0.1), Vector3(0, -0.04, -0.078), head)
	return head


func _make_card() -> Node3D:
	var card := Node3D.new()
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(CARD_W, CARD_T, CARD_L)
	body.mesh = body_mesh
	body.material_override = white_mat
	card.add_child(body)

	var back := MeshInstance3D.new()
	var back_mesh := PlaneMesh.new()
	back_mesh.size = Vector2(CARD_W * 0.9, CARD_L * 0.92)
	back.mesh = back_mesh
	back.material_override = back_mat
	back.position.y = -CARD_T / 2.0 - 0.0003
	back.rotation.x = PI
	card.add_child(back)

	var face := Label3D.new()
	face.name = "Face"
	face.font = font
	face.font_size = 96
	face.pixel_size = 0.0005
	face.outline_size = 0
	face.double_sided = false
	face.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	face.rotation.x = -PI / 2.0
	face.position.y = CARD_T / 2.0 + 0.0004
	card.add_child(face)
	return card


func _set_card_face(card_node: Node3D, card: int) -> void:
	var face: Label3D = card_node.get_node("Face")
	face.text = Cards.text(card)
	face.modulate = Color(0.8, 0.05, 0.05) if Cards.is_red(card) else Color(0.05, 0.05, 0.05)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 65.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 0.6, SEAT_RADIUS + 0.35), Vector3(0, 0, -0.02))
	_camera_pos = camera.position
	_camera_base = camera.basis


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud_counts = _hud_label(layer, 22, Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT)
	hud_counts.position = Vector2(20, 16)
	hud_turn = _hud_label(layer, 30, Control.PRESET_TOP_WIDE, HORIZONTAL_ALIGNMENT_CENTER)
	hud_turn.offset_top = 16
	hud_message = _hud_label(layer, 38, Control.PRESET_FULL_RECT, HORIZONTAL_ALIGNMENT_CENTER)
	hud_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_message.offset_bottom = -200
	var help := _hud_label(layer, 18, Control.PRESET_BOTTOM_WIDE, HORIZONTAL_ALIGNMENT_CENTER)
	help.offset_top = -40
	help.text = "Clic gauche sur ton tas puis glisse vers le centre : jouer    |    Clic droit sur le tas du centre : taper    |    Échap : libérer la souris"


func _hud_label(layer: CanvasLayer, size: int, preset: Control.LayoutPreset, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	label.set_anchors_and_offsets_preset(preset)
	return label


# --- Boucle --------------------------------------------------------------------

func _process(delta: float) -> void:
	_update_camera(delta)
	_update_turn_light(delta)
	_update_human_hand(delta)

	if _turn_player >= 0:
		_turn_left = maxf(0.0, _turn_left - delta)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0 and not _game_over:
			hud_message.text = ""
	_refresh_hud()


func _update_camera(delta: float) -> void:
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	var mouse := viewport.get_mouse_position()
	var target := Vector2(mouse.x / size.x * 2.0 - 1.0, mouse.y / size.y * 2.0 - 1.0)
	target = target.clamp(Vector2(-1, -1), Vector2(1, 1))
	_sway = _sway.lerp(target, minf(1.0, delta * 6.0))
	camera.basis = Basis(Vector3.UP, -_sway.x * CAMERA_SWAY.x) * _camera_base \
		* Basis(Vector3.RIGHT, -_sway.y * CAMERA_SWAY.y)
	camera.position = _camera_pos + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake
	_shake = move_toward(_shake, 0.0, delta * 0.08)


func _update_turn_light(delta: float) -> void:
	var t := minf(1.0, delta * 5.0)
	_light_pos = _light_pos.lerp(_light_goal, t)
	_light_aim = _light_aim.lerp(_light_aim_goal, t)
	turn_light.look_at_from_position(_light_pos, _light_aim)


func _update_human_hand(delta: float) -> void:
	if hand_locked[HUMAN]:
		return
	var hit = _mouse_on_table()
	if hit == null:
		return
	var target := Vector3(
		clampf(hit.x, TABLE_LIMITS.position.x, TABLE_LIMITS.end.x), HAND_Y,
		clampf(hit.z, TABLE_LIMITS.position.y, TABLE_LIMITS.end.y))
	var hand := right_hands[HUMAN]
	hand.global_position = hand.global_position.lerp(target, minf(1.0, delta * 20.0))


func _refresh_hud() -> void:
	var lines := []
	for p in SEATS:
		lines.append("%s : %d carte%s" % [NAMES[p], counts[p], "s" if counts[p] > 1 else ""])
	hud_counts.text = "\n".join(lines)
	if _turn_player == HUMAN:
		hud_turn.text = "À toi de jouer !  %.1f s" % _turn_left
	elif _turn_player > 0:
		hud_turn.text = "Au tour de %s  %.1f s" % [NAMES[_turn_player], _turn_left]
	else:
		hud_turn.text = ""


func _show_message(text: String, duration := 2.5) -> void:
	hud_message.text = text
	_message_left = duration


# --- Contrôles du joueur ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_grab()
			else:
				_try_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_try_slap()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and _game_over:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


# Point de la table sous le curseur (Vector3), ou null.
func _mouse_on_table():
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	return Plane(Vector3.UP, HAND_Y).intersects_ray(origin, direction)


func _try_grab() -> void:
	if _turn_player != HUMAN or _held_card != null or hand_locked[HUMAN] or counts[HUMAN] == 0:
		return
	var hit = _mouse_on_table()
	if hit == null:
		return
	var deck := _deck_top(HUMAN)
	if Vector2(hit.x - deck.x, hit.z - deck.z).length() > GRAB_RADIUS:
		return
	_held_card = _make_card()
	right_hands[HUMAN].add_child(_held_card)
	_held_card.position = Vector3(0, 0.03, -0.02)
	_held_card.rotation = Vector3(0, 0, PI)  # face cachée
	_grab_point = hit


func _try_release() -> void:
	if _held_card == null:
		return
	var hit = _mouse_on_table()
	var center := Vector3(0, HAND_Y, 0)
	if hit != null and hit.distance_to(center) < _grab_point.distance_to(center) - PLAY_DRAG_DISTANCE:
		server.request_play(HUMAN)  # si accepté, _on_card_played récupère la carte tenue
	_drop_held_card()


func _drop_held_card() -> void:
	if _held_card != null:
		_held_card.queue_free()
		_held_card = null


func _try_slap() -> void:
	if hand_locked[HUMAN]:
		return
	var hit = _mouse_on_table()
	if hit == null or Vector2(hit.x, hit.z).length() > SLAP_RADIUS:
		return
	_drop_held_card()
	_human_slapped = false
	server.request_slap(HUMAN)
	if not _human_slapped:
		# Tape refusée par le serveur (pas de paire) : la main tape puis revient.
		_animate_slap(HUMAN, 1, false)


# --- Réactions aux annonces du serveur ---------------------------------------------

func _on_game_started(start_counts: Array) -> void:
	for p in SEATS:
		counts[p] = start_counts[p]
		_update_stack(p)


func _on_turn_started(player: int, duration: float) -> void:
	_turn_player = player
	_turn_left = duration
	if player != HUMAN:
		_drop_held_card()
		# La main droite de l'ordinateur va chercher la carte sur son tas.
		var tw := _hand_tween(player)
		tw.tween_property(right_hands[player], "global_position", _deck_top(player) + Vector3(0, 0.04, 0), 0.3)
	_light_goal = seat_roots[player].global_position * 0.55 + Vector3(0, 1.3, 0)
	_light_aim_goal = seat_roots[player].to_global(Vector3(0, 0, -0.1))


func _on_card_played(player: int, card: int, center_count: int) -> void:
	_turn_player = -1
	counts[player] -= 1
	_update_stack(player)

	var node: Node3D
	if player == HUMAN and _held_card != null:
		node = _held_card
		_held_card = null
		node.reparent(self)
	else:
		node = _make_card()
		add_child(node)
		node.global_position = right_hands[player].global_position + Vector3(0, 0.03, 0)
		node.rotation = Vector3(0, seat_roots[player].rotation.y, PI)
	_set_card_face(node, card)
	center_cards.append(node)

	var start := node.global_position
	var end := Vector3(randf_range(-0.02, 0.02), center_count * CARD_T + 0.001, randf_range(-0.02, 0.02))
	var tw := node.create_tween().set_parallel()
	tw.tween_method(func(t: float):
		node.global_position = start.lerp(end, t) + Vector3.UP * sin(t * PI) * 0.07,
		0.0, 1.0, GameServer.CARD_TRAVEL)
	tw.tween_property(node, "rotation", Vector3(0, randf_range(-0.4, 0.4), 0), GameServer.CARD_TRAVEL)

	if player != HUMAN:
		var hand := right_hands[player]
		var ht := _hand_tween(player)
		ht.tween_property(hand, "global_position", hand.global_position.lerp(end, 0.5) + Vector3(0, 0.03, 0), 0.18)
		ht.tween_property(hand, "global_position", _rest_pos(player), 0.25)
		ht.tween_callback(func(): hand_locked[player] = false)


func _on_slap_registered(player: int, order: int) -> void:
	if player == HUMAN:
		_human_slapped = true
	_animate_slap(player, order, true)


func _on_pile_taken(player: int, count: int, reason: String) -> void:
	_turn_player = -1
	if player == HUMAN:
		_drop_held_card()
	var who: String = NAMES[player]
	if reason == "timeout" and count == 0:
		_show_message("Temps écoulé ! %s" % ("Tu passes ton tour." if player == HUMAN else who + " passe son tour."))
	elif reason == "timeout":
		if player == HUMAN:
			_show_message("Temps écoulé ! Tu ramasses %d cartes." % count)
		else:
			_show_message("%s : temps écoulé ! %d cartes ramassées." % [who, count])
	elif player == HUMAN:
		_show_message("Tu as tapé en dernier ! Tu ramasses %d cartes." % count)
	else:
		_show_message("%s a tapé en dernier et ramasse %d cartes !" % [who, count])

	# Les cartes du centre volent vers le tas du perdant.
	var target := _deck_top(player)
	var cards := center_cards.duplicate()
	center_cards.clear()
	var stagger := minf(0.03, 0.6 / maxf(1.0, cards.size()))
	for k in cards.size():
		var node: Node3D = cards[k]
		var tw := node.create_tween()
		tw.tween_interval(0.35 + k * stagger)
		tw.tween_property(node, "global_position", target, 0.25)
		tw.tween_callback(node.queue_free)
	var done := create_tween()
	done.tween_interval(0.35 + cards.size() * stagger + 0.25)
	done.tween_callback(func():
		counts[player] += count
		_update_stack(player))

	# Les mains posées sur le tas reviennent.
	for p in SEATS:
		if hand_locked[p]:
			var ht := _hand_tween(p)
			ht.tween_interval(0.3)
			ht.tween_property(right_hands[p], "global_position", _rest_pos(p), 0.25)
			ht.tween_callback(func(): hand_locked[p] = false)


func _on_game_over(loser: int) -> void:
	_game_over = true
	_turn_player = -1
	if loser == HUMAN:
		_show_message("Tu as perdu !\nAppuie sur R pour rejouer", 1e9)
	else:
		_show_message("%s a perdu, tu gagnes !\nAppuie sur R pour rejouer" % NAMES[loser], 1e9)
	if loser >= 0:
		_light_goal = seat_roots[loser].global_position * 0.55 + Vector3(0, 1.3, 0)
		_light_aim_goal = seat_roots[loser].to_global(Vector3(0, 0, -0.1))


# --- Animations ---------------------------------------------------------------------

# Crée l'animation d'une main en annulant la précédente ; la main est bloquée pendant ce temps.
func _hand_tween(p: int) -> Tween:
	var previous: Tween = hand_tweens[p]
	if previous != null and previous.is_valid():
		previous.kill()
	hand_locked[p] = true
	var tw := create_tween()
	hand_tweens[p] = tw
	return tw


func _animate_slap(p: int, order: int, stay: bool) -> void:
	var hand := right_hands[p]
	var toward_seat := (seat_roots[p].global_position * Vector3(1, 0, 1)).normalized()
	var pile_height := center_cards.size() * CARD_T
	var target := toward_seat * 0.035 + Vector3(0, pile_height + 0.002 + (order - 1) * 0.026, 0)
	var raised := hand.global_position.lerp(target, 0.4) + Vector3(0, 0.12, 0)
	var tw := _hand_tween(p)
	tw.tween_property(hand, "global_position", raised, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(hand, "global_position", target, 0.07).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _shake = maxf(_shake, 0.012 if p == HUMAN else 0.005))
	if not stay:
		tw.tween_interval(0.25)
		tw.tween_property(hand, "global_position", _rest_pos(p), 0.2)
		tw.tween_callback(func(): hand_locked[p] = false)


func _update_stack(p: int) -> void:
	var stack := stacks[p]
	var height := counts[p] * CARD_T * 1.2
	stack.visible = counts[p] > 0
	var body: Node3D = stack.get_child(0)
	var top: Node3D = stack.get_child(1)
	body.scale.y = maxf(height, 0.0001)
	body.position.y = PALM_H + height / 2.0
	top.position.y = PALM_H + height + 0.0003


func _deck_top(p: int) -> Vector3:
	return (stacks[p].get_child(1) as Node3D).global_position


func _rest_pos(p: int) -> Vector3:
	return seat_roots[p].to_global(RIGHT_HAND_LOCAL)
