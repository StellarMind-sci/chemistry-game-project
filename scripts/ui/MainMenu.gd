# MainMenu.gd
# Demo 主菜单：化学拓扑地图 + 开始按钮
# 项目说明书要求：评委打开 Demo 首屏就是蜂窝六边形化学拓扑地图
extends Node

const C_BG   := Color(0.040, 0.048, 0.080)
const C_TEXT := Color(0.900, 0.900, 0.950)

var _hex_map: ChemHexMap
var _font:    Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_build()

func _build() -> void:
	# ── 背景 ─────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ── 化学拓扑地图（左侧主视觉）────────────────────────
	_hex_map = ChemHexMap.new()
	_hex_map.position = Vector2(480, 370)   # 屏幕中左区域
	add_child(_hex_map)

	# ── 右侧信息面板 ──────────────────────────────────────
	var panel := ColorRect.new()
	panel.color = Color(0.07, 0.09, 0.14, 0.92)
	panel.size  = Vector2(320, 360)
	panel.position = Vector2(880, 180)
	add_child(panel)

	# 标题
	var title := Label.new()
	title.text = "ChemBattle"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.80, 0.88, 1.00))
	title.position = Vector2(900, 200)
	add_child(title)

	# 副标题
	var sub := Label.new()
	sub.text = "通过化学讲述人的故事"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.55, 0.68, 0.85))
	sub.position = Vector2(908, 248)
	add_child(sub)

	# 分割线
	var line := ColorRect.new()
	line.color    = Color(0.30, 0.50, 0.75, 0.50)
	line.size     = Vector2(280, 2)
	line.position = Vector2(900, 272)
	add_child(line)

	# 说明文字
	var desc := Label.new()
	desc.text = (
		"回合制化学策略战斗\n\n" +
		"● 双方技能化学反应碰撞\n" +
		"● 勒夏特列环境平衡系统\n" +
		"● 分子结构活性位点攻击\n" +
		"● Boss 多形态叙事机制\n"
	)
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90))
	desc.position = Vector2(908, 285)
	add_child(desc)

	# ── 开始 Demo 按钮 ─────────────────────────────────
	var start_btn := Button.new()
	start_btn.text = "▶  开始 Demo"
	start_btn.add_theme_font_size_override("font_size", 18)
	start_btn.custom_minimum_size = Vector2(240, 50)
	start_btn.position            = Vector2(910, 450)
	start_btn.modulate            = Color(0.30, 0.80, 0.55)
	start_btn.pressed.connect(_on_start_pressed)
	add_child(start_btn)

	# ── 地图说明标签 ──────────────────────────────────────
	var map_lbl := Label.new()
	map_lbl.text = "化学领域拓扑地图  （灰色=待解锁）"
	map_lbl.add_theme_font_size_override("font_size", 12)
	map_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.65))
	map_lbl.position = Vector2(200, 660)
	add_child(map_lbl)

	# ── 版本标签 ──────────────────────────────────────────
	var ver := Label.new()
	ver.text = "Demo Build  |  Godot 4.6"
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(0.35, 0.38, 0.45))
	ver.position = Vector2(20, 710)
	add_child(ver)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")
