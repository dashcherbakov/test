# scripts/autoloads/event_bus.gd
# Decoupled signal relay. Systems emit here; listeners connect here.
extends Node

signal player_died
signal item_collected(item_id: String, quantity: int)
signal score_changed(new_score: int)
signal level_completed(level_id: String)
