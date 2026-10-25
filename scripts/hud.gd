extends CanvasLayer

# 最小 HUD：左下 血量 + 电量格；右下 弹匣 + 三个技能格（喷气 CD / 隐身 / 技能2占位）。
# 用法：hud.bind(player)，之后每帧从 player 读取数值。

var _player
var _hp_label: Label
var _cells: Array[ColorRect] = []
var _ammo_label: Label
var _slot_bgs: Array[ColorRect] = []
var _slot_overlays: Array[ColorRect] = []  # [0]=喷气 CD, [1]=隐身 CD


func bind(p: Node) -> void:
	_player = p
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# 屏幕上方的操作提示：深色底 + 三行短文字，避免小分辨率下被截断（占位文字，后续可换成教学提示）
	var hint_panel := PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.offset_top = 8
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0, 0, 0, 0.55)
	hint_style.set_corner_radius_all(6)
	hint_style.content_margin_left = 12
	hint_style.content_margin_right = 12
	hint_style.content_margin_top = 6
	hint_style.content_margin_bottom = 6
	hint_panel.add_theme_stylebox_override("panel", hint_style)
	var hint := Label.new()
	hint.text = "A/D 移动   空格 跳跃   C 蹲下   Z 趴下   Shift 跑步/冲刺\nCtrl 喷气   Q 隐身   T 勾爪   R 换弹   F 开门\n鼠标左键 射击/投掷EMP   右键 EMP撞击   1 手枪  2 射击模式  3 EMP"
	hint.add_theme_font_override("font", Config.cjk_font)
	hint.add_theme_font_size_override("font_size", 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(hint)
	root.add_child(hint_panel)

	# 左下：血量数字 + 电量 10 格（从底边向上长）
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(left)
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 24)
	left.add_child(_hp_label)
	var cell_row := HBoxContainer.new()
	cell_row.add_theme_constant_override("separation", 4)
	left.add_child(cell_row)
	for i in Config.battery_max:
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(22, 14)
		cell_row.add_child(c)
		_cells.append(c)

	# 右下：弹匣 + 三个技能格（从底边向上、向左长）
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(right)
	_ammo_label = Label.new()
	_ammo_label.add_theme_font_size_override("font_size", 24)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_ammo_label)
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	right.add_child(slot_row)

	var names := ["喷气", "隐身", "技能2"]
	for i in names.size():
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(56, 56)
		slot_row.add_child(slot)

		var bg := ColorRect.new()
		bg.color = Color(0.35, 0.35, 0.35) if i == 2 else Color(0.25, 0.25, 0.3)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(bg)
		_slot_bgs.append(bg)

		if i < 2:
			var overlay := ColorRect.new()
			overlay.color = Color(0, 0, 0, 0.6)
			overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			slot.add_child(overlay)
			_slot_overlays.append(overlay)

		var lbl := Label.new()
		lbl.text = names[i] if i < 2 else "占位"
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(lbl)


func _process(_delta: float) -> void:
	if _player == null:
		return
	_hp_label.text = "HP %d" % int(_player.hp)
	for i in _cells.size():
		var fill := clampf(_player.battery - float(i), 0.0, 1.0)
		_cells[i].color = Color(0.3, 0.9, 0.4, maxf(fill, 0.12))
	if _player.kind == 1:
		_ammo_label.text = "EMP x%d" % _player.emp_count
	elif _player.reloading:
		_ammo_label.text = "换弹中"
	else:
		var mode := "三连发" if _player.fire_mode == 1 else "单发"
		_ammo_label.text = "%s  %d / %d" % [mode, _player.ammo, Config.pistol_magazine]

	_slot_overlays[0].anchor_bottom = clampf(_player.jet_cd_left / Config.jet_cooldown, 0.0, 1.0)
	_slot_overlays[1].anchor_bottom = clampf(_player.stealth_cd_left / Config.stealth_internal_cooldown, 0.0, 1.0)
	_slot_bgs[1].color = Color(0.2, 0.6, 0.3) if _player.stealth_on else Color(0.25, 0.25, 0.3)
