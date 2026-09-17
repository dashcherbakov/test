# scripts/2d/chaser_settings.gd
# Every tunable parameter of the chasing dot, in one resource.
#
# The dot is recreated every few seconds, so its parameters live here rather
# than on the prefab: the spawner stamps this resource onto each new dot and
# onto the one already in flight, which is what lets the control panel change
# the chase while it is happening.
#
# DotParamsPanel builds one slider per exported number below, so adding a
# parameter here adds a control with no UI code to touch.
class_name ChaserSettings
extends Resource

@export_group("Motion")
## Resistance to a change of velocity. This is the inertia: a heavier dot needs
## more thrust to turn the same corner.
@export_range(0.1, 40.0, 0.1) var mass: float = 4.0
## Turning authority, in force units. Acceleration is thrust / mass, so a lower
## thrust means wider laps: loop radius is roughly speed^2 / acceleration.
@export_range(0.0, 16000.0, 10.0) var thrust: float = 6100.0
## Top speed. With the thrust it fixes the tightest loop the dot can fly.
@export_range(0.0, 1600.0, 10.0) var max_speed: float = 800.0
## Fraction of top speed lost per second. The dot keeps its inertia, but the
## loops it can hold tighten - this is what turns "orbits forever" into a hit.
## 0 = orbits indefinitely.
@export_range(0.0, 2.0, 0.001) var speed_bleed_per_second: float = 0.088
## Velocity lost per second. Note the dot uses DAMP_MODE_REPLACE, so this value
## is the whole story (the project default no longer adds to it).
@export_range(0.0, 4.0, 0.01) var linear_damp: float = 0.05
## Drawn size, and the radius of its collision shape.
@export_range(2.0, 48.0, 1.0) var radius: float = 8.0

@export_group("Scoring")
## Score rate a dot starts at, in points per second. The live rate climbs from
## here, and it is also the baseline the multiplier that scales distance scoring
## is measured against: at spawn the multiplier is exactly 1.
@export_range(1.0, 500.0, 1.0) var points_per_second: float = 10.0
## Points per second added to the live rate for every second a dot stays alive.
## This is what turns "distance covered" into "distance covered, and worth more
## by the second", so a long spiralling flight outscores a short straight one
## even over the same ground. Reset to nothing on every spawn and every
## collision, which is what "the rate resets" means.
@export_range(0.0, 200.0, 1.0) var rate_gain_per_second: float = 4.0

@export_group("Round")
## Dots per round. The counter along the top counts up to this, and the last dot
## to collide ends the game. One is the shortest possible round.
@export_range(1, 50, 1) var max_dots: int = 5

@export_group("Trail")
## Draw the path the dot took at all.
@export var trail_enabled: bool = true
## Seconds of path to keep. The line is sampled once per physics tick, so this is
## turned into a point count rather than being exposed as one.
@export_range(0.0, 10.0, 0.25) var trail_seconds: float = 2.0
@export_range(1.0, 12.0, 0.5) var trail_width: float = 2.0
@export var trail_color: Color = Color(1.0, 0.72, 0.25, 0.45)
## How long a dead dot's path lingers before it is freed.
@export_range(0.0, 5.0, 0.1) var trail_fade_seconds: float = 1.2
