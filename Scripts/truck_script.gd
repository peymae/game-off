extends VehicleBody3D
# speed -> controlled only by the two shifters:
	# main gear (1-5) x range (low / high) = speed ceiling in m/s
	# test keys -> E = shift up, Q = shift down, R = toggle range 

signal gear_changed(main_gear: int, high_range: bool, speed_cap: float)
signal reached_end

@export_group("Gearbox")
# top speed (m/s) for main gears 1..5 in HIGH range
@export var main_gear_caps: Array[float] = [4.0, 8.0, 12.0, 16.0, 20.0]
# LOW range multiplier (HIGH range is always 1.0)
@export var low_range_multiplier: float = 0.5

@export_group("Engine")
# throttle is always "on"
@export var engine_power: float = 6000.0
# how hard the engine drags you back when over the cap
@export var engine_brake_strength: float = 600.0

@export_group("Steering")
@export var max_steer: float = 0.3          # radians
@export var steer_speed: float = 0.8        # how fast the wheel can turn (rad/s)
@export var steer_return_speed: float = 0.4 # how fast it recenters 

@export_group("Route")
@export var route: Path3D
## Measured from node origin to the model's centreline, mid-body and tyre contact
## patch. Re-measure after swapping the model, or the truck steers toward a ghost.
@export var model_offset := Vector3(2.5170898, 0.198, 5.592875)
@export var guide_lookahead: float = 10.0
@export var guide_gain: float = 0.35
@export var guide_max_steer: float = 0.15

const REACH_MARGIN := 1.0

var main_gear: int = 1        # 1..5
var high_range: bool = false  # false = LOW, true = HIGH

var _progress := 0.0
var _finished := false


func _ready() -> void:
	# lower center of mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.5, 0)
	emit_gear()
	if not _has_route():
		push_warning("truck_script: no route set; falling back to manual J/K steering.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: shift_up()
			KEY_Q: shift_down()
			KEY_R: toggle_range()

func _physics_process(delta: float) -> void:
	brake = 0.0  # no brakes

	var forward := -global_transform.basis.z
	var speed := linear_velocity.dot(forward)
	var cap := get_speed_cap()

	# throttle is always on -> ease toward the cap so it doesn't slam into it
	engine_force = engine_power * clampf((cap - speed) / 3.0, 0.0, 1.0)

	# over the cap (e.g. after a downshift or on a downhill) -> engine braking
	var over := speed - cap
	if over > 0.0:
		apply_central_force(-forward * over * engine_brake_strength)

	if _has_route():
		_drive_guide(delta)
	else:
		_update_steering(delta)


# Progress is measured, not integrated: physics decides where the truck is.
func _drive_guide(delta: float) -> void:
	var length := route.curve.get_baked_length()
	if length <= 0.0:
		return
	var center := global_transform * model_offset
	var local_center := route.global_transform.affine_inverse() * center
	_progress = clampf(route.curve.get_closest_offset(local_center), 0.0, length)
	# A physical truck never stops within a centimetre of the endpoint.
	if not _finished and _progress >= length - REACH_MARGIN:
		_finished = true
		reached_end.emit()

	var target := route.global_transform * route.curve.sample_baked(
			minf(_progress + guide_lookahead, length), true)
	var body := Transform3D(global_transform.basis, center)
	var local := body.affine_inverse() * target
	if local.z >= 0.0:
		steering = move_toward(steering, 0.0, steer_return_speed * delta)
		return
	# Positive steering turns left, so a lookahead point on the left needs +steer.
	var err := atan2(-local.x, -local.z)
	var want := clampf(err * guide_gain, -guide_max_steer, guide_max_steer)
	# Reversing flips the steering geometry; positive engine_force reverses on some wheel setups.
	if linear_velocity.dot(-global_transform.basis.z) < -0.5:
		want = -want
	steering = move_toward(steering, want, steer_speed * delta)


func _has_route() -> bool:
	return route != null and route.curve != null


# temp binded to J & K keys 
func _update_steering(delta: float) -> void:
	var input_dir := 0.0
	if Input.is_key_pressed(KEY_J):
		input_dir += 1.0
	if Input.is_key_pressed(KEY_K):
		input_dir -= 1.0

	if input_dir != 0.0:
		steering = clampf(steering + input_dir * steer_speed * delta, -max_steer, max_steer)
	else:
		steering = move_toward(steering, 0.0, steer_return_speed * delta)

# will call these from lever scenes later
func get_speed_cap() -> float:
	var base: float = main_gear_caps[main_gear - 1]
	return base if high_range else base * low_range_multiplier

func shift_up() -> void:
	set_main_gear(main_gear + 1)

func shift_down() -> void:
	set_main_gear(main_gear - 1)

func set_main_gear(gear: int) -> void:
	main_gear = clampi(gear, 1, main_gear_caps.size())
	emit_gear()

func toggle_range() -> void:
	set_range(not high_range)

func set_range(is_high: bool) -> void:
	high_range = is_high
	emit_gear()

func emit_gear() -> void:
	gear_changed.emit(main_gear, high_range, get_speed_cap())
	print("Gear %d | %s range | cap %.1f m/s" % [main_gear, "HIGH" if high_range else "LOW", get_speed_cap()])
