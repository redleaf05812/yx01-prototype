extends CanvasLayer

# 最小 HUD：左下 血量 + 电量格；右下 弹匣 + 三个技能格（喷气 CD / 隐身占位 / 技能2占位）。
# 用法：hud.bind(player)，之后每帧从 player 读取数值。

var _player: Node
var _hp_label: Label
var _cells: Array[ColorRect] = []
var _ammo_label: Label
var _jet_overlay: ColorRect


func bind(p: Node) -> void:
	_player = p
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 左下：血量数字 + 电量 10 格
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN  # 从底边向上长，不会跑出屏幕
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

	# 右下：弹匣 + 三个技能格
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
		bg.color = Color(0.25, 0.25, 0.3) if i == 0 else Color(0.35, 0.35, 0.35)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(bg)
		if i == 0:
			# 冷却遮罩：从顶部覆盖，剩余比例越大覆盖越多
			_jet_overlay = ColorRect.new()
			_jet_overlay.color = Color(0, 0, 0, 0.6)
			_jet_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			slot.add_child(_jet_overlay)
		var lbl := Label.new()
		lbl.text = names[i] if i == 0 else "占位"
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
	_ammo_label.text = "%d / %d" % [_player.ammo, Config.pistol_magazine]
	_jet_overlay.anchor_bottom = clampf(_player.jet_cd_left / Config.jet_cooldown, 0.0, 1.0)
