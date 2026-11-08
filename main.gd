extends Node3D

@onready var left_view := $SubViewport2/LeftView
@onready var front_view := $SubViewport/FrontView
@onready var cam := $Camera3D

const VIEW_ANGLES := [75.0, 0.0, -75.0]
var current_view := 1
var tween: Tween

func _ready() -> void:
	cam.rotation_degrees = Vector3(0, VIEW_ANGLES[current_view], 0) 
	
func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_pressed("right"):
		swap_view(1) 

	if Input.is_action_pressed("left"):
		swap_view(-1) 
	
func swap_view(step: int): 
	var new_view := clampi(current_view + step, 0, VIEW_ANGLES.size() - 1)
	if new_view == current_view: return
		
	current_view = new_view 
		
	if tween:
		tween.kill() 
		
	tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(cam, "rotation_degrees:y", VIEW_ANGLES[current_view], 0.3)

	
	
	
