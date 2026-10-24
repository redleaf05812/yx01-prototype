extends Node3D

# 房间 01 Blockout：根据文档第三节的元素表，用色块生成几何体（运行时生成，不用手摆）。
# 坐标约定：1 格 = 1H = Config.H 米。格子 (col, row)，col 从左 0 起，row 从上 0 起。
# 房间 36 格宽 × 11 格高。地面在 row 10。

const COLS := 36
const ROWS := 11

const COLOR_WALL := Color(0.35, 0.35, 0.38)
const COLOR_FLOOR := Color(0.45, 0.45, 0.5)
const COLOR_PLATFORM := Color(0.6, 0.6, 0.7)
const COLOR_BARRIER := Color(0.9, 0.5, 0.15)   # XX 阻拦点
const COLOR_TUNNEL := Color(0.55, 0.4, 0.25)   # .. 低矮通道顶
const COLOR_INFECTED := Color(0.4, 0.9, 0.3)   # ~ 感染区
const COLOR_DOOR := Color(0.6, 0.2, 0.8)       # || 侵蚀的门

var H: float


func _ready() -> void:
	H = Config.H
	_build_room()
	_build_elements()
	_build_kill_zone()


# 通用：生成一个带碰撞的长方体。x0..x1, y0..y1 为米，z 厚度 1 格。
func _add_box(x0: float, x1: float, y0: float, y1: float, color: Color, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = label
	var depth := H
	var size := Vector3(x1 - x0, y1 - y0, depth)
	var center := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0)

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	body.add_child(mesh_inst)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	body.position = center
	add_child(body)


# 按格子坐标加一个方块：左上角格 (col,row)，宽 w 格，高 h 格。
func _cell_box(col: int, row: int, w: int, h: int, color: Color, label: String) -> void:
	var x0 := col * H
	var x1 := (col + w) * H
	var y_top := (ROWS - row) * H
	var y_bot := (ROWS - (row + h)) * H
	_add_box(x0, x1, y_bot, y_top, color, label)


func _build_room() -> void:
	# 外墙：上、下（地面另算）、左、右
	_cell_box(0, 0, COLS, 1, COLOR_WALL, "Ceiling")
	_cell_box(0, 0, 1, ROWS, COLOR_WALL, "WallLeft")
	_cell_box(COLS - 1, 0, 1, ROWS, COLOR_WALL, "WallRight")

	# 地面：row 10，挖掉感染区的 3 格（col 7..9）
	_cell_box(0, ROWS - 1, 7, 1, COLOR_FLOOR, "FloorLeft")
	_cell_box(10, ROWS - 1, COLS - 10 - 1, 1, COLOR_FLOOR, "FloorRight")


func _build_elements() -> void:
	# 感染区：地面缺口，3H 宽（col 7..9）。缺口底部画一块绿色做提示。
	# 缺口里只放一块无碰撞的绿色视觉提示，不能站、要跳过去
	var marker := MeshInstance3D.new()
	marker.name = "InfectedGapMarker"
	var m := BoxMesh.new()
	m.size = Vector3(3 * H, 0.2, H)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_INFECTED
	m.material = mat
	marker.mesh = m
	marker.position = Vector3((7 + 1.5) * H, -0.1, 0.0)
	add_child(marker)

	# 平台：col 13..16, row 4，宽 4 格
	_cell_box(13, 4, 4, 1, COLOR_PLATFORM, "Platform")

	# 阻拦点 XX：col 23..24, 从地面往上 3H 高
	_add_box(23 * H, 25 * H, 1.8, 1.8 + 3 * H, COLOR_BARRIER, "Barrier")

	# 低矮通道顶：col 18..19，离地 0.4H 净高（0.72 m）
	_add_box(18 * H, 20 * H, 1.8 + 0.4 * H, 1.8 + 0.4 * H + 2 * H, COLOR_TUNNEL, "TunnelRoof")

	# 侵蚀的门 ||：col 29，从地面往上 2H 高
	_add_box(29 * H, 30 * H, 1.8, 1.8 + 2 * H, COLOR_DOOR, "InfectedDoor")


# 感染区缺口下方的死亡区：掉进去就回到出生点（玩家脚本接入后替换）。
func _build_kill_zone() -> void:
	var area := Area3D.new()
	area.name = "KillZone"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(COLS * H, 2.0, H)
	shape.shape = box
	area.add_child(shape)
	area.position = Vector3(COLS * H * 0.5, -3.0, 0.0)
	add_child(area)
	area.body_entered.connect(_on_kill_zone_entered)


func _on_kill_zone_entered(body: Node3D) -> void:
	# 占位：先打印，玩家控制器写好后改为回出生点
	print("fell out of room: ", body.name)
