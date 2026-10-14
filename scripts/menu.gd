# Page de garde : la table à 4 joueurs attend dans la pénombre, le menu est par-dessus.
extends Node

const Main = preload("res://scripts/main.gd")
const Lobby = preload("res://scripts/lobby.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const MIN_BOTS := 1
const MAX_BOTS := 5
const TITLE_RED := Color(0.9, 0.1, 0.1)

var _bot_label: Label
var _bot_suffix: Label
var _main_screen: VBoxContainer
var _options_screen: VBoxContainer
var _display_button: Button
var _lobby: VBoxContainer
var _shade: ColorRect


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var table: Node3D = (load(MAIN_SCENE) as PackedScene).instantiate()
	table.demo_mode = true
	add_child(table)
	_build_menu()


func _build_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_show_return_message.call_deferred(layer)

	var shade := ColorRect.new()  # assombrit la table pour faire ressortir le menu
	shade.color = Color(0, 0, 0, 0.45)
	_shade = shade
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var screens := VBoxContainer.new()
	center.add_child(screens)
	_main_screen = _build_main_screen()
	screens.add_child(_main_screen)
	_options_screen = _build_options_screen()
	_options_screen.visible = false
	screens.add_child(_options_screen)
	_lobby = Lobby.new()
	_lobby.visible = false
	_lobby.closed.connect(func():
		_lobby.visible = false
		_main_screen.visible = true
		_shade.color.a = 0.45)
	screens.add_child(_lobby)
	_change_bots(0)


func _build_main_screen() -> VBoxContainer:
	var column := _column()
	column.add_child(_title("Don't Be NERVOUS !!!", 92))
	column.add_child(_spacer(30))

	# « Jouer contre ◀ 5 ▶ ordis   [Jouer !] »
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	row.add_child(_label("Jouer contre", 40))
	row.add_child(_button("◀", 40, func(): _change_bots(-1)))
	_bot_label = _label("", 48)
	_bot_label.custom_minimum_size.x = 50
	_bot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_bot_label)
	row.add_child(_button("▶", 40, func(): _change_bots(1)))
	_bot_suffix = _label("", 40)
	_bot_suffix.custom_minimum_size.x = 110
	row.add_child(_bot_suffix)
	row.add_child(_spacer(0, 20))
	row.add_child(_solid_button("Jouer !", 42, _start_game))

	column.add_child(_menu_entry(_button("Jouer à plusieurs", 40, _show_lobby), false))
	column.add_child(_menu_entry(_button("Options", 40, func(): _show_options(true)), false))
	column.add_child(_menu_entry(_button("Quitter", 40, func(): get_tree().quit()), false))
	return column


# Options : une seule pour l'instant, fenêtré ou plein écran (mémorisée entre deux lancements).
func _build_options_screen() -> VBoxContainer:
	var column := _column()
	column.add_child(_title("Options", 80))
	column.add_child(_spacer(20))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	row.add_child(_label("Affichage", 40))
	_display_button = _solid_button("", 36, _toggle_fullscreen)
	_display_button.custom_minimum_size.x = 300
	row.add_child(_display_button)
	column.add_child(row)
	column.add_child(_spacer(20))
	column.add_child(_menu_entry(_button("Retour", 40, func(): _show_options(false)), false))
	_refresh_display_button()
	return column


func _show_options(show: bool) -> void:
	_main_screen.visible = not show
	_options_screen.visible = show


func _toggle_fullscreen() -> void:
	Settings.set_fullscreen(not Settings.fullscreen)
	_refresh_display_button()


func _refresh_display_button() -> void:
	_display_button.text = "Plein écran" if Settings.fullscreen else "Fenêtré"


func _change_bots(step: int) -> void:
	Main.bot_count = clampi(Main.bot_count + step, MIN_BOTS, MAX_BOTS)
	_bot_label.text = str(Main.bot_count)
	_bot_suffix.text = "ordi" if Main.bot_count == 1 else "ordis"


func _start_game() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	return label


func _button(text: String, size: int, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_outline_color", Color.BLACK)
	button.add_theme_constant_override("outline_size", 10)
	button.add_theme_color_override("font_hover_color", TITLE_RED)
	button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5, 0.7))
	if action.is_valid():
		button.pressed.connect(action)
	return button


# Entrée de menu centrée ; « grisée » : visible mais inactive (pas encore disponible).
func _menu_entry(button: Button, greyed: bool) -> Control:
	button.disabled = greyed
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _spacer(height: int, width := 0) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(width, height)
	return spacer


func _column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 26)
	return column


func _title(text: String, size: int) -> Label:
	var title := _label(text, size)
	title.add_theme_color_override("font_color", TITLE_RED)
	title.add_theme_constant_override("outline_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


# Vrai bouton plein (fond rouge arrondi, plus clair au survol, plus sombre au clic).
func _solid_button(text: String, size: int, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.8))
	for state in [["normal", TITLE_RED], ["hover", TITLE_RED.lightened(0.2)], ["pressed", TITLE_RED.darkened(0.3)]]:
		var style := StyleBoxFlat.new()
		style.bg_color = state[1]
		style.set_corner_radius_all(14)
		style.set_content_margin_all(12)
		style.content_margin_left = 34
		style.content_margin_right = 34
		style.border_color = Color(1, 1, 1, 0.85)
		style.set_border_width_all(3)
		style.shadow_color = Color(0, 0, 0, 0.6)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 4)
		button.add_theme_stylebox_override(state[0], style)
	button.pressed.connect(action)
	return button


func _show_lobby() -> void:
	_main_screen.visible = false
	_lobby.visible = true
	_shade.color.a = 0.78  # fond plus sombre : beaucoup de texte à lire
	_lobby.open()


# Raison du retour au menu (ex. l'hôte a quitté la partie), affichée en bas de l'écran.
func _show_return_message(layer: CanvasLayer) -> void:
	if OS.has_environment("NET_LOG") and not Net.last_message.is_empty():
		print("[menu] ", Net.last_message)
	if Net.last_message.is_empty():
		return
	var label := _label(Net.last_message, 30)
	label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -70
	Net.last_message = ""
	var fade := label.create_tween()
	fade.tween_interval(6.0)
	fade.tween_property(label, "modulate:a", 0.0, 1.0)
