# Écrans « Jouer à plusieurs » : choix héberger / rejoindre, salon de l'hôte (avec la notice
# et les vérifications réseau), salon d'un ami. Construit en code, affiché par le menu.
extends VBoxContainer

signal closed  # retour au menu principal

const RED := Color(0.9, 0.1, 0.1)
const STATE_COLORS := {"ok": Color(0.3, 0.85, 0.35), "warn": Color(1.0, 0.7, 0.1), "fail": Color(0.95, 0.2, 0.2), "pending": Color(0.6, 0.6, 0.6)}
const STATE_ICONS := {"ok": "●", "warn": "●", "fail": "●", "pending": "○"}

var _choose: VBoxContainer
var _host: VBoxContainer
var _join: VBoxContainer
var _pseudo: LineEdit
var _address: LineEdit
var _status: Label
var _host_players: VBoxContainer
var _join_players: VBoxContainer
var _checks_box: VBoxContainer
var _notice: Label
var _bots := 4
var _bots_label: Label
var _total_label: Label


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	_choose = _build_choose()
	_host = _build_host()
	_join = _build_join()
	for screen in [_choose, _host, _join]:
		add_child(screen)
	_status = _label("", 24)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)
	Net.status_changed.connect(func(text): _status.text = text)
	Net.lobby_changed.connect(_refresh_players)
	Net.checks_changed.connect(_refresh_checks)
	Net.left_lobby.connect(func(reason):
		_show(_join)
		_status.text = reason)
	_show(_choose)


func open() -> void:
	_status.text = ""
	_show(_choose)


func _show(screen: Control) -> void:
	for s in [_choose, _host, _join]:
		s.visible = s == screen


# --- Choix ------------------------------------------------------------------------------

func _build_choose() -> VBoxContainer:
	var column := _column()
	column.add_child(_title("Jouer à plusieurs"))
	var row := _row()
	row.add_child(_label("Ton pseudo", 32))
	_pseudo = _line_edit(Settings.pseudo, "Ton pseudo", 16)
	row.add_child(_pseudo)
	column.add_child(row)
	column.add_child(_solid_button("Héberger une partie", 34, _on_host_pressed))
	column.add_child(_solid_button("Rejoindre une partie", 34, func(): _remember_pseudo(); _show(_join)))
	column.add_child(_flat_button("Retour", 32, func(): closed.emit()))
	return column


func _remember_pseudo() -> void:
	Settings.pseudo = _pseudo.text.strip_edges()
	Settings.save()


func _pseudo_or_default() -> String:
	return Settings.pseudo if not Settings.pseudo.is_empty() else "Joueur"


func _on_host_pressed() -> void:
	_remember_pseudo()
	_bots = Net.MAX_PLAYERS - 1  # par défaut, la table est complétée jusqu'à 6
	_show(_host)
	_refresh_checks()
	Net.host(_pseudo_or_default())


# --- Salon de l'hôte ----------------------------------------------------------------------

func _build_host() -> VBoxContainer:
	var column := _column()
	column.add_child(_title("Ton salon"))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 60)
	column.add_child(columns)

	# À gauche : vérifications et notice.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 760
	left.add_theme_constant_override("separation", 10)
	left.add_child(_label("Pour que tes amis puissent te rejoindre", 28))
	_checks_box = VBoxContainer.new()
	_checks_box.add_theme_constant_override("separation", 6)
	left.add_child(_checks_box)
	left.add_child(_flat_button("Copier l'adresse à donner à tes amis", 26, _copy_address))
	_notice = _label("", 18)
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size.x = 760
	left.add_child(_notice)
	columns.add_child(left)

	# À droite : joueurs, ordinateurs, lancement.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 420
	right.add_theme_constant_override("separation", 14)
	right.add_child(_label("Joueurs", 28))
	_host_players = VBoxContainer.new()
	right.add_child(_host_players)
	var bots_row := _row()
	bots_row.add_child(_label("Ordinateurs", 26))
	bots_row.add_child(_flat_button("◀", 28, func(): _change_bots(-1)))
	_bots_label = _label("", 30)
	bots_row.add_child(_bots_label)
	bots_row.add_child(_flat_button("▶", 28, func(): _change_bots(1)))
	right.add_child(bots_row)
	_total_label = _label("", 22)
	right.add_child(_total_label)
	right.add_child(_solid_button("Lancer la partie", 32, func(): Net.start_match(_bots)))
	right.add_child(_flat_button("Fermer le salon", 26, func():
		Net.leave()
		_status.text = ""
		_show(_choose)))
	columns.add_child(right)
	return column


func _refresh_checks() -> void:
	if _checks_box == null:
		return
	for child in _checks_box.get_children():
		child.queue_free()
	if Net.checks.is_empty():
		return
	var rows := [
		["port", "Port libre sur ce PC"],
		["upnp", "Ouverture du port sur ta box"],
		["public_ip", "Ton adresse publique"],
		["cgnat", "Adresse IP non partagée"],
		["firewall", "Pare-feu Windows"],
	]
	for row_def in rows:
		var check: Dictionary = Net.checks.get(row_def[0], {"state": "pending", "text": ""})
		var row := _row()
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		var icon := _label(STATE_ICONS[check.state], 26)
		icon.add_theme_color_override("font_color", STATE_COLORS[check.state])
		row.add_child(icon)
		var text: String = row_def[1]
		var detail: String = check.text
		if row_def[0] == "firewall":
			detail = "Si Windows demande d'autoriser le jeu, accepte (réseaux privés ET publics)."
		elif check.state == "pending":
			detail = "vérification…"
		var line := _label("%s : %s" % [text, detail], 20)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 700
		row.add_child(line)
		_checks_box.add_child(row)
	var manual: bool = Net.checks.get("upnp", {}).get("state", "") == "warn"
	_notice.text = "" if not manual else (
		"Ouvrir le port à la main :\n"
		+ "1. Ouvre l'interface de ta box dans un navigateur (souvent http://192.168.1.1 ; chez Free : mafreebox.freebox.fr).\n"
		+ "2. Cherche « Redirection de ports » (ou NAT / PAT).\n"
		+ "3. Redirige le port %d en UDP vers l'adresse de ce PC : %s.\n" % [Net.PORT, Net.checks.get("local_ip", "?")]
		+ "4. Le vrai test : un ami essaie de te rejoindre. S'il apparaît dans la liste, c'est gagné.")


func _copy_address() -> void:
	var public: Dictionary = Net.checks.get("public_ip", {})
	if public.get("state", "") == "ok":
		DisplayServer.clipboard_set(public.text)
		_status.text = "Adresse copiée : %s — envoie-la à tes amis." % public.text
	else:
		_status.text = "Adresse publique pas encore connue."


func _change_bots(step: int) -> void:
	var humans := maxi(1, Net.lobby.size())
	_bots = clampi(_bots + step, maxi(0, 2 - humans), Net.MAX_PLAYERS - humans)
	_bots_label.text = str(_bots)
	_total_label.text = "%d joueurs autour de la table" % (humans + _bots)


# --- Salon d'un ami -----------------------------------------------------------------------

func _build_join() -> VBoxContainer:
	var column := _column()
	column.add_child(_title("Rejoindre une partie"))
	var row := _row()
	row.add_child(_label("Adresse de l'hôte", 30))
	_address = _line_edit(Settings.last_address, "ex. 86.245.12.34", 40)
	_address.custom_minimum_size.x = 360
	row.add_child(_address)
	row.add_child(_solid_button("Se connecter", 28, _on_join_pressed))
	column.add_child(row)
	column.add_child(_label("Joueurs dans le salon", 26))
	_join_players = VBoxContainer.new()
	column.add_child(_join_players)
	column.add_child(_flat_button("Retour", 30, func():
		Net.leave()
		_status.text = ""
		_show(_choose)))
	return column


func _on_join_pressed() -> void:
	Settings.last_address = _address.text.strip_edges()
	Settings.save()
	Net.join(Settings.last_address, _pseudo_or_default())


# --- Liste des joueurs ------------------------------------------------------------------------

func _refresh_players() -> void:
	for box in [_host_players, _join_players]:
		if box == null:
			continue
		for child in box.get_children():
			child.queue_free()
		for entry in Net.lobby:
			var text: String = entry.name
			if entry.id == 1:
				text += "  (hôte)"
			elif Net.is_host:
				text += "  — %d ms" % entry.ping
			if entry.id == multiplayer.get_unique_id():
				text += "  ← toi"
			box.add_child(_label(text, 24))
	if Net.is_host:
		_change_bots(0)


# --- Briques d'interface ------------------------------------------------------------------------

func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 20)
	return column


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	return row


func _title(text: String) -> Label:
	var title := _label(text, 64)
	title.add_theme_color_override("font_color", RED)
	title.add_theme_constant_override("outline_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	return label


func _line_edit(text: String, placeholder: String, max_length: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.placeholder_text = placeholder
	edit.max_length = max_length
	edit.custom_minimum_size = Vector2(300, 0)
	edit.add_theme_font_size_override("font_size", 28)
	return edit


func _flat_button(text: String, size: int, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_outline_color", Color.BLACK)
	button.add_theme_constant_override("outline_size", 8)
	button.add_theme_color_override("font_hover_color", RED)
	button.pressed.connect(action)
	return button


func _solid_button(text: String, size: int, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	for state in [["normal", RED], ["hover", RED.lightened(0.2)], ["pressed", RED.darkened(0.3)]]:
		var style := StyleBoxFlat.new()
		style.bg_color = state[1]
		style.set_corner_radius_all(12)
		style.set_content_margin_all(10)
		style.content_margin_left = 28
		style.content_margin_right = 28
		style.border_color = Color(1, 1, 1, 0.85)
		style.set_border_width_all(3)
		button.add_theme_stylebox_override(state[0], style)
	button.pressed.connect(action)
	return button
