# scripts/autoloads/save_manager.gd
# Simple key/value save/load to user://savegame.cfg via ConfigFile.
extends Node

const SAVE_PATH := "user://savegame.cfg"

var save_data: Dictionary = {}


func save_game() -> void:
	var config := ConfigFile.new()
	for key: String in save_data:
		config.set_value("data", key, save_data[key])
	var err := config.save(SAVE_PATH)
	if err != OK:
		push_error("SaveManager: failed to save game (error %d)" % err)


func load_game() -> bool:
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		return false
	save_data.clear()
	for key: String in config.get_section_keys("data"):
		save_data[key] = config.get_value("data", key)
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


func set_value(key: String, value: Variant) -> void:
	save_data[key] = value


func get_value(key: String, default: Variant = null) -> Variant:
	return save_data.get(key, default)
