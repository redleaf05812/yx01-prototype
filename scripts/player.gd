extends CharacterBody3D

# 玩家控制器：走 / 跑 / 蹲 / 趴 / 一段跳 / 二段跳 / 冲刺 / 勾爪 / 喷气 / 电池 (M1–M3)。
# 原点 = 脚底中心。2.5D：Z 锁定为 0。
# 假设（文档未给）：身体宽 0.6 m；二段跳 = 与一段跳同速度；空中保持水平速度；
#   勾爪锚点 = 瞄准射线第一个命中的表面，且该表面在 grapple_anchor 组里（平台/阻拦点/通道顶）；
#   冲刺/跑/空中二段跳 在电量为 0 时不可用；喷气需电量 >= 3 格启动，启动时扣 3 格（自定）。

enum Posture { STAND, CROUCH, PRONE }

const HUD_SCRIPT := preload("res://scripts/hud.gd")
const EMP_SCRIPT := preload("res://scripts/emp.gd")

@export var spawn_point := Vector3(9.9, 1.8, 0.0)  # '@' 出生点：第 5 列第 9 行，脚站在地面上
const BODY_WIDTH := 0.6

# 公开状态（HUD 读取）
var hp := Config.max_hp
var battery := float(Config.battery_max)
var ammo := Config.pistol_magazine
var jet_cd_left := 0.0
var stealth_on := false
var stealth_cd_left := 0.0
var in_tunnel := false
var kind := 0  # 0 = 手枪, 1 = EMP
var emp_count := 0
var reloading := false

var _posture := Posture.STAND
var _col: CollisionShape3D
var _shape: BoxShape3D
var _mesh: MeshInstance3D
var _box: BoxMesh
var _jumps_left := 2
var _dash_time_left := 0.0
var _dash_cd_left := 0.0
var _dash_dir := 1.0
var _jet_time_left := 0.0
var _jet_dir := 1.0
var _facing := 1.0
var _fire_cd := 0.0
var _reload_left := 0.0
var _iframes_left := 0.0
var _knock_left := 0.0
var _knock_dir := 1.0
var _running_now := false

# 勾爪
var _anchor := Vector3.ZERO
var _anchor_valid := false
var _grapple_active := false
var _grapple_target := Vector3.ZERO
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _rope: MeshInstance3D
var _rope_mesh: ImmediateMesh
var _grapple_hold := false   # 已勾住：静止挂在锚点上
var _hold_pos := Vector3.ZERO

# 跳跃容错
var _coyote_left := 0.0
var _jump_buffer_left := 0.0

# 射击
var fire_mode := 0    # 0 = 单发, 1 = 三连发
var _recoil := 0.0    # 后坐力：枪口上抬的弧度


func _ready() -> void:
	_ensure_input()
	_build_body()
	_build_grapple_visuals()
	var hud = HUD_SCRIPT.new()
	add_child(hud)
	hud.bind(self)
	global_position = spawn_point
	add_to_group("player")
	emp_count = Config.emp_carry


func _ensure_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("run", [KEY_SHIFT])
	_add_action("crouch", [KEY_C])
	_add_action("prone", [KEY_Z])
	_add_action("grapple", [KEY_T])
	_add_action("jet", [KEY_CTRL])
	_add_action("stealth", [KEY_Q])
	_add_action("reload", [KEY_R])
	_add_action("interact", [KEY_F])
	_add_action("slot_pistol", [KEY_1])
	_add_action("slot_emp", [KEY_3])
	_add_action("fire_mode", [KEY_2])
	_add_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_add_mouse_action("alt_fire", MOUSE_BUTTON_RIGHT)


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


func _build_grapple_visuals() -> void:
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.albedo_color = Color.RED
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	sphere.material = _marker_mat
	_marker = MeshInstance3D.new()
	_marker.mesh = sphere
	_marker.top_level = true
	add_child(_marker)

	var rope_mat := StandardMaterial3D.new()
	rope_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rope_mat.albedo_color = Color(0.9, 0.9, 0.9)
	_rope_mesh = ImmediateMesh.new()
	_rope = MeshInstance3D.new()
	_rope.mesh = _rope_mesh
	_rope.material_override = rope_mat
	_rope.top_level = true
	add_child(_rope)


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
		return
	_posture = wanted
	_set_height(target_h)


# ---------- 战斗 / 交互 ----------

func _add_mouse_action(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# 瞄准方向（从 from 指向鼠标，Z=0）；鼠标与自己重合时用朝向
func _aim_dir(from: Vector3) -> Vector3:
	var raw := _mouse_world_point() - from
	raw.z = 0.0
	return raw.normalized() if raw.length() > 0.01 else Vector3(_facing, 0.0, 0.0)


# 趴下（爬行）和隧道里不能开枪、不能投掷、不能换弹
func _can_act() -> bool:
	return _posture != Posture.PRONE and not in_tunnel


func _update_combat(delta: float) -> void:
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_recoil = move_toward(_recoil, 0.0, Config.recoil_recover_per_sec * delta)
	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			reloading = false
			ammo = Config.pistol_magazine

	if Input.is_action_just_pressed("slot_pistol"):
		kind = 0
	if Input.is_action_just_pressed("slot_emp"):
		kind = 1
	if Input.is_action_just_pressed("fire_mode"):
		fire_mode = 1 - fire_mode

	# 换弹：耗 1 格电，动作 1.2 s；电量不足 1 格不能换弹
	if Input.is_action_just_pressed("reload") and kind == 0 and not reloading \
			and ammo < Config.pistol_magazine and battery >= Config.reload_cost and _can_act():
		battery -= Config.reload_cost
		reloading = true
		_reload_left = Config.reload_time

	if kind == 0:
		var can_shoot := _can_act() and not reloading and ammo > 0 and _fire_cd <= 0.0
		if Input.is_action_just_pressed("fire") and can_shoot:
			if fire_mode == 0:
				_fire_shot()
				_fire_cd = Config.pistol_fire_interval
			else:
				_burst_left = Config.triple_count
		# 三连发：同一把枪连续打出，发与发之间有间隔（每发都会抬枪）
		if _burst_left > 0 and (not _can_act() or reloading or ammo <= 0):
			_burst_left = 0
		if _burst_left > 0 and _fire_cd <= 0.0:
			_fire_shot()
			_burst_left -= 1
			_fire_cd = Config.triple_interval if _burst_left > 0 else Config.pistol_fire_interval
	elif emp_count > 0 and _can_act():
		if Input.is_action_just_pressed("fire"):
			_throw_emp(false)
		elif Input.is_action_just_pressed("alt_fire"):
			_throw_emp(true)


# 手枪：瞬时命中（射线）。一发 = 消耗 1 发弹药；每发后坐力使枪口上抬。
func _fire_shot() -> void:
	ammo -= 1
	break_stealth()  # 隐身中开枪立刻破隐
	var chest := _chest()
	_shoot(chest, _kicked(_aim_dir(chest)))
	_recoil = minf(_recoil + Config.recoil_per_shot, Config.recoil_max)


func _shoot(from: Vector3, dir: Vector3) -> void:
	var end := from + dir * Config.pistol_range
	var q := PhysicsRayQueryParameters3D.create(from, end)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit.position
		var target = hit.collider
		if target.has_method("take_hit"):
			target.take_hit(Config.pistol_damage)
	_spawn_tracer(from, end)


# 后坐力：在瞄准方向上再向上抬 _recoil 弧度（不论朝左朝右，都是往上抬）
func _kicked(dir: Vector3) -> Vector3:
	var side := signf(dir.x) if dir.x != 0.0 else _facing
	var a := _recoil * side
	return Vector3(dir.x * cos(a) - dir.y * sin(a), dir.x * sin(a) + dir.y * cos(a), 0.0).normalized()


# 子弹轨迹：一闪而过的细条
func _spawn_tracer(a: Vector3, b: Vector3) -> void:
	var t := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, maxf(a.distance_to(b), 0.01))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.5)
	bm.material = mat
	t.mesh = bm
	get_parent().add_child(t)
	t.global_position = (a + b) * 0.5
	t.look_at(b, Vector3.BACK)
	get_tree().create_timer(0.06).timeout.connect(t.queue_free)


func _throw_emp(impact: bool) -> void:
	emp_count -= 1
	var chest := _chest()
	var g = Node3D.new()
	g.set_script(EMP_SCRIPT)
	get_parent().add_child(g)
	g.global_position = chest
	g.setup(_aim_dir(chest), impact, self)


# F 交互：只看 X 距离（2.5D）
func _try_interact() -> void:
	for d in get_tree().get_nodes_in_group("door"):
		if absf(d.global_position.x - global_position.x) <= Config.door_interact_range:
			d.interact()
			return


# ---------- 隧道 ----------

# 进入隧道：只能走和爬。其它技能（跳、冲刺、喷气、勾爪、隐身）全部锁住，并立刻结束正在进行的效果。
func set_in_tunnel(v: bool) -> void:
	in_tunnel = v
	if v:
		if stealth_on:
			_stop_stealth()
		_jet_time_left = 0.0
		_dash_time_left = 0.0
		if _grapple_active:
			_end_grapple()
			_update_rope()


# ---------- 隐身 / 受伤 ----------

func _stop_stealth() -> void:
	stealth_on = false
	stealth_cd_left = Config.stealth_internal_cooldown


# 蜘蛛用：返回 INF = 未隐身（用普通视野）；0 = 不可能被发现；否则为水平发现距离
func detection_range() -> float:
	if not stealth_on:
		return INF
	if _posture != Posture.STAND:
		return 0.0
	return Config.detect_range_run_stealth if _running_now else Config.detect_range_walk_stealth


# 开枪时调用（M5 接入）：隐身中开枪立刻破隐
func break_stealth() -> void:
	if stealth_on:
		_stop_stealth()


func take_damage(amount: float, from_x: float) -> void:
	if _iframes_left > 0.0:
		return
	hp -= amount
	_iframes_left = Config.invincible_time
	_knock_dir = signf(global_position.x - from_x)
	if _knock_dir == 0.0:
		_knock_dir = 1.0
	_knock_left = 0.2
	if hp <= 0.0:
		respawn()


# ---------- 勾爪 ----------

func _chest() -> Vector3:
	return global_position + Vector3(0, _shape.size.y * 0.5, 0)


func _mouse_world_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position
	var m := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(m)
	var d := cam.project_ray_normal(m)
	if absf(d.z) < 0.0001:
		return global_position
	var p := o + d * (-o.z / d.z)
	p.z = 0.0
	return p


func _update_aim() -> void:
	var chest := _chest()
	var raw := _mouse_world_point() - chest
	raw.z = 0.0
	var dir := raw.normalized() if raw.length() > 0.01 else Vector3(_facing, 0, 0)
	var query := PhysicsRayQueryParameters3D.create(chest, chest + dir * Config.grapple_range)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	# 第一个命中的表面必须是可勾的锚点（墙/地/天花板会挡住并显示红色）
	_anchor_valid = not hit.is_empty() and hit.collider.is_in_group("grapple_anchor")
	if _anchor_valid:
		_anchor = hit.position
		_marker_mat.albedo_color = Color.GREEN
		_marker.global_position = _anchor
	elif not hit.is_empty():
		_marker_mat.albedo_color = Color.RED
		_marker.global_position = hit.position
	else:
		_marker_mat.albedo_color = Color.RED
		_marker.global_position = chest + dir * Config.grapple_range


func _grapple_step(_delta: float) -> void:
	# 拉向锚点（用胸口对准锚点）；到达或撞到东西就停下，进入「静止悬挂」状态
	var to := _grapple_target - _chest()
	to.z = 0.0
	if to.length() <= Config.grapple_arrive_distance:
		_grab()
		return
	velocity = to.normalized() * Config.grapple_speed
	velocity.z = 0.0
	move_and_slide()
	global_position.z = 0.0
	if get_slide_collision_count() > 0:
		if _touched_anchor():
			_grab()
		else:
			_end_grapple()  # 被墙/平台挡住：绳子断开，直接下落


# 撞到的是锚点（而不是墙）才算勾住
func _touched_anchor() -> bool:
	for i in get_slide_collision_count():
		var c = get_slide_collision(i).get_collider()
		if c is Node and c.is_in_group("grapple_anchor"):
			return true
	return false


# 勾住锚点后：完全静止（不受重力、不能移动），直到再按 T 松开或按跳跃起跳
func _grab() -> void:
	_grapple_active = false
	_grapple_hold = true
	_hold_pos = global_position
	velocity = Vector3.ZERO


func _end_grapple() -> void:
	_grapple_active = false
	_grapple_hold = false
	velocity = Vector3.ZERO


func _update_rope() -> void:
	_rope_mesh.clear_surfaces()
	if not _grapple_active:
		return
	_rope_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_rope_mesh.surface_add_vertex(_chest())
	_rope_mesh.surface_add_vertex(_grapple_target)
	_rope_mesh.surface_end()


# ---------- 主循环 ----------

func _physics_process(delta: float) -> void:
	battery = minf(float(Config.battery_max), battery + Config.battery_regen_per_sec * delta)
	jet_cd_left = maxf(0.0, jet_cd_left - delta)
	_dash_cd_left = maxf(0.0, _dash_cd_left - delta)
	stealth_cd_left = maxf(0.0, stealth_cd_left - delta)
	_iframes_left = maxf(0.0, _iframes_left - delta)

	_update_aim()
	if _grapple_hold:
		if Input.is_action_just_pressed("grapple"):
			_grapple_hold = false  # 再按 T 松开，自由下落
			_update_rope()
			return
		if Input.is_action_just_pressed("jump") and not in_tunnel:
			_grapple_hold = false  # 按跳跃松开：直接起跳（不耗电）
			_coyote_left = Config.coyote_time
			_jumps_left = 2
		else:
			velocity = Vector3.ZERO
			global_position = _hold_pos
			_update_rope()
			return
	if not _grapple_active and not _grapple_hold and Input.is_action_just_pressed("grapple") and _anchor_valid and not in_tunnel:
		_grapple_active = true
		_grapple_target = _anchor
	if _grapple_active:
		_grapple_step(delta)
		_update_rope()
		return

	_update_posture()
	_update_combat(delta)
	if Input.is_action_just_pressed("interact"):
		_try_interact()

	if is_on_floor():
		_jumps_left = 2

	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		_facing = signf(dir)
	var has_power := battery > 0.0001
	var running := Input.is_action_pressed("run") and _posture == Posture.STAND and has_power
	_running_now = running and dir != 0.0

	# 隐身（Q 切换）：启动需 >= 3 格，持续每秒耗 1 格，关闭后 3 s 内置 CD
	if Input.is_action_just_pressed("stealth"):
		if stealth_on:
			_stop_stealth()
		elif stealth_cd_left <= 0.0 and battery >= Config.battery_start_threshold and not in_tunnel:
			stealth_on = true
	if stealth_on:
		battery -= Config.stealth_cost_per_sec * delta
		if battery <= 0.0:
			battery = 0.0
			_stop_stealth()

	# 点按 Shift 冲刺（站立、有电、有 CD）
	if Input.is_action_just_pressed("run") and _posture == Posture.STAND and has_power and _dash_cd_left <= 0.0 and not in_tunnel:
		_dash_time_left = Config.dash_time
		_dash_cd_left = Config.dash_cooldown
		_dash_dir = dir if dir != 0.0 else _facing

	# 喷气（Ctrl）：需要电量 >= 3 格才能启动，启动后不耗电，可用到 0
	if Input.is_action_just_pressed("jet") and _posture != Posture.PRONE \
			and jet_cd_left <= 0.0 and battery >= Config.battery_start_threshold and not in_tunnel:
		_jet_time_left = Config.jet_duration
		jet_cd_left = Config.jet_cooldown
		battery -= Config.jet_battery_cost  # 每次喷气扣 3 格（启动门槛 >= 3 保证不会扣成负数）
		_jet_dir = _facing

	# 跳跃缓冲 / 土狼时间：离开平台后短时间内仍可起跳；落地前按的跳跃会在落地后执行
	_coyote_left = maxf(0.0, _coyote_left - delta)
	if is_on_floor():
		_coyote_left = Config.coyote_time
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_left = Config.jump_buffer_time
	else:
		_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)

	# 跳跃：地面一段 1H；空中二段（总高 2H）需要有电
	if _jump_buffer_left > 0.0 and _posture != Posture.PRONE and _jumps_left > 0 \
			and (is_on_floor() or _coyote_left > 0.0 or has_power) and not in_tunnel:
		velocity.y = Config.jump_velocity
		_jumps_left -= 1
		_jump_buffer_left = 0.0
		_coyote_left = 0.0

	# 可变跳高：松开跳跃键时上升被截短
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= Config.jump_cut_multiplier

	# 重力：下落更快（上升高度不变）
	if not is_on_floor():
		var g := Config.gravity
		if velocity.y < 0.0:
			g *= Config.fall_gravity_multiplier
		velocity.y -= g * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	# 水平：喷气 > 冲刺 > 正常移动
	if _knock_left > 0.0:
		_knock_left -= delta
		velocity.x = _knock_dir * Config.knockback_distance / 0.2
		velocity.y = velocity.y if not is_on_floor() else 0.0
	elif _jet_time_left > 0.0:
		_jet_time_left -= delta
		velocity.x = _jet_dir * Config.jet_distance / Config.jet_duration
		velocity.y = 0.0
	elif _dash_time_left > 0.0:
		_dash_time_left -= delta
		velocity.x = _dash_dir * Config.dash_speed
		velocity.y = 0.0
	elif dir != 0.0:
		velocity.x = dir * _speed_for(_posture, running)
	elif is_on_floor():
		velocity.x = 0.0

	velocity.z = 0.0
	move_and_slide()
	global_position.z = 0.0
	_update_rope()


# 掉进缺口或死亡：整个房间重开（玩家回出生点，蜘蛛等也一起重置）。
# 用 call_deferred：物理回调里不能直接换场景。
func respawn() -> void:
	get_tree().call_deferred("reload_current_scene")
