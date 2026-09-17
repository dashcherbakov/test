# scripts/2d/chaser_settings.gd
# Every tunable parameter of the chasing dot, in one resource.
#
# The dot is recreated every few seconds, so its parameters live here rather
# than on the prefab: the spawner stamps this resource onto each new dot and
# onto the one already in flight, which is what lets the control panel change
# the chase while it is happening.
#
# DotParamsPanel builds one slider per exported float below, so adding a
# parameter here adds a control with no UI code to touch.
class_name ChaserSettings
extends Resource

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
