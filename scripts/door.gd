extends StaticBody3D

# 门：被纳米疫群侵蚀时 F 无效，EMP 炸掉侵蚀后才能开。开关瞬时完成（占位）。
# 普通射击打不动它（没有 take_hit）。

var infected := true
var is_open := false
var _col: CollisionShape3D
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("door")
	var size := Vector3(Config.H, 2.0 * Config.H, Config.H)
	_col = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_col.shape = box
	add_child(_col)

	_mat = StandardMaterial3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = bm
	add_child(_mesh)
	_refresh()


func interact() -> void:
	if infected:
		return
	is_open = not is_open
	_refresh()


func emp_clear() -> void:
	infected = false
	_refresh()


func _refresh() -> void:
	if _col == null:
		return
	_col.disabled = is_open
	_mesh.visible = not is_open
	_mat.albedo_color = Color(0.6, 0.2, 0.8) if infected else Color(0.5, 0.5, 0.55)
