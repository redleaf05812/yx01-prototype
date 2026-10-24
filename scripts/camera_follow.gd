extends Camera3D

# 相机沿 X 跟随玩家，但不超出房间边界。Y/Z 保持场景里设定的值。
@export var target_path: NodePath

func _process(_delta: float) -> void:
	var target := get_node_or_null(target_path) as Node3D
	if target == null:
		return
	var half_view := Config.H * 20.0 * 0.5   # 视野宽 20H 的一半
	var room_w := Config.H * 36.0
	var x := clampf(target.global_position.x, half_view, room_w - half_view)
	global_position = Vector3(x, global_position.y, global_position.z)
