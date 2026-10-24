extends Node

# 《孤星.YX-01：余晖》原型 — 所有数值的唯一来源 (Godot 4, GDScript)
# 设置方法：Project > Project Settings > Globals > Autoload
#   Path: res://scripts/game_config.gd    Name: Config
# 之后在任何脚本里直接用 Config.walk_speed 调用。
# 单位：米 (Godot 默认 1 单位 = 1 米)。换算：文档 uu ÷ 100；1H = 1.8 m。

# ---- 单位基准 ----
const H := 1.8                          # 1H = 180 uu

# ---- 玩家移动 ----
var walk_speed := 2.25                  # 225 uu/s
var run_speed := 5.62                   # 562 uu/s
var crouch_speed := 1.35                # 135 uu/s
var crawl_speed := 0.67                 # 67 uu/s
var jump_velocity := 11.62              # 1162 uu/s (一段跳 1H)
var gravity := 37.5                     # 3750 uu/s²
var dash_speed := 16.87                 # 1687 uu/s
var dash_time := 0.15                   # s
var dash_cooldown := 0.5                # s

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

# ---- 手枪 ----
var pistol_damage := 1.0
var pistol_range := 9.0                 # 900 uu (5H)
var pistol_fire_interval := 0.35        # s
var pistol_magazine := 6
var reload_time := 1.2                  # s

# ---- EMP ----
var emp_radius := 5.4                   # 540 uu (3H)
var emp_stun_time := 5.0                # s
var emp_fuse_time := 1.5                # s (左键)
var emp_throw_range := 10.8             # 1080 uu (6H)
var emp_carry := 2

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
