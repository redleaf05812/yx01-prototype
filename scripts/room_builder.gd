extends Node3D

# 房间 01 Blockout：根据文档第三节的元素表，用色块生成几何体（运行时生成，不用手摆）。
# 坐标约定：1 格 = 1H = Config.H 米。格子 (col, row)，col 从左 0 起，row 从上 0 起。
# 房间 36 格宽 × 11 格高。地面在 row 10。

const COLS := 36

# 只有这些表面可以被勾爪钩住（墙、地、天花板、门不行）
const GRAPPLE_ANCHORS := ["Platform", "Barrier"]  # 隧道顶不可勾
const ROWS := 11

# 低矮通道（隧道）占第 18–19 列，净高 0.4H。蜘蛛不能进入。
const TUNNEL_COL := 18
const TUNNEL_COLS := 2

# 方块上的名字标签（英文，默认字体可直接显示）
const LABEL_TEXT := {
	"Platform": "平台 4H",
	"Barrier": "阻拦点 3H",
	"TunnelRoof": "低矮通道 0.4H（只能趴下）",
	"InfectedGapMarker": "感染区 3H",
	"InfectedDoor": "侵蚀的门 2H（需 EMP 清除）",
}

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
	_build_tunnel_zone()
	_build_spider()


# 通用：生成一个带碰撞的长方体。x0..x1, y0..y1 为米，z 厚度 1 格。
func _add_box(x0: float, x1: float, y0: float, y1: float, color: Color, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = label
	if label in GRAPPLE_ANCHORS:
		body.add_to_group("grapple_anchor")
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
	if LABEL_TEXT.has(label):
		_name_label(Vector3(center.x, y1 + 0.3, 0.0), LABEL_TEXT[label])


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
	_name_label(Vector3((7 + 1.5) * H, 0.6, 0.0), LABEL_TEXT["InfectedGapMarker"])

	# 平台：col 13..16, row 4，宽 4 格
	_cell_box(13, 4, 4, 1, COLOR_PLATFORM, "Platform")

	# 阻拦点 XX：col 23..24, 从地面往上 3H 高
	_add_box(23 * H, 25 * H, 1.8, 1.8 + 3 * H, COLOR_BARRIER, "Barrier")

	# 低矮通道顶：col 18..19，离地 0.4H 净高（0.72 m）
	_add_box(18 * H, 20 * H, 1.8 + 0.4 * H, 1.8 + 0.4 * H + 2 * H, COLOR_TUNNEL, "TunnelRoof")

	# 侵蚀的门 ||：col 29，从地面往上 2H 高（门脚本处理侵蚀和开关）
	_build_door()


# 感染区缺口下方的死亡区：掉进去就回到出生点（玩家脚本接入后替换）。
func _build_door() -> void:
	var door := StaticBody3D.new()
	door.name = "InfectedDoor"
	door.set_script(DOOR_SCRIPT)
	door.set("infected", true)
	door.position = Vector3(29.5 * H, 1.8 + H, 0.0)
	add_child(door)
	_name_label(Vector3(29.5 * H, 1.8 + 2.0 * H + 0.3, 0.0), LABEL_TEXT["InfectedDoor"])


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


const SPIDER_SCRIPT := preload("res://scripts/spider.gd")
const DOOR_SCRIPT := preload("res://scripts/door.gd")


# 蜘蛛：'S' 在第 14 列（地面上，平台下方）
func _build_spider() -> void:
	var spider := CharacterBody3D.new()
	spider.name = "Spider"
	spider.set_script(SPIDER_SCRIPT)
	spider.position = Vector3((14 + 0.5) * H, 1.8, 0.0)
	# 蜘蛛不能进隧道：巡逻右端停在隧道前，并设置硬限制（追击时也进不去）
	spider.set("patrol_right", TUNNEL_COL * H - 1.0)
	spider.set("no_go_min", TUNNEL_COL * H - 0.4)
	spider.set("no_go_max", (TUNNEL_COL + TUNNEL_COLS) * H + 0.4)
	add_child(spider)


# 隧道区域：玩家进入时锁住除走/爬以外的所有技能（见 player.gd set_in_tunnel）
func _build_tunnel_zone() -> void:
	var area := Area3D.new()
	area.name = "TunnelZone"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TUNNEL_COLS * H, 0.4 * H, H)
	shape.shape = box
	area.add_child(shape)
	area.position = Vector3((TUNNEL_COL + TUNNEL_COLS * 0.5) * H, 1.8 + 0.2 * H, 0.0)
	add_child(area)
	area.body_entered.connect(func(b: Node3D) -> void:
		if b.has_method("set_in_tunnel"):
			b.set_in_tunnel(true))
	area.body_exited.connect(func(b: Node3D) -> void:
		if b.has_method("set_in_tunnel"):
			b.set_in_tunnel(false))


# 生成一个始终正对镜头的文字标签
func _name_label(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Config.cjk_font
	l.font_size = 48
	l.pixel_size = 0.01
	l.outline_size = 8
	l.no_depth_test = true
	l.position = pos
	add_child(l)


func _on_kill_zone_entered(body: Node3D) -> void:
	if body.has_method("respawn"):
		body.respawn()
