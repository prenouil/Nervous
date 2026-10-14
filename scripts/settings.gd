# Réglages du joueur, chargés au lancement (autoload) et mémorisés entre deux sessions.
extends Node

const SETTINGS_PATH := "user://settings.cfg"

var fullscreen := false
var pseudo := ""
var last_address := ""


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		fullscreen = config.get_value("display", "fullscreen", false)
		pseudo = config.get_value("player", "pseudo", "")
		last_address = config.get_value("network", "last_address", "")
	_apply()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply()
	save()


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("player", "pseudo", pseudo)
	config.set_value("network", "last_address", last_address)
	config.save(SETTINGS_PATH)


func _apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
