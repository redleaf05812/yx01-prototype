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
var _stance := Posture.STAND  # 玩家选择的姿态（C/Z 按一下切换）；实际姿态受头顶空间限制
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
var _swing_theta := 0.0     # 摆角：0 = 正下方
var _swing_omega := 0.0     # 摆角速度 (rad/s)
var _rope_len := 1.0        # 绳长 = 勾住时胸口到锚点的距离
var _swing_anchor := Vector3.ZERO
var _anchor_node: Node = null     # 当前瞄准到的锚点
var _grapple_node: Node = null    # 本次勾爪绑定的锚点
var _pullup_left := 0.0           # 悬崖拉上剩余时间
var _pullup_dir := 1.0
var _jump_committed := false      # 一段跳已起跳：空中水平方向锁定，二段跳后恢复自由控制
var _jump_vx := 0.0

# 跳跃容错
var _coyote_left := 0.0
var _jump_buffer_left := 0.0

# 射击
var fire_mode := 0    # 0 = 单发, 1 = 三连发
var _recoil := 0.0    # 后坐力：枪口上抬的弧度
var _burst_left := 0     # 三连发剩余发数


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
	_add_action("slot_weapon2", [KEY_2])  # 2 号武器位（暂无武器）
	_add_action("fire_mode", [KEY_B])
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
	# 按一下切换：C 站⇄蹲，Z 站⇄趴。站不起来（头顶有东西）时保持当前姿态，直到空间足够
	if Input.is_action_just_pressed("prone"):
		_stance = Posture.STAND if _stance == Posture.PRONE else Posture.PRONE
	if Input.is_action_just_pressed("crouch"):
		_stance = Posture.STAND if _stance == Posture.CROUCH else Posture.CROUCH
	var wanted := _stance

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
		if can_shoot and Input.is_action_just_pressed("fire"):
			# 左键 = 主射击：按 B 选的模式（单发 / 三连发）
			if fire_mode == 0:
				_fire_shot()
				_fire_cd = Config.pistol_fire_interval
			else:
				_burst_left = Config.triple_count
		elif can_shoot and Input.is_action_just_pressed("alt_fire"):
			# 右键 = 副射击：三连发（不受 B 的模式影响）
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
	_anchor_node = hit.collider if _anchor_valid else null
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
	# 拉向锚点（用胸口对准锚点）；到达或撞到锚点就结束拉拽；撞到墙则断绳下落
	var to := _grapple_target - _chest()
	to.z = 0.0
	if to.length() <= Config.grapple_arrive_distance:
		_on_anchor_reached()
		return
	velocity = to.normalized() * Config.grapple_speed
	velocity.z = 0.0
	move_and_slide()
	global_position.z = 0.0
	if get_slide_collision_count() > 0:
		if _touched_anchor():
			_on_anchor_reached()
		else:
			_end_grapple()  # 被墙/平台挡住：绳子断开，直接下落


# 撞到的是锚点（不是墙）才算勾住
func _touched_anchor() -> bool:
	for i in get_slide_collision_count():
		var c = get_slide_collision(i).get_collider()
		if c is Node and c.is_in_group("grapple_anchor"):
			return true
	return false


# 到达锚点：悬崖边锚点 → 自动拉上；空中锚点 → 悬挂
func _on_anchor_reached() -> void:
	var kind := "hang"
	if _grapple_node != null:
		kind = str(_grapple_node.get_meta("anchor_kind", "hang"))
	if kind == "ledge":
		_start_pullup()
	else:
		_grab()


func _start_pullup() -> void:
	_grapple_active = false
	_grapple_hold = false
	_pullup_left = Config.pullup_time
	var d := signf(_grapple_target.x - global_position.x)
	_pullup_dir = d if d != 0.0 else _facing
	velocity = Vector3.ZERO


# 空中锚点：勾住后进入摆荡（单摆），保留勾拽时的速度
func _grab() -> void:
	_grapple_active = false
	_grapple_hold = true
	var anc := _grapple_target
	if _grapple_node is Node3D:
		anc = (_grapple_node as Node3D).global_position
	var off := _chest() - anc
	off.z = 0.0
	_swing_anchor = anc
	_rope_len = Config.H  # 挂在锚点下方 1H
	_swing_theta = atan2(off.x, -off.y)
	var tangent := Vector3(cos(_swing_theta), sin(_swing_theta), 0.0)
	_swing_omega = velocity.dot(tangent) / _rope_len
	velocity = Vector3.ZERO


# 摆荡：单摆方程 + A/D 施加侧向推力；身体跟随绳子位置
func _swing_step(delta: float) -> void:
	var pump := Input.get_axis("move_left", "move_right")
	var alpha := -(Config.gravity / _rope_len) * sin(_swing_theta) + pump * Config.swing_pump_accel
	_swing_omega += alpha * delta
	_swing_omega *= exp(-Config.swing_damping * delta)
	_swing_theta += _swing_omega * delta
	if absf(_swing_theta) > Config.swing_max_angle:
		_swing_theta = clampf(_swing_theta, -Config.swing_max_angle, Config.swing_max_angle)
		_swing_omega = 0.0
	var chest := _swing_anchor + Vector3(sin(_swing_theta), -cos(_swing_theta), 0.0) * _rope_len
	global_position = chest - Vector3(0, _shape.size.y * 0.5, 0)
	global_position.z = 0.0
	velocity = Vector3.ZERO


# 松开摆荡：速度 = 切线方向 × 角速度 × 绳长
func _release_swing() -> void:
	var tangent := Vector3(cos(_swing_theta), sin(_swing_theta), 0.0)
	velocity = tangent * _swing_omega * _rope_len
	velocity.z = 0.0
	_grapple_hold = false


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
	stealth_cd_left = maxf(0.0, stealth_cd_left - delta)
	_iframes_left = maxf(0.0, _iframes_left - delta)

	_update_aim()
	if _grapple_hold:
		if Input.is_action_just_pressed("grapple"):
			_release_swing()  # 再按 T 松开，带着摆动速度下落
			_update_rope()
			return
		if Input.is_action_just_pressed("jump") and not in_tunnel:
			_release_swing()  # 按跳跃松开：带摆动速度起跳（不耗电）
			_coyote_left = Config.coyote_time
			_jumps_left = 2
		else:
			_swing_step(delta)
			_update_rope()
			return
	if not _grapple_active and not _grapple_hold and Input.is_action_just_pressed("grapple") and _anchor_valid and not in_tunnel:
		_grapple_active = true
		_grapple_target = _anchor
		_grapple_node = _anchor_node
	if _grapple_active:
		_grapple_step(delta)
		_update_rope()
		return

	# 悬崖拉上：向上 + 向前冲一小段，之后自然落到崖顶
	if _pullup_left > 0.0:
		_pullup_left -= delta
		velocity = Vector3(_pullup_dir * Config.pullup_forward, Config.pullup_up, 0.0)
		move_and_slide()
		global_position.z = 0.0
		if _pullup_left <= 0.0:
			_jumps_left = 2
			_jump_committed = false
		_update_rope()
		return

	_update_posture()
	_update_combat(delta)
	if Input.is_action_just_pressed("interact"):
		_try_interact()

	if is_on_floor():
		_jumps_left = 2
		_jump_committed = false

	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		_facing = signf(dir)
	var has_power := battery > 0.0001
	var running := Input.is_action_pressed("run") and _posture == Posture.STAND
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
		if _jumps_left == 2:
			# 一段跳：方向在起跳时锁定（按住哪边就往哪边，松开就直上直下）
			_jump_committed = true
			_jump_vx = dir * _speed_for(_posture, running) if dir != 0.0 else 0.0
		else:
			# 二段跳：空中完全自由控制
			_jump_committed = false
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
	elif _jump_committed and not is_on_floor():
		velocity.x = _jump_vx
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
