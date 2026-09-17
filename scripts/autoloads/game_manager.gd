# scripts/autoloads/game_manager.gd
# Central game state: scene transitions and pause control.
extends Node

signal scene_changed(scene_path: String)
signal game_paused(is_paused: bool)

var current_level: String = ""
var is_paused: bool = false
## Set by whoever starts the next round, and consumed once by the title card:
## a restart drops straight into play instead of showing the controls again.
var skip_startup_once: bool = false


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


## Starts a fresh round in the current scene, from scratch: the reloaded scene
## gets new circles, a new spawner and a score back at zero.
##
## The tree is unpaused first, because the card that asks for a restart is
## showing over a paused game. `skip_startup` is that card's request: the player
## already said yes to another round, so the title card is not shown again.
func restart_scene(skip_startup: bool = false) -> void:
	skip_startup_once = skip_startup
	set_paused(false)
	get_tree().reload_current_scene()


## Reads and clears the skip flag. Consuming rather than reading it is what stops
## a restart's flag from leaking into every later load of the title card.
func consume_skip_startup() -> bool:
	var skip: bool = skip_startup_once
	skip_startup_once = false
	return skip
