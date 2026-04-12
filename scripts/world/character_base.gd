# character_base.gd
# Base class for all characters (Player and NPC).
# Provides movement, animation, and basic stats.
# The combat system has been removed; plug in a combat addon as needed.
extends CharacterBody2D
class_name CharacterBase

signal health_changed(current: int, maximum: int)
signal stamina_changed(current: int, maximum: int)

const JUMP_DURATION := 1.2

# ── Stats ─────────────────────────────────────────────────────────────────────
@export var max_health    := 100
@export var max_stamina   := 100
@export var speed         := 10
@export var strength      := 10
@export var defense       := 10
@export var willpower     := 10

var current_health:  int
var current_stamina: int
var status_effects := {}  # kept for sleep-restoration compatibility

# ── Movement / animation state ────────────────────────────────────────────────
var debug             := false
var is_moving         := false
var was_moving        := false
var is_running        := false
var is_jumping        := false
var jump_timer        := 0.0
var last_direction    := Vector2(0, 1)   # default: face down
var last_animation    := "idle"
var anim_direction    := "down"
var animator          = null
var base_speed        := 250.0
var run_speed_multiplier := 1.5
var last_position     := Vector2.ZERO
var is_navigating     := false

func _ready() -> void:
	current_health  = max_health
	current_stamina = max_stamina
	animator        = get_node_or_null("CharacterAnimator")
	last_position   = position

# Override in subclasses
func get_character_id() -> String:
	return ""

func change_facing(_direction: String) -> void:
	pass  # override in subclasses

# ── Direction helpers ─────────────────────────────────────────────────────────
func update_anim_direction() -> void:
	if abs(last_direction.x) > abs(last_direction.y):
		anim_direction = "right" if last_direction.x > 0 else "left"
	else:
		anim_direction = "down" if last_direction.y > 0 else "up"

func get_direction_to_target(target_position: Vector2) -> String:
	var to_target := (target_position - global_position).normalized()
	if abs(to_target.x) > abs(to_target.y):
		return "right" if to_target.x > 0 else "left"
	return "down" if to_target.y > 0 else "up"

func face_target(target: Node) -> void:
	change_facing(get_direction_to_target(target.position))

# ── Movement helpers ──────────────────────────────────────────────────────────
func process_jumping(delta: float) -> void:
	if is_jumping:
		jump_timer -= delta
		if jump_timer <= 0:
			is_jumping = false
			last_animation = ""

func begin_jump() -> void:
	is_jumping  = true
	jump_timer  = JUMP_DURATION
	update_anim_direction()
	if animator:
		animator.set_animation("jump", anim_direction, get_character_id())

func update_position_tracking() -> void:
	if position != last_position:
		last_position = position

# ── Animation ─────────────────────────────────────────────────────────────────
func update_animation(input_vector: Vector2) -> void:
	if is_jumping:
		return
	if input_vector != Vector2.ZERO:
		var old_direction : String = anim_direction
		update_anim_direction()
		var anim_type : String = "run" if is_running else "walk"
		if old_direction != anim_direction or last_animation != anim_type or not was_moving:
			if animator:
				animator.set_animation(anim_type, anim_direction, get_character_id())
			last_animation = anim_type
	elif last_animation != "idle":
		if animator:
			animator.set_animation("idle", anim_direction, get_character_id())
		last_animation = "idle"

# ── Status effects (minimal – for sleep restoration) ─────────────────────────
func remove_status_effect(effect_id: String) -> void:
	if status_effects.has(effect_id):
		status_effects.erase(effect_id)
