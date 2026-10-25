extends Node

# 《孤星.YX-01：余晖》原型 — 所有数值的唯一来源 (Godot 4, GDScript)
# 设置方法：Project > Project Settings > Globals > Autoload
#   Path: res://scripts/game_config.gd    Name: Config
# 之后在任何脚本里直接用 Config.walk_speed 调用。
# 单位：米 (Godot 默认 1 单位 = 1 米)。换算：文档 uu ÷ 100；1H = 1.8 m。

# ---- 单位基准 ----
const H := 1.8                          # 1H = 180 uu

# ---- 玩家移动 ----
var walk_speed := 3.6                   # 自定：原 2.25 太慢，改为 2 H/s
var run_speed := 5.4                    # 自定：走路 × 1.5，不耗电
var crouch_speed := 2.88                # 自定：走路 × 0.8
var crawl_speed := 2.16                 # 自定：走路 × 0.6
var jump_velocity := 11.62              # 1162 uu/s (一段跳 1H)
var gravity := 37.5                     # 3750 uu/s²
# 跳跃手感（Metroidvania 式，自定）：满跳高度不变，只改松键截断、下落速度、容错
var jump_cut_multiplier := 0.5          # 松开跳跃键时上升速度 × 此值（可变跳高）
var fall_gravity_multiplier := 1.6      # 下落时重力 × 此值（下落更快，手感更干脆）
var coyote_time := 0.1                  # 离开平台后仍可起跳的时间 (s)
var jump_buffer_time := 0.1             # 落地前提前按跳跃，落地后自动起跳 (s)

# ---- 玩家体型 (米) ----
var stand_height := 1.8                 # 1H
var crouch_height := 1.08               # 0.6H
var crawl_height := 0.54                # 0.3H

# ---- 血量与受击 ----
var max_hp := 100.0
var invincible_time := 0.8              # s
var knockback_distance := 1.2           # 120 uu

# ---- 电池 ----
var battery_max := 10                   # 格
var battery_regen_per_sec := 0.2        # 2%/s = 0.2 格/s
var battery_start_threshold := 3        # 启动技能所需最少格数
var stealth_cost_per_sec := 1.0         # 格/s
var stealth_internal_cooldown := 3.0    # s
var reload_cost := 1                    # 格

# ---- 喷气 ----
var jet_distance := 5.4                 # 540 uu (3H)
var jet_duration := 0.4                 # s
var jet_cooldown := 2.5                 # s
var jet_battery_cost := 3.0              # 格：每次喷气扣除（自定，文档未给）

# ---- 勾爪 ----
var grapple_range := 7.2                # 720 uu (4H)
var grapple_speed := 22.5               # 2250 uu/s
var grapple_arrive_distance := 0.2      # 自定：到达阈值
var pullup_up := 9.0                  # 悬崖拉上：向上速度 (m/s)
var pullup_forward := 4.0               # 悬崖拉上：向前速度 (m/s)
var pullup_time := 0.35                 # 悬崖拉上：持续时间 (s)，之后自然落到崖顶
# 摆荡（空中锚点悬挂时）
var swing_pump_accel := 8.0             # A/D 施加的摆荡加速度 (rad/s²)
var swing_damping := 0.25               # 摆荡阻尼（越大越快停）
var swing_max_angle := 1.3              # 最大摆角 (rad，约 75°)

# ---- 手枪 ----
var pistol_damage := 1.0
var pistol_range := 9.0                 # 900 uu (5H)
var pistol_fire_interval := 0.35        # s
var pistol_magazine := 6
# 三连发 / 后坐力（自定）：三连发 = 同一把枪连续打 3 发（每发 1 发弹药），每发之间枪口上抬
var triple_count := 3                   # 一次三连发打出的发数
var triple_interval := 0.12             # 三连发内每发间隔 (s)
var recoil_per_shot := 0.12             # 每发后坐力：枪口上抬 (rad，约 6.9°)
var recoil_max := 0.4                   # 后坐力上限 (rad，约 23°)
var recoil_recover_per_sec := 0.6       # 后坐力回落速度 (rad/s)
var reload_time := 1.2                  # s

# ---- EMP ----
var emp_radius := 5.4                   # 540 uu (3H)
var emp_stun_time := 5.0                # s
var emp_fuse_time := 1.5                # s (左键)
var emp_throw_range := 10.8             # 1080 uu (6H)
var emp_carry := 2
var emp_throw_speed := 12.0             # m/s（自定，文档未给飞行速度）
var door_interact_range := 1.8          # 1H（自定，F 键交互距离）

# ---- 蜘蛛 ----
var spider_hp := 2.0
var spider_speed := 6.2                 # 620 uu/s
var spider_vision_range := 10.8         # 1080 uu (6H)
var spider_vision_angle := 90.0         # 度 (正面)
var spider_attack_range := 1.12         # 112 uu
var spider_attack_interval := 1.0       # s
var spider_attack_damage := 25.0
var spider_patrol_pause := 1.0          # 到点停留
var spider_search_time_min := 6.0       # s
var spider_search_time_max := 8.0       # s

# ---- 隐身发现距离 (水平 X 距离, 米) ----
var detect_range_walk_stealth := 3.6    # 2H，站立走
var detect_range_run_stealth := 9.0     # 5H，奔跑
# 蹲走：永不发现，不需要数值

# ---- 正交相机 ----
# Godot 的 Camera3D.size 在正交模式下是视野的完整高度（不是半高）。
# 11.25H = 20.25 m。宽度随 16:9 自动为 36 m = 20H。
var camera_ortho_height := 20.25


# ---- 中文字体 ----
# Godot 默认字体不含中文，会显示成方块。这里取系统自带的中文字体（macOS 为 PingFang SC）。
var cjk_font: SystemFont

func _init() -> void:
	cjk_font = SystemFont.new()
	cjk_font.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "Noto Sans SC"])
