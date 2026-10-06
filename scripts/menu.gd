# Page de garde : la table à 4 joueurs attend dans la pénombre, le menu est par-dessus.
extends Node

const Main = preload("res://scripts/main.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const MIN_BOTS := 1
const MAX_BOTS := 5
const TITLE_RED := Color(0.9, 0.1, 0.1)

var _bot_label: Label
var _bot_suffix: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var table: Node3D = (load(MAIN_SCENE) as PackedScene).instantiate()
	table.demo_mode = true
	add_child(table)
	_build_menu()


func _build_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var shade := ColorRect.new()  # assombrit la table pour faire ressortir le menu
	shade.color = Color(0, 0, 0, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 26)
	center.add_child(column)

	var title := _label("Don't Be NERVOUS !!!", 92)
	title.add_theme_color_override("font_color", TITLE_RED)
	title.add_theme_constant_override("outline_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(_spacer(30))

	# « Jouer contre ◀ 3 ▶ ordis   GO »
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
	var go := _button("GO", 44, _start_game)
	go.add_theme_color_override("font_color", TITLE_RED)
	go.custom_minimum_size.x = 130
	row.add_child(go)

	column.add_child(_menu_entry(_button("Jouer à plusieurs", 40, Callable()), true))
	column.add_child(_menu_entry(_button("Options", 40, Callable()), true))
	column.add_child(_menu_entry(_button("Quitter", 40, func(): get_tree().quit()), false))
	_change_bots(0)


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


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer
