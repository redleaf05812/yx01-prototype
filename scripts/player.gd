extends CharacterBody3D

# 玩家控制器 (M1)：走 / 跑 / 蹲 / 趴 / 一段跳 / 二段跳 / 冲刺。
# 原点 = 脚底中心。2.5D：Z 锁定为 0。
# 假设（文档未给）：身体宽 0.6 m，二段跳 = 与一段跳同速度，空中可保持水平速度。

enum Posture { STAND, CROUCH, PRONE }

@export var spawn_point := Vector3(9.9, 1.8, 0.0)  # '@' 出生点：第 5 列第 9 行，脚站在地面上
const BODY_WIDTH := 0.6

var _posture := Posture.STAND
var _col: CollisionShape3D
var _shape: BoxShape3D
var _mesh: MeshInstance3D
var _box: BoxMesh
var _jumps_left := 2
var _dash_time_left := 0.0
var _dash_cd_left := 0.0
var _dash_dir := 1.0
var _facing := 1.0


func _ready() -> void:
	_ensure_input()
	_build_body()
	global_position = spawn_point


func _ensure_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("run", [KEY_SHIFT])
	_add_action("crouch", [KEY_C])
	_add_action("prone", [KEY_Z])


func _add_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _build_body() -> void:
	_shape = BoxShape3D.new()
	_col = CollisionShape3D.new()
	_col.shape = _shape
	add_child(_col)

	_box = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.9, 0.7)
	_box.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _box
	add_child(_mesh)

	_set_height(Config.stand_height)


func _set_height(h: float) -> void:
	var size := Vector3(BODY_WIDTH, h, Config.H)
	_shape.size = size
	_box.size = size
	_col.position = Vector3(0, h * 0.5, 0)
	_mesh.position = _col.position


func _height_for(p: Posture) -> float:
	match p:
		Posture.CROUCH:
			return Config.crouch_height
		Posture.PRONE:
			return Config.crawl_height
	return Config.stand_height


func _speed_for(p: Posture, running: bool) -> float:
	match p:
		Posture.CROUCH:
			return Config.crouch_speed
		Posture.PRONE:
			return Config.crawl_speed
	return Config.run_speed if running else Config.walk_speed


# 站起来前要确认头顶有空间（否则卡在 0.4H 通道里）。
func _update_posture() -> void:
	var wanted := Posture.STAND
	if Input.is_action_pressed("prone"):
		wanted = Posture.PRONE
	elif Input.is_action_pressed("crouch"):
		wanted = Posture.CROUCH

	var target_h := _height_for(wanted)
	var cur_h := _shape.size.y
	if target_h > cur_h and test_move(global_transform, Vector3(0, target_h - cur_h, 0)):
		return  # 头顶被挡住，保持当前姿态
	_posture = wanted
	_set_height(target_h)


func _physics_process(delta: float) -> void:
	_update_posture()

	_dash_cd_left = maxf(0.0, _dash_cd_left - delta)
	if is_on_floor():
		_jumps_left = 2

	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		_facing = signf(dir)
	var running := Input.is_action_pressed("run") and _posture == Posture.STAND

	# 点按 Shift 冲刺（只在站立时，有 CD）
	if Input.is_action_just_pressed("run") and _posture == Posture.STAND and _dash_cd_left <= 0.0:
		_dash_time_left = Config.dash_time
		_dash_cd_left = Config.dash_cooldown
		_dash_dir = dir if dir != 0.0 else _facing

	# 跳跃：一段 1H，空中再按一次为二段（总高 2H）
	if Input.is_action_just_pressed("jump") and _posture != Posture.PRONE and _jumps_left > 0:
		velocity.y = Config.jump_velocity
		_jumps_left -= 1

	# 重力
	if not is_on_floor():
		velocity.y -= Config.gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	# 水平
	if _dash_time_left > 0.0:
		_dash_time_left -= delta
		velocity.x = _dash_dir * Config.dash_speed
		velocity.y = 0.0
	elif dir != 0.0:
		velocity.x = dir * _speed_for(_posture, running)
	elif is_on_floor():
		velocity.x = 0.0  # 空中保持惯性

	velocity.z = 0.0
	move_and_slide()
	global_position.z = 0.0


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	_jumps_left = 2
	_dash_time_left = 0.0
