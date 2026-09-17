# scripts/autoloads/game_manager.gd
# Central game state: scene transitions and pause control.
extends Node

signal scene_changed(scene_path: String)
signal game_paused(is_paused: bool)

var current_level: String = ""
var is_paused: bool = false


func change_scene(path: String) -> void:
	current_level = path
	scene_changed.emit(path)
	get_tree().change_scene_to_file(path)


func set_paused(paused: bool) -> void:
	is_paused = paused
	get_tree().paused = paused
	game_paused.emit(paused)


func quit_game() -> void:
	get_tree().quit()
