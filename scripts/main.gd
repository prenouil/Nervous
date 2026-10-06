# Vue 3D de la partie et contrôles du joueur humain.
# La vue ne connaît pas les règles : elle envoie des demandes au serveur
# et affiche ce que le serveur annonce par ses signaux.
extends Node3D

const GameServer = preload("res://scripts/game_server.gd")
const BotPlayer = preload("res://scripts/bot_player.gd")
const Cards = preload("res://scripts/cards.gd")
const Table = preload("res://scripts/table.gd")

const DEFAULT_BOTS := 3
const MAX_PLAYERS := 6
const HUMAN := 0
const NAMES := ["Toi", "Léon", "Margot", "Igor", "Zoé", "Bruno"]
const SKIN_COLORS := [
	Color(0.96, 0.78, 0.62), Color(0.55, 0.38, 0.26),
	Color(0.98, 0.82, 0.70), Color(0.80, 0.60, 0.42),
	Color(0.70, 0.50, 0.36), Color(0.92, 0.72, 0.56)]
const HAIR_COLORS := [Color.BLACK, Color(0.15, 0.1, 0.08), Color(0.85, 0.35, 0.1), Color(0.9, 0.85, 0.6),
	Color(0.55, 0.1, 0.35), Color(0.4, 0.4, 0.42)]

const SEAT_RADIUS := Table.SEAT_RADIUS
const CARD_W := Cards.CARD_W
const CARD_L := Cards.CARD_L
const CARD_T := 0.0016
const PALM_H := 0.022
const HAND_Y := 0.03
const HEAD_LOCAL := Vector3(0, 0.34, 0.15)

const GRAB_RADIUS := 0.09         # distance au tas pour pouvoir saisir une carte
const PLAY_DRAG_DISTANCE := 0.07  # mouvement minimal vers le centre pour jeter la carte
const CAMERA_SWAY := Vector2(0.22, 0.13)  # amplitude (radians) du regard qui suit la main
const HAND_SPEED := 0.0011        # déplacement de la main (mètres) par pixel de souris
const SWAY_HAND_RANGE := 0.6     # écart de la main (mètres) qui donne le regard maximal
const SHAKE_OFFSET := 0.06        # tremblement de la caméra (mètres) pour une intensité de 1
const SHAKE_ANGLE := 0.12         # et en rotation (radians)
const TRAUMA_DECAY := 1.1         # vitesse de retour au calme après les tapes
const LIGHT_FOLLOW_SPEED := 2.2   # plus c'est bas, plus la lumière de tour est en retard
const TRAUMA_SLAP := 0.5          # tremblement ajouté par une tape adverse...
const TRAUMA_HUMAN_SLAP := 0.6    # ...et par la tienne
const TRAUMA_MAX := 3.0           # les tapes se cumulent jusqu'à cette intensité
const SWAY_NEUTRAL := Vector2(-0.08, 0.41)  # position de la main (x, z) pour laquelle la caméra regarde droit devant
const TENSION_CARDS := 15.0       # nombre de cartes au centre pour une tension maximale
const TENSION_LEAN := 0.16        # la tête se penche vers la table (mètres) à tension maximale
const TREMOR_FROM_CARD := 10     # les mains commencent à trembler à partir de cette carte au centre
const TREMOR_MAX := 0.004         # tremblement des mains (mètres) à tension maximale
const HEAD_RETARGET := Vector2(0.3, 1.2)  # intervalle (s) entre deux changements de regard des visages
const HEAD_CHAOS_CHANCE := 0.2    # chance de regarder ailleurs, au hasard
const HEAD_TURN_SPEED := 7.0      # vitesse de rotation des visages
const LEFT_SWAY_RADIUS := 0.012   # amplitude du balancier de la main gauche (mètres)
const DECK_CLEARANCE := 0.012     # marge de la main droite au-dessus du tas de la main gauche
const HAND_RADIUS := Table.HAND_RADIUS
const WARNING_RED := Color(1.0, 0.1, 0.1)
const WARNING_TREMBLE := 0.005    # tremblement (mètres) d'une main qui touche le cercle
const PICKUP_FLIGHT := 0.85       # durée du vol d'une carte ramassée
const TEARS_DURATION := 2.5      # durée des pleurs d'un perdant (les larmes se succèdent plus vite s'il y en a beaucoup)
const SOUND_GROUPS := {"flop": 5, "flush": 5, "slap": 5, "grunt": 3, "heartbeat": 1, "defeat": 1, "victory": 1, "buzz": 1, "nervous_cry": 1, "ambient": 1}
const HEARTBEAT_BPM := Vector2(70.0, 140.0)    # battement de cœur : rythme au début du penché, puis au maximum
const HEARTBEAT_VOLUME := Vector2(-28.0, -4.0)  # et volume (dB)
const BUZZ_VOLUME := Vector2(-30.0, -14.0)     # grésillement : volume (dB) quand la main effleure le cercle, puis à la limite
const MUSIC_VOLUME := -17.0                    # musique d'ambiance (dB), discrète
const TABLE_LIMITS := Rect2(-0.6, -0.45, 1.2, 0.95)  # zone accessible à la main droite (x, z)

# Nombre d'ordinateurs de la prochaine partie (choisi dans le menu).
static var bot_count := DEFAULT_BOTS

# Mode « attente » : la table à 4 joueurs, dans la pénombre, sert de fond au menu.
var demo_mode := false
var seat_count := 4
var _left_local := Vector3.ZERO    # mains au repos, dans le repère du siège (écart selon le nombre de joueurs)
var _right_local := Vector3.ZERO

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
var heads: Array[Node3D] = []        # visages des ordinateurs (null pour le joueur humain)
var _left_phase: Array[Vector3] = []  # balancier de la main gauche : deux fréquences et une phase
var _slap_sequence: Array[int] = []    # joueurs dont la main est posée sur le tas, dans l'ordre
var _head_targets: Array[Vector3] = []
var _head_retarget: Array[float] = []
var _bot_hand_goal: Array[Vector3] = []  # position annoncée par le serveur pour la main droite des autres joueurs
var hud_nervous: Label
var hud_speed: Label

var _camera_pos := Vector3.ZERO
var _camera_base := Basis()
var _sway := Vector2.ZERO
var _trauma := 0.0   # intensité du tremblement, les tapes s'additionnent
var _tension := 0.0  # monte avec la taille du tas, retombe au ramassage
var _tremor := 0.0   # tremblement des mains, à partir de la 10e carte
var sounds := {}   # nom du groupe -> liste de variantes
var _beat_timer := 0.0
var _tear_mat: StandardMaterial3D
var _buzz_players: Array[AudioStreamPlayer3D] = []
var _music: AudioStreamPlayer
var _camera_forward := Vector3.FORWARD
var _light_pos := Vector3(0, 1.5, 0)
var _light_goal := Vector3(0, 1.5, 0)
var _light_aim := Vector3.ZERO
var _light_aim_goal := Vector3.ZERO

var _held_card: Node3D = null
var _grab_point := Vector3.ZERO
var _hand_target := Vector3.ZERO
var _human_slap_answered := false  # le serveur a répondu à la tape du joueur (touchée ou feinte)
var _turn_player := -1
var _turn_left := 0.0
var _game_over := false

var hud_counts: Label
var hud_turn: Label
var hud_message: Label
var _message_left := 0.0


func _ready() -> void:
	seat_count = 4 if demo_mode else bot_count + 1
	var spread := Table.hand_spread(seat_count)
	_left_local = Vector3(-spread, HAND_Y, Table.HAND_FORWARD)
	_right_local = Vector3(spread, HAND_Y, Table.HAND_FORWARD)
	font.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI", "Arial"])
	white_mat = _mat(Color(0.97, 0.96, 0.92))
	back_mat = _mat(Color(0.15, 0.25, 0.65))
	for i in seat_count:
		counts.append(0)
		hand_locked.append(false)
		hand_tweens.append(null)
		heads.append(null)
		_left_phase.append(Vector3(randf_range(0.7, 1.3), randf_range(0.7, 1.3), randf() * TAU))
		_head_targets.append(Vector3.ZERO)
		_head_retarget.append(0.0)
		_bot_hand_goal.append(Vector3.ZERO)

	_build_environment()
	_build_table()
	for i in seat_count:
		_build_seat(i)
	_build_camera()
	_hand_target = _rest_pos(HUMAN)
	for p in seat_count:
		_bot_hand_goal[p] = _rest_pos(p)
	if demo_mode:
		_dim_for_menu()
		return
	_build_hud()
	_load_sounds()

	server = GameServer.new()
	server.name = "GameServer"
	add_child(server)
	server.game_started.connect(_on_game_started)
	server.turn_started.connect(_on_turn_started)
	server.card_played.connect(_on_card_played)
	server.slap_registered.connect(_on_slap_registered)
	server.slap_missed.connect(_on_slap_missed)
	server.slap_judged.connect(_on_slap_judged)
	server.card_ejected.connect(_on_card_ejected)
	server.pile_taken.connect(_on_pile_taken)
	server.game_over.connect(_on_game_over)
	server.hand_moved.connect(_on_hand_moved)
	server.player_nervous.connect(_on_player_nervous)
	server.speed_changed.connect(_on_speed_changed)
	for i in range(1, seat_count):
		var bot := BotPlayer.new()
		bot.name = "Bot%d" % i
		add_child(bot)
		bot.setup(i, server)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	server.start_game.call_deferred(seat_count)


# Pénombre pour le fond du menu : lampe et ambiance baissées, pas de lumière de tour.
func _dim_for_menu() -> void:
	turn_light.visible = false
	for child in get_children():
		if child is OmniLight3D:
			child.light_energy = 0.45
		elif child is WorldEnvironment:
			child.environment.ambient_light_energy = 0.12
	for p in seat_count:
		counts[p] = 13
		_update_stack(p)


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
	_box(Vector3(Table.TABLE_SIZE, 0.04, Table.TABLE_SIZE), Color(0.1, 0.42, 0.2), Vector3(0, -0.02, 0), self)
	_box(Vector3(Table.TABLE_SIZE + 0.12, 0.06, Table.TABLE_SIZE + 0.12), Color(0.35, 0.2, 0.1), Vector3(0, -0.035, 0), self)
	# Cercle rouge : une main qui franchit la ligne doit taper, sinon elle est nerveuse.
	var ring := TorusMesh.new()
	ring.inner_radius = Table.CIRCLE_RADIUS - 0.005
	ring.outer_radius = Table.CIRCLE_RADIUS + 0.005
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.85, 0.08, 0.08)
	var ring_inst := MeshInstance3D.new()
	ring_inst.mesh = ring
	ring_inst.material_override = ring_mat
	ring_inst.scale = Vector3(1, 0.1, 1)
	ring_inst.position.y = 0.0005
	add_child(ring_inst)


func _build_seat(i: int) -> void:
	var root := Node3D.new()
	root.name = "Seat%d" % i
	var angle := Table.seat_angle(i, seat_count)  # sens des aiguilles d'une montre vu du dessus
	root.position = Vector3(sin(angle), 0, cos(angle)) * SEAT_RADIUS
	root.rotation.y = angle     # -Z local pointe vers le centre de la table
	add_child(root)
	seat_roots.append(root)

	var left := _make_hand(SKIN_COLORS[i], true)
	left.position = _left_local
	root.add_child(left)
	left_hands.append(left)

	var right := _make_hand(SKIN_COLORS[i], false)
	right.position = _right_local
	root.add_child(right)
	right_hands.append(right)

	var stack := _make_stack()
	left.add_child(stack)
	stacks.append(stack)

	if i != HUMAN:
		var head := _make_head(SKIN_COLORS[i], HAIR_COLORS[i])
		head.position = HEAD_LOCAL
		root.add_child(head)
		heads[i] = head


func _make_hand(skin: Color, is_left: bool) -> Node3D:
	var hand := Node3D.new()
	var visual := Node3D.new()  # porte les formes : on le fait trembler sans déplacer la main
	visual.name = "Visual"
	hand.add_child(visual)
	_box(Vector3(0.075, PALM_H, 0.085), skin, Vector3(0, PALM_H / 2.0, 0), visual)
	for k in 4:
		_box(Vector3(0.015, 0.016, 0.05), skin, Vector3(-0.027 + k * 0.018, 0.008, -0.065), visual)
	var side := 1.0 if is_left else -1.0
	var thumb := _box(Vector3(0.018, 0.016, 0.04), skin, Vector3(side * 0.045, 0.008, -0.01), visual)
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
	camera.fov = 65.0 + maxi(0, seat_count - 4) * 4.0  # plus large à 5 ou 6 joueurs, pour garder les visages à l'écran
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 0.6, SEAT_RADIUS + 0.35), Vector3(0, 0, -0.02))
	_camera_pos = camera.position
	_camera_forward = -camera.basis.z
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
	hud_nervous = _hud_label(layer, 150, Control.PRESET_FULL_RECT, HORIZONTAL_ALIGNMENT_CENTER)
	hud_nervous.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_nervous.add_theme_color_override("font_color", WARNING_RED)
	hud_nervous.add_theme_constant_override("outline_size", 24)
	hud_nervous.text = "NERVOUS !!!"
	hud_nervous.visible = false
	hud_speed = _hud_label(layer, 96, Control.PRESET_FULL_RECT, HORIZONTAL_ALIGNMENT_CENTER)
	hud_speed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_speed.add_theme_color_override("font_color", Color(1.0, 0.7, 0.1))
	hud_speed.add_theme_constant_override("outline_size", 20)
	hud_speed.text = "La partie s'accélère !"
	hud_speed.visible = false
	var help := _hud_label(layer, 18, Control.PRESET_BOTTOM_WIDE, HORIZONTAL_ALIGNMENT_CENTER)
	help.offset_top = -40
	help.text = "Clic gauche sur ton tas puis glisse vers le centre : jouer    |    Clic droit : taper (sur la carte du dessus… ou à côté pour feinter)    |    Échap : libérer la souris (clic pour reprendre)"


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
	if demo_mode:
		_update_camera(delta)
		_update_heads(delta)
		_update_left_hands()
		_update_other_hands(delta)
		return
	_update_camera(delta)
	_update_turn_light(delta)
	_update_human_hand(delta)
	_update_heads(delta)
	_update_left_hands()
	_update_other_hands(delta)
	_update_heartbeat(delta)
	_update_hand_warnings()

	if _turn_player >= 0:
		_turn_left = maxf(0.0, _turn_left - delta)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0 and not _game_over:
			hud_message.text = ""
	_refresh_hud()


# La caméra regarde là où pointe la main droite, et tremble selon l'intensité des tapes.
func _update_camera(delta: float) -> void:
	# Main en SWAY_NEUTRAL (un peu à gauche du centre) = regard droit devant.
	var offset := Vector2(_hand_target.x, _hand_target.z) - SWAY_NEUTRAL
	var target := (offset / SWAY_HAND_RANGE).clamp(Vector2(-1, -1), Vector2(1, 1))
	_sway = _sway.lerp(target, minf(1.0, delta * 6.0))
	# Plus le tas grossit, plus on se penche au-dessus de la table.
	var tension_goal := 0.0 if _game_over else clampf(center_cards.size() / TENSION_CARDS, 0.0, 1.0)
	_tension = lerpf(_tension, tension_goal, minf(1.0, delta * 3.0))
	var shake := pow(_trauma, 1.5)
	var roll := randf_range(-1, 1) * SHAKE_ANGLE * shake
	var pitch := randf_range(-1, 1) * SHAKE_ANGLE * shake
	camera.basis = Basis(Vector3.UP, -_sway.x * CAMERA_SWAY.x) * _camera_base \
		* Basis(Vector3.RIGHT, -_sway.y * CAMERA_SWAY.y + pitch) * Basis(Vector3.BACK, roll)
	camera.position = _camera_pos + _camera_forward * TENSION_LEAN * _tension \
		+ Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * SHAKE_OFFSET * shake
	_trauma = maxf(0.0, _trauma - delta * TRAUMA_DECAY)


func _update_turn_light(delta: float) -> void:
	# La lumière traîne derrière le joueur actif et essaie de le rattraper.
	var t := minf(1.0, delta * LIGHT_FOLLOW_SPEED)
	_light_pos = _light_pos.lerp(_light_goal, t)
	_light_aim = _light_aim.lerp(_light_aim_goal, t)
	turn_light.look_at_from_position(_light_pos, _light_aim)


func _update_human_hand(delta: float) -> void:
	var hand := right_hands[HUMAN]
	if hand_locked[HUMAN]:
		# Pendant une animation, la cible suit la main pour éviter un saut ensuite.
		_hand_target = Vector3(hand.global_position.x, HAND_Y, hand.global_position.z)
		return
	var goal := _hand_target
	goal.y = _height_over_deck(goal)
	hand.global_position = hand.global_position.lerp(goal, minf(1.0, delta * 25.0))
	server.update_hand(HUMAN, Vector2(hand.global_position.x, hand.global_position.z))


# Les mains droites des autres joueurs suivent la position annoncée par le serveur
# (quand elles ne sont pas en pleine animation).
func _update_other_hands(delta: float) -> void:
	for p in seat_count:
		if p == HUMAN or hand_locked[p]:
			continue
		var hand := right_hands[p]
		hand.global_position = hand.global_position.lerp(_bot_hand_goal[p], minf(1.0, delta * 6.0))


# Une main qui touche le cercle pulse en rouge et tremble, d'autant plus qu'elle s'enfonce.
func _update_hand_warnings() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	# À partir de la 10e carte au centre, toutes les mains tremblent, de plus en plus.
	var cards_over := center_cards.size() - TREMOR_FROM_CARD + 1
	var tremor_goal := clampf(cards_over / (TENSION_CARDS - TREMOR_FROM_CARD + 1.0), 0.0, 1.0) if cards_over > 0 else 0.0
	_tremor = lerpf(_tremor, tremor_goal, 0.1)
	for p in seat_count:
		(left_hands[p].get_node("Visual") as Node3D).position = _tremor_offset(p * 2, t) * TREMOR_MAX * _tremor
	for p in seat_count:
		var hand := right_hands[p]
		var level := 0.0
		if not hand_locked[p] or hand.has_meta("nervous"):
			var pos := Vector2(hand.global_position.x, hand.global_position.z)
			level = clampf(Table.intrusion(pos) / Table.LINE_TOLERANCE, 0.0, 1.0)
		if hand.has_meta("nervous"):
			level = 1.0
		var visual: Node3D = hand.get_node("Visual")
		visual.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * WARNING_TREMBLE * level \
			+ _tremor_offset(p * 2 + 1, t) * TREMOR_MAX * _tremor
		var pulse := (0.5 + 0.5 * sin(t * 18.0)) * level
		for mesh: MeshInstance3D in visual.get_children():
			(mesh.material_override as StandardMaterial3D).albedo_color = (SKIN_COLORS[p] as Color).lerp(WARNING_RED, pulse)
		if p < _buzz_players.size():  # grésillement électrique discret quand la main touche le cercle
			_buzz_players[p].volume_db = -80.0 if level <= 0.0 or _game_over else lerpf(BUZZ_VOLUME.x, BUZZ_VOLUME.y, level)


# Un même mouvement de souris déplace la main de la même distance sur la table,
# quelle que soit la profondeur.
func _move_hand_target(relative: Vector2) -> void:
	if hand_locked[HUMAN]:
		return
	_hand_target.x = clampf(_hand_target.x + relative.x * HAND_SPEED, TABLE_LIMITS.position.x, TABLE_LIMITS.end.x)
	_hand_target.z = clampf(_hand_target.z + relative.y * HAND_SPEED, TABLE_LIMITS.position.y, TABLE_LIMITS.end.y)


# Hauteur de la main droite : elle monte pour passer par-dessus le tas de la main gauche.
func _height_over_deck(pos: Vector3) -> float:
	if counts[HUMAN] == 0:
		return HAND_Y
	var deck := _deck_top(HUMAN)
	var outside := Vector2(
		maxf(0.0, absf(pos.x - deck.x) - CARD_W / 2.0),
		maxf(0.0, absf(pos.z - deck.z) - CARD_L / 2.0)).length()
	var above := deck.y + DECK_CLEARANCE
	# Montée progressive à l'approche du tas, pleine hauteur dès que la paume le survole.
	var t := clampf((outside - HAND_RADIUS) / 0.04, 0.0, 1.0)
	return maxf(HAND_Y, lerpf(above, HAND_Y, t))


# La main gauche se balance doucement dans un petit cercle, comme un balancier.
func _update_left_hands() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for p in seat_count:
		var phase := _left_phase[p]
		var circle := Vector3(cos(t * phase.x + phase.z), 0, sin(t * phase.y + phase.z)) * LEFT_SWAY_RADIUS
		var bob := Vector3(0, sin(t * phase.x * 2.0 + phase.z) * 0.003, 0)
		left_hands[p].position = _left_local + circle + bob
		left_hands[p].rotation = Vector3(circle.z * 5.0, 0, -circle.x * 5.0)  # s'incline dans le sens du mouvement


# Les visages regardent surtout le joueur actif, parfois le tas, parfois n'importe où.
func _update_heads(delta: float) -> void:
	for p in seat_count:
		var head := heads[p]
		if head == null:
			continue
		_head_retarget[p] -= delta
		if _head_retarget[p] <= 0.0:
			_head_retarget[p] = randf_range(HEAD_RETARGET.x, HEAD_RETARGET.y)
			_head_targets[p] = _pick_head_target(p)
		var direction := _head_targets[p] - head.global_position
		if direction.length() < 0.01:
			continue
		var target_basis := Basis.looking_at(direction, Vector3.UP)
		head.global_basis = head.global_basis.slerp(target_basis, minf(1.0, delta * HEAD_TURN_SPEED))


func _pick_head_target(p: int) -> Vector3:
	var roll := randf()
	if roll < HEAD_CHAOS_CHANCE:
		# Regard perdu : n'importe où devant soi, plus ou moins haut.
		return seat_roots[p].to_global(Vector3(randf_range(-0.8, 0.8), randf_range(-0.1, 0.6), randf_range(-1.2, -0.3)))
	if _turn_player >= 0 and roll < 0.8:
		return right_hands[_turn_player].global_position + Vector3(0, 0.05, 0)
	return Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05))  # le tas


func _refresh_hud() -> void:
	var lines := []
	for p in seat_count:
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
	if demo_mode:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_move_hand_target(event.relative)
	elif event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # un clic reprend le contrôle de la main
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_grab()
			else:
				_try_release()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_try_slap()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M and _game_over:
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		elif event.keycode == KEY_R and _game_over:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _try_grab() -> void:
	if _turn_player != HUMAN or _held_card != null or hand_locked[HUMAN] or counts[HUMAN] == 0:
		return
	var deck := _deck_top(HUMAN)
	if Vector2(_hand_target.x - deck.x, _hand_target.z - deck.z).length() > GRAB_RADIUS:
		return
	_held_card = _make_card()
	right_hands[HUMAN].add_child(_held_card)
	_held_card.position = Vector3(0, 0.03, -0.02)
	_held_card.rotation = Vector3(PI, 0, 0)  # face cachée
	_grab_point = _hand_target
	server.grab_card(HUMAN)  # en jetant sa carte, on peut franchir la ligne du cercle


func _try_release() -> void:
	if _held_card == null:
		return
	var center := Vector3(0, HAND_Y, 0)
	if _hand_target.distance_to(center) < _grab_point.distance_to(center) - PLAY_DRAG_DISTANCE:
		server.request_play(HUMAN)  # si accepté, _on_card_played récupère la carte tenue
	server.release_card(HUMAN)  # main lâchée : 0,5 s pour ressortir du cercle
	_drop_held_card()


func _drop_held_card() -> void:
	if _held_card != null:
		_held_card.queue_free()
		_held_card = null
		server.release_card(HUMAN)


func _try_slap() -> void:
	if hand_locked[HUMAN]:
		return
	_drop_held_card()
	# On tape là où est la main : à côté du tas, c'est une feinte.
	var pos := Vector2(_hand_target.x, _hand_target.z)
	_human_slap_answered = false
	server.request_slap(HUMAN, pos)
	if not _human_slap_answered:
		# Le serveur n'accepte pas de tape en ce moment (ramassage en cours) : simple geste.
		_animate_slap(HUMAN, pos, 0, false)


# --- Réactions aux annonces du serveur ---------------------------------------------

func _on_game_started(start_counts: Array) -> void:
	for p in seat_count:
		counts[p] = start_counts[p]
		_update_stack(p)


func _on_turn_started(player: int, duration: float) -> void:
	_turn_player = player
	_turn_left = duration
	if player != HUMAN:
		_drop_held_card()
		# La main droite de l'ordinateur va chercher la carte sur son tas.
		var tw := _hand_tween(player)
		tw.tween_property(right_hands[player], "global_position", _deck_top(player) + Vector3(0, 0.04, 0), 0.12)
	_light_goal = seat_roots[player].global_position * 0.55 + Vector3(0, 1.3, 0)
	_light_aim_goal = seat_roots[player].to_global(Vector3(0, 0, -0.1))


func _on_card_played(player: int, card: int, center_count: int, landing: Vector2, end_yaw: float) -> void:
	_turn_player = -1
	counts[player] -= 1
	_update_stack(player)

	var seat_yaw := seat_roots[player].rotation.y
	var node: Node3D
	if player == HUMAN and _held_card != null:
		node = _held_card
		_held_card = null
		node.reparent(self)
	else:
		node = _make_card()
		add_child(node)
		node.global_position = right_hands[player].global_position + Vector3(0, 0.03, 0)
	_set_card_face(node, card)
	center_cards.append(node)

	# Le serveur a choisi où la carte atterrit (il en a besoin pour juger les tapes).
	var start := node.global_position
	var end := Vector3(landing.x, center_count * CARD_T + 0.001, landing.y)
	# Retournement vers soi : le bord proche se lève, la face se montre d'abord à l'adversaire d'en face.
	_play_sound("flush", start, -12.0)  # la carte glisse du tas
	var flight := node.create_tween()
	node.set_meta("flight", flight)
	flight.tween_method(func(t: float):
		node.global_position = start.lerp(end, t) + Vector3.UP * sin(t * PI) * 0.09
		node.global_basis = Basis(Vector3.UP, lerp_angle(seat_yaw, end_yaw, t)) * Basis(Vector3.RIGHT, -PI * (1.0 - t)),
		0.0, 1.0, server.card_travel)
	flight.tween_callback(func(): _play_sound("flop", end, -3.0))

	if player != HUMAN:
		var hand := right_hands[player]
		var ht := _hand_tween(player)
		ht.tween_property(hand, "global_position", hand.global_position.lerp(end, 0.5) + Vector3(0, 0.03, 0), 0.18)
		ht.tween_property(hand, "global_position", _rest_pos(player), 0.25)
		ht.tween_callback(func(): hand_locked[player] = false)


# La carte qui recouvrait la paire est éjectée au loin, puis rejoint le tas de son propriétaire.
func _on_card_ejected(player: int, _card: int) -> void:
	var node: Node3D = center_cards.pop_back()
	var previous: Tween = node.get_meta("flight")
	if previous.is_valid():
		previous.kill()
	var start := node.global_position
	var away := Vector2.from_angle(randf() * TAU) * 2.5
	var end := Vector3(away.x, 1.2, away.y - 1.0)  # plutôt vers le fond, loin de la caméra
	var spin_axis := Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)).normalized()
	var start_basis := node.global_basis
	_play_sound("flush", start, -4.0)
	var tw := node.create_tween()
	tw.tween_method(func(t: float):
		node.global_position = start.lerp(end, t) + Vector3.UP * sin(t * PI) * 0.6
		node.global_basis = Basis(spin_axis, t * TAU * 4.0) * start_basis,
		0.0, 1.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(node.queue_free)
	var done := create_tween()
	done.tween_interval(0.7)
	done.tween_callback(func():
		counts[player] += 1
		_update_stack(player))


func _on_slap_registered(player: int, order: int, pos: Vector2) -> void:
	if player == HUMAN:
		_human_slap_answered = true
	_turn_player = -1  # le jeu est bloqué par les mains : plus de compte à rebours
	_slap_sequence.append(player)
	_animate_slap(player, pos, order, true)


# Verdict : on laisse d'abord le tremblement s'éteindre (on voit bien qui a tapé, où et
# dans quel ordre). Ensuite seulement : le message, les cartes en cause qui clignotent en
# rouge, et les mains qui se retirent lentement une par une (la dernière posée d'abord).
func _on_slap_judged(shares: Dictionary, reason: String, highlighted: int) -> void:
	_turn_player = -1
	var calm := create_tween()
	calm.tween_property(self, "_trauma", 0.0, GameServer.SETTLE_TIME).set_ease(Tween.EASE_OUT)
	var sequence := _slap_sequence.duplicate()
	_slap_sequence.clear()
	var reveal := create_tween()
	reveal.tween_interval(GameServer.SETTLE_TIME)
	reveal.tween_callback(func():
		_show_message(_pile_message(shares, reason), GameServer.reveal_time(sequence.size()) - GameServer.SETTLE_TIME + 0.6)
		var n := center_cards.size()
		for i in range(maxi(0, n - highlighted), n):
			_highlight(center_cards[i])
		var k := 0
		for i in range(sequence.size() - 1, -1, -1):
			var p: int = sequence[i]
			var hand := right_hands[p]
			var ht := _hand_tween(p)
			ht.tween_interval(k * GameServer.HAND_LIFT_INTERVAL)
			ht.tween_property(hand, "global_position", hand.global_position + Vector3(0, 0.1, 0), 0.3) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
			ht.tween_property(hand, "global_position", _rest_pos(p), 0.6).set_trans(Tween.TRANS_SINE)
			ht.tween_callback(func(): hand_locked[p] = false)
			k += 1)


# Cadre rouge qui pulse autour de la carte, et carte teintée de rouge.
func _highlight(card_node: Node3D) -> void:
	var frame_mat := StandardMaterial3D.new()
	frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var border := 0.014
	var y := CARD_T / 2.0 + 0.0005
	var strips := [
		[Vector2(CARD_W + border * 2.0, border), Vector3(0, y, CARD_L / 2.0 + border / 2.0)],
		[Vector2(CARD_W + border * 2.0, border), Vector3(0, y, -CARD_L / 2.0 - border / 2.0)],
		[Vector2(border, CARD_L), Vector3(CARD_W / 2.0 + border / 2.0, y, 0)],
		[Vector2(border, CARD_L), Vector3(-CARD_W / 2.0 - border / 2.0, y, 0)]]
	for strip in strips:
		var mesh := PlaneMesh.new()
		mesh.size = strip[0]
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = frame_mat
		inst.position = strip[1]
		card_node.add_child(inst)
	var body: MeshInstance3D = card_node.get_child(0)
	var body_mat: StandardMaterial3D = white_mat.duplicate()
	body.material_override = body_mat
	var pulse := card_node.create_tween().set_loops()
	pulse.tween_method(func(t: float):
		var glow := 0.5 - 0.5 * cos(t * TAU)
		frame_mat.albedo_color = Color(1.0, 0.1, 0.1, lerpf(0.35, 1.0, glow))
		body_mat.albedo_color = white_mat.albedo_color.lerp(Color(1.0, 0.45, 0.45), glow),
		0.0, 1.0, 0.5)


func _on_hand_moved(player: int, pos: Vector2) -> void:
	if player != HUMAN:
		_bot_hand_goal[player] = Vector3(pos.x, HAND_Y, pos.y)


# NERVOUS !!! : grosse annonce au premier nerveux, lumière rouge qui clignote sur chaque main fautive.
func _on_player_nervous(player: int, order: int) -> void:
	_turn_player = -1
	var hand := right_hands[player]
	hand.set_meta("nervous", true)
	var light := OmniLight3D.new()
	light.light_color = WARNING_RED
	light.omni_range = 0.35
	light.position = Vector3(0, 0.08, 0)
	hand.add_child(light)
	light.add_to_group("fx")
	var blink := light.create_tween().set_loops()
	blink.tween_property(light, "light_energy", 6.0, 0.1)
	blink.tween_property(light, "light_energy", 0.0, 0.1)
	_trauma = minf(TRAUMA_MAX, _trauma + 1.0)
	if order == 1:
		_show_banner(hud_nervous)
		_shout_nervous()


# Grosse annonce au centre de l'écran : surgit, tremble, puis s'efface.
func _show_banner(banner: Label) -> void:
	banner.visible = true
	banner.modulate.a = 1.0
	banner.pivot_offset = banner.size / 2.0
	banner.scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(banner, "scale", Vector2(1.25, 1.25), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.12)
	# Tremblement du texte pendant l'annonce.
	tw.tween_method(func(t: float):
		banner.rotation = sin(t * 40.0) * 0.06 * (1.0 - t)
		banner.scale = Vector2.ONE * (1.0 + 0.08 * sin(t * 25.0)),
		0.0, 1.0, 1.3)
	tw.tween_property(banner, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		banner.visible = false
		banner.rotation = 0.0)


# Un perdant pleure : une larme par carte ramassée, alternativement de chaque œil,
# et la tête est secouée de sanglots.
func _cry(p: int, tears: int) -> void:
	var interval := clampf(TEARS_DURATION / tears, 0.06, 0.15)
	var tw := create_tween()
	for k in tears:
		tw.tween_callback(_spawn_tear.bind(p, k % 2 == 0))
		tw.tween_interval(interval)
	var head := heads[p]
	if head != null:
		var sob := head.create_tween()
		sob.tween_method(func(t: float):
			head.position.y = HEAD_LOCAL.y + absf(sin(t * 22.0)) * 0.012,
			0.0, tears * interval + 0.3, tears * interval + 0.3)
		sob.tween_callback(func(): head.position.y = HEAD_LOCAL.y)


func _spawn_tear(p: int, left_eye: bool) -> void:
	if _game_over:
		return
	if _tear_mat == null:
		_tear_mat = StandardMaterial3D.new()
		_tear_mat.albedo_color = Color(0.45, 0.75, 1.0, 0.65)
		_tear_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tear_mat.roughness = 0.05
		_tear_mat.emission_enabled = true
		_tear_mat.emission = Color(0.2, 0.45, 0.8)
		_tear_mat.emission_energy_multiplier = 0.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.011
	mesh.height = 0.032  # goutte allongée
	var tear := MeshInstance3D.new()
	tear.mesh = mesh
	tear.material_override = _tear_mat
	tear.add_to_group("fx")
	add_child(tear)
	var side := -1.0 if left_eye else 1.0
	var start: Vector3
	var cheek: Vector3
	var fall_to: float
	if heads[p] != null:
		start = heads[p].to_global(Vector3(side * 0.032, -0.008, -0.088))  # sous l'œil
		cheek = heads[p].to_global(Vector3(side * 0.05, -0.055, -0.07))    # au bas de la joue
		fall_to = 0.004  # jusqu'à la table
	else:
		# Tes propres larmes : juste devant la caméra, dans les coins bas de l'écran.
		start = camera.global_transform * Vector3(side * 0.07, -0.025, -0.16)
		cheek = camera.global_transform * Vector3(side * 0.075, -0.07, -0.16)
		fall_to = cheek.y - 0.25
		tear.set_meta("own", true)
	var land := Vector3(cheek.x + randf_range(-0.02, 0.02), fall_to, cheek.z + randf_range(-0.02, 0.02))
	tear.global_position = start
	tear.scale = Vector3.ONE * 0.3
	var tw := tear.create_tween()
	# La larme grossit au coin de l'œil, glisse sur la joue, puis tombe.
	var size := 0.6 if tear.has_meta("own") else 1.0  # tes larmes sont tout près de la caméra : plus petites
	tw.tween_property(tear, "scale", Vector3.ONE * size, 0.12)
	tw.tween_property(tear, "global_position", cheek, 0.22).set_ease(Tween.EASE_IN)
	var fall_time := sqrt(2.0 * maxf(0.01, cheek.y - fall_to) / 9.8)
	tw.tween_method(func(t: float):
		tear.global_position = cheek.lerp(land, t)
		tear.global_position.y = lerpf(cheek.y, fall_to, t * t),
		0.0, 1.0, fall_time)
	tw.tween_property(tear, "scale", Vector3(2.2, 0.15, 2.2), 0.1)  # elle s'écrase
	tw.tween_property(tear, "scale", Vector3.ZERO, 0.25)
	tw.tween_callback(tear.queue_free)


func _clear_nervous_hands() -> void:
	for hand in right_hands:
		if hand.has_meta("nervous"):
			hand.remove_meta("nervous")
			for child in hand.get_children():
				if child is OmniLight3D:
					child.queue_free()


func _on_slap_missed(player: int, pos: Vector2) -> void:
	if player == HUMAN:
		_human_slap_answered = true
	_animate_slap(player, pos, 0, false)


func _on_pile_taken(shares: Dictionary, reason: String) -> void:
	_turn_player = -1
	_drop_held_card()
	_clear_nervous_hands()
	# Ta main ressort du cercle, pour ne pas être de nouveau nerveux au tour suivant.
	var out := Table.outside_circle(Vector2(_hand_target.x, _hand_target.z))
	_hand_target = Vector3(out.x, HAND_Y, out.y)
	var takers: Array = shares.keys()
	if reason == "timeout":  # pour les tapes, le verdict a déjà été annoncé
		_show_message(_pile_message(shares, reason))
	# Ceux qui ramassent pleurent : une grosse larme par carte ramassée.
	for p in takers:
		if shares[p] > 0:
			_cry(p, shares[p])

	# Les cartes du centre explosent vers le haut en tournoyant, puis plongent
	# vers le tas de ceux qui ramassent (réparties une par une s'ils sont plusieurs).
	var cards := center_cards.duplicate()
	center_cards.clear()
	var stagger := minf(0.05, 0.7 / maxf(1.0, cards.size()))
	for k in cards.size():
		_fly_to_deck(cards[k], takers[k % takers.size()], 0.35 + k * stagger)
	var done := create_tween()
	done.tween_interval(0.35 + cards.size() * stagger + PICKUP_FLIGHT)
	done.tween_callback(func():
		for p in takers:
			counts[p] += shares[p]
			_update_stack(p))

	# Les mains posées sur le tas reviennent.
	for p in seat_count:
		if hand_locked[p]:
			var ht := _hand_tween(p)
			ht.tween_interval(0.3)
			ht.tween_property(right_hands[p], "global_position", _rest_pos(p), 0.25)
			ht.tween_callback(func(): hand_locked[p] = false)


func _on_game_over(loser: int) -> void:
	_game_over = true
	_turn_player = -1
	_stop_effects()
	_play_end_music(loser != HUMAN)
	if loser == HUMAN:
		_show_message("Tu as perdu !\nR : rejouer     M : menu", 1e9)
	else:
		_show_message("%s a perdu, tu gagnes !\nR : rejouer     M : menu" % NAMES[loser], 1e9)
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


# Tape à la position pos (x, z). order > 0 : la main touche le tas et s'empile sur les
# précédentes ; order = 0 : feinte à côté, la main frappe la table puis remonte.
func _animate_slap(p: int, pos: Vector2, order: int, stay: bool) -> void:
	var hand := right_hands[p]
	var height := 0.001
	if order > 0:
		height = center_cards.size() * CARD_T + 0.002 + (order - 1) * 0.026
	elif pos.length() < 0.2:
		height = center_cards.size() * CARD_T * 0.5  # à côté, mais sur le bord du tas éparpillé
	var target := Vector3(pos.x, height, pos.y)
	var raised := hand.global_position.lerp(target, 0.4) + Vector3(0, 0.12, 0)
	# Après une feinte, la main du joueur ressort juste hors du cercle ; un ordinateur la ramène au repos.
	var outside := Table.outside_circle(pos)
	var back := Vector3(outside.x, HAND_Y, outside.y) if p == HUMAN else _rest_pos(p)
	var tw := _hand_tween(p)
	_play_sound("grunt", _mouth_pos(p), -8.0)  # petit effort de celui qui tape
	tw.tween_property(hand, "global_position", raised, 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(hand, "global_position", target, 0.07).set_ease(Tween.EASE_IN)
	# Chaque tape ajoute du tremblement : des tapes simultanées s'additionnent.
	tw.tween_callback(func():
		_play_sound("slap", target, 0.0 if order > 0 else -4.0)
		_trauma = minf(TRAUMA_MAX, _trauma + (TRAUMA_HUMAN_SLAP if p == HUMAN else TRAUMA_SLAP)))
	if not stay:
		tw.tween_interval(0.15)
		tw.tween_property(hand, "global_position", back, 0.12)
		tw.tween_callback(func(): hand_locked[p] = false)


func _fly_to_deck(node: Node3D, p: int, delay: float) -> void:
	var start := node.global_position
	var target := _deck_top(p)
	# Point de contrôle haut au-dessus du centre : la carte monte haut avant de plonger.
	var control := Vector3(randf_range(-0.15, 0.15), randf_range(0.8, 1.2), randf_range(-0.15, 0.15))
	var start_rot := node.global_basis.get_rotation_quaternion()
	var end_rot := (Basis(Vector3.UP, seat_roots[p].rotation.y) * Basis(Vector3.RIGHT, PI)).get_rotation_quaternion()
	var spin_axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var spins := float(randi_range(2, 4)) * TAU  # tours complets : l'orientation finale est respectée
	var tw := node.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if randf() < 0.5:  # pas un souffle par carte : ce serait trop chargé
			_play_sound("flush", start, -14.0))
	tw.tween_method(func(t: float):
		var u := 1.0 - t
		node.global_position = start * u * u + control * 2.0 * u * t + target * t * t
		node.global_basis = Basis(spin_axis, spins * t) * Basis(start_rot.slerp(end_rot, t))
		node.scale = Vector3.ONE * (1.0 + 0.3 * sin(t * PI)),
		0.0, 1.0, PICKUP_FLIGHT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): _play_sound("flop", target, -10.0))
	tw.tween_callback(node.queue_free)


func _pile_message(shares: Dictionary, reason: String) -> String:
	var takers: Array = shares.keys()
	var total := 0
	for p in takers:
		total += shares[p]
	if takers.size() > 1:
		var names: Array[String] = []
		for p in takers:
			names.append(NAMES[p])
		var listed := ", ".join(names.slice(0, -1)) + " et " + names[-1]
		if reason == "false_slap":
			return "Tape par erreur ! %s se partagent %d cartes." % [listed, total]
		if reason == "nervous":
			return "%s ont été nerveux, ils perdent !\nIls se partagent %d cartes." % [listed, total]
		return "%s n'ont pas tapé : ils se partagent %d cartes !" % [listed, total]
	var p: int = takers[0]
	if reason == "nervous":
		return ("Tu as été nerveux, tu perds !\nTu ramasses %d cartes." % total) if p == HUMAN \
			else ("%s a été nerveux, il perd !\nIl ramasse %d cartes." % [NAMES[p], total])
	if reason == "false_slap":
		return ("Tape par erreur ! Tu ramasses %d cartes." % total) if p == HUMAN \
			else ("%s a tapé par erreur et ramasse %d cartes !" % [NAMES[p], total])
	if reason == "timeout" and total == 0:
		return "Temps écoulé ! " + ("Tu passes ton tour." if p == HUMAN else NAMES[p] + " passe son tour.")
	if reason == "timeout":
		return ("Temps écoulé ! Tu ramasses %d cartes." % total) if p == HUMAN \
			else ("%s : temps écoulé ! %d cartes ramassées." % [NAMES[p], total])
	return ("Tu as tapé en dernier ! Tu ramasses %d cartes." % total) if p == HUMAN \
		else ("%s a tapé en dernier et ramasse %d cartes !" % [NAMES[p], total])


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
	return seat_roots[p].to_global(_right_local)


# Vibration fluide (somme de sinus) plutôt qu'un bruit aléatoire à chaque image ;
# chaque main a son propre rythme.
func _tremor_offset(index: int, t: float) -> Vector3:
	var k := float(index) * 1.37
	return Vector3(
		sin(t * 23.0 + k) + 0.5 * sin(t * 41.0 + k * 2.1),
		0.3 * sin(t * 29.0 + k * 0.7),
		sin(t * 31.0 + k * 1.3) + 0.5 * sin(t * 47.0 + k * 0.4)) / 1.5


# --- Sons ---------------------------------------------------------------------------

# Charge les variantes de chaque son (sounds/flop_1.wav…, sounds/heartbeat.wav…).
func _load_sounds() -> void:
	for group in SOUND_GROUPS:
		var variants: Array[AudioStream] = []
		var count: int = SOUND_GROUPS[group]
		for i in count:
			var path := "res://sounds/%s.wav" % group if count == 1 else "res://sounds/%s_%d.wav" % [group, i + 1]
			if ResourceLoader.exists(path):
				variants.append(load(path))
		sounds[group] = variants
	# Un grésillement par main droite, en boucle, muet tant que la main ne touche pas le cercle.
	if not sounds["buzz"].is_empty():
		for p in seat_count:
			var buzz := AudioStreamPlayer3D.new()
			buzz.stream = sounds["buzz"][0]
			buzz.volume_db = -80.0
			buzz.unit_size = 1.0
			right_hands[p].add_child(buzz)
			buzz.play()
			_buzz_players.append(buzz)
	_start_music()


# Joue une variante au hasard, placée dans la scène, avec un peu de variation de hauteur et de volume.
func _play_sound(group: String, pos: Vector3, volume_db := 0.0) -> void:
	var variants: Array = sounds.get(group, [])
	if _game_over:
		return  # partie finie : plus aucun bruitage
	if variants.is_empty():
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = variants.pick_random()
	player.volume_db = volume_db + randf_range(-2.0, 1.0)
	player.pitch_scale = randf_range(0.9, 1.1)
	player.unit_size = 1.5
	add_child(player)
	player.global_position = pos
	player.finished.connect(player.queue_free)
	player.add_to_group("sfx")
	player.play()


# Son non spatialisé (annonces).
func _play_ui_sound(group: String, volume_db := 0.0) -> void:
	var variants: Array = sounds.get(group, [])
	if _game_over:
		return
	if variants.is_empty():
		return
	var player := AudioStreamPlayer.new()
	player.stream = variants.pick_random()
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.add_to_group("sfx")
	player.play()


func _mouth_pos(p: int) -> Vector3:
	return heads[p].global_position if heads[p] != null else _camera_pos


# Battement de cœur : il démarre quand tu te penches au-dessus du tas, s'accélère et s'amplifie.
func _update_heartbeat(delta: float) -> void:
	if _game_over or _tension < 0.03:
		_beat_timer = 0.0
		return
	_beat_timer += delta
	if _beat_timer >= 60.0 / lerpf(HEARTBEAT_BPM.x, HEARTBEAT_BPM.y, _tension):
		_beat_timer = 0.0
		_play_ui_sound("heartbeat", lerpf(HEARTBEAT_VOLUME.x, HEARTBEAT_VOLUME.y, _tension))


# Fin de partie : on coupe tous les effets visuels et sonores en cours.
func _stop_effects() -> void:
	if _music != null:
		_music.stop()
	DisplayServer.tts_stop()
	for buzz in _buzz_players:
		buzz.stop()
	_trauma = 0.0
	_tremor = 0.0
	hud_nervous.visible = false
	hud_speed.visible = false
	_clear_nervous_hands()
	for node in get_tree().get_nodes_in_group("fx"):
		node.queue_free()
	for player in get_tree().get_nodes_in_group("sfx"):
		player.stop()
		player.queue_free()


func _play_end_music(victory: bool) -> void:
	var variants: Array = sounds.get("victory" if victory else "defeat", [])
	if variants.is_empty():
		return
	var player := AudioStreamPlayer.new()
	player.stream = variants[0]
	player.volume_db = -4.0
	add_child(player)
	player.play()


# Cri « Nervouuuus !!! » : voix de synthèse du système si possible (anglaise de préférence,
# lente et aiguë), sinon le cri synthétisé de secours.
func _shout_nervous() -> void:
	var voices := DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		voices = DisplayServer.tts_get_voices()
	if voices.is_empty():
		_play_ui_sound("nervous_cry", -2.0)
		return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak("Nervous!", voices[0], 100, 1.6, 0.45)


# Nouvelle manche plus rapide : grosse annonce au centre de l'écran.
func _on_speed_changed(level: int) -> void:
	hud_speed.text = "La partie s'accélère !\nNiveau %d" % (level + 1)
	_show_banner(hud_speed)


# Musique d'ambiance en boucle, qui monte doucement au début de la partie.
func _start_music() -> void:
	if sounds["ambient"].is_empty():
		return
	_music = AudioStreamPlayer.new()
	_music.stream = sounds["ambient"][0]
	_music.volume_db = -60.0
	add_child(_music)
	_music.play()
	create_tween().tween_property(_music, "volume_db", MUSIC_VOLUME, 3.0)
