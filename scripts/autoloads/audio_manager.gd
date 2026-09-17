# scripts/autoloads/audio_manager.gd
# Music and SFX playback with dedicated audio buses.
extends Node

signal music_volume_changed(value: float)
signal sfx_volume_changed(value: float)

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	music_player = AudioStreamPlayer.new()
	music_player.bus = MUSIC_BUS
	add_child(music_player)
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = SFX_BUS
	add_child(sfx_player)


func play_music(stream: AudioStream, volume_db: float = 0.0) -> void:
	music_player.stream = stream
	music_player.volume_db = volume_db
	music_player.play()


func stop_music() -> void:
	music_player.stop()


func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = SFX_BUS
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func set_music_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), linear_to_db(clampf(value, 0.0, 1.0)))
	music_volume_changed.emit(value)


func set_sfx_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(clampf(value, 0.0, 1.0)))
	sfx_volume_changed.emit(value)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
