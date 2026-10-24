extends CharacterBody3D

# 小型蜘蛛：巡逻两点往返（到点停 1 s）→ 发现玩家后追击攻击 → 失去目标后原地搜索 6–8 s → 回巡逻。
# 与玩家互不碰撞（蜘蛛很矮，不挡潜行路线）。原点 = 脚底中心。

enum State { PATROL, CHASE, SEARCH }

@export var patrol_left := 20.0
@export var patrol_right := 35.0

var hp := 0.0
var _state := State.PATROL
var _player
var _facing := 1.0
var _target_x := 0.0
var _pause_left := 0.0
var _search_left := 0.0
var _attack_cd := 0.0
var _size := Vector3.ZERO


func _ready() -> void:
	hp = Config.spider_hp
	_size = Vector3(0.8, 0.5, Config.H)

	var box := BoxShape3D.new()
	box.size = _size
	var col := CollisionShape3D.new()
	col.shape = box
	col.position = Vector3(0, _size.y * 0.5, 0)
	add_child(col)

	var mesh := BoxMesh.new()
	mesh.size = _size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = col.position
	add_child(mi)

	_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		add_collision_exception_with(_player)
	_target_x = patrol_right


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if not is_on_floor():
		velocity.y -= Config.gravity * delta
	else:
		velocity.y = 0.0

	var seen := _can_see_player()
	match _state:
		State.PATROL:
			if seen:
				_set_state(State.CHASE)
			else:
				_patrol(delta)
		State.CHASE:
			if seen:
				_chase()
			else:
				_set_state(State.SEARCH)
		State.SEARCH:
			if seen:
				_set_state(State.CHASE)
			else:
				velocity.x = 0.0
				_search_left -= delta
				if _search_left <= 0.0:
					_set_state(State.PATROL)

	velocity.z = 0.0
	move_and_slide()
	global_position.z = 0.0


func _set_state(s: State) -> void:
	_state = s
	match s:
		State.SEARCH:
			_search_left = randf_range(Config.spider_search_time_min, Config.spider_search_time_max)
		State.PATROL:
			# 回巡逻：走向离自己最近的那个端点
			_target_x = patrol_left if absf(global_position.x - patrol_left) < absf(global_position.x - patrol_right) else patrol_right
			_pause_left = 0.0


func _patrol(delta: float) -> void:
	if _pause_left > 0.0:
		_pause_left -= delta
		velocity.x = 0.0
		return
	var dx := _target_x - global_position.x
	if absf(dx) < 0.1:
		_pause_left = Config.spider_patrol_pause
		_target_x = patrol_left if _target_x == patrol_right else patrol_right
		velocity.x = 0.0
		return
	_facing = signf(dx)
	velocity.x = _facing * Config.spider_speed


func _chase() -> void:
	var dx: float = _player.global_position.x - global_position.x
	if dx != 0.0:
		_facing = signf(dx)
	if absf(dx) <= Config.spider_attack_range:
		velocity.x = 0.0
		if _attack_cd <= 0.0:
			_player.take_damage(Config.spider_attack_damage, global_position.x)
			_attack_cd = Config.spider_attack_interval
	else:
		velocity.x = _facing * Config.spider_speed


# 发现规则：
#  - 没隐身：正面 90° 锥形、1080 uu(6H) 内
#  - 隐身：蹲/趴永不发现；站立走 2H 内；奔跑 5H 内（只看水平距离）
func _can_see_player() -> bool:
	if _player == null:
		return false
	var dx: float = _player.global_position.x - global_position.x
	var dy: float = _player.global_position.y - global_position.y
	var r: float = _player.detection_range()
	if r == INF:
		var v := Vector2(dx, dy)
		var dist := v.length()
		if dist > Config.spider_vision_range:
			return false
		if dist < 0.01:
			return true
		var cos_ang := (v / dist).dot(Vector2(_facing, 0.0))
		return cos_ang >= cos(deg_to_rad(Config.spider_vision_angle * 0.5))
	return r > 0.0 and absf(dx) <= r


func take_hit(dmg: float) -> void:
	hp -= dmg
	if hp <= 0.0:
		queue_free()
