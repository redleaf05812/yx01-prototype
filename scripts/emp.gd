extends Node3D

# EMP 手雷：左键 = 延时（落地后 1.5 s 爆）；右键 = 撞击即爆。最远 6H，撞到表面就停下。
# 爆炸：3H 半径内的蜘蛛瘫痪 5 s；侵蚀的门被清除（之后可以用 F 打开）。

var _dir := Vector3.RIGHT
var _impact := false
var _travel_left := 0.0
var _landed := false
var _fuse_left := 0.0
var _done := false
var _ex: RID


func _ready() -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.2)
	sm.material = mat
	m.mesh = sm
	add_child(m)


func setup(dir: Vector3, impact: bool, owner_body: CollisionObject3D) -> void:
	_dir = Vector3(dir.x, dir.y, 0.0).normalized()
	_impact = impact
	_travel_left = Config.emp_throw_range
	_ex = owner_body.get_rid()


func _physics_process(delta: float) -> void:
	if not _landed:
		_fly(delta)
		return
	if not _impact:
		_fuse_left -= delta
		if _fuse_left <= 0.0:
			_explode()


func _fly(delta: float) -> void:
	var step_len := minf(Config.emp_throw_speed * delta, _travel_left)
	var from := global_position
	var to := from + _dir * step_len
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [_ex]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit.position
		_land()
		return
	global_position = to
	_travel_left -= step_len
	if _travel_left <= 0.001:
		_land()


func _land() -> void:
	_landed = true
	if _impact:
		_explode()
	else:
		_fuse_left = Config.emp_fuse_time


func _explode() -> void:
	if _done:
		return
	_done = true
	for s in get_tree().get_nodes_in_group("spider"):
		if s.global_position.distance_to(global_position) <= Config.emp_radius:
			s.stun(Config.emp_stun_time)
	for d in get_tree().get_nodes_in_group("door"):
		if d.global_position.distance_to(global_position) <= Config.emp_radius:
			d.emp_clear()
	_show_blast()
	queue_free()


func _show_blast() -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = Config.emp_radius
	sm.height = Config.emp_radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.25)
	sm.material = mat
	m.mesh = sm
	get_parent().add_child(m)
	m.global_position = global_position
	get_tree().create_timer(0.3).timeout.connect(m.queue_free)
