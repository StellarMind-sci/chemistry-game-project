# MainMenu.gd
# Demo 主菜单：化学拓扑地图 + 右侧信息面板（自适应布局）
# 项目说明书要求：评委打开 Demo 首屏就是蜂窝六边形化学拓扑地图
extends Control

const C_BG := Color(0.040, 0.048, 0.080)

var _hex_map: ChemHexMap
var _info_root: Control

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	# 监听窗口大小变化，自动重排
	get_viewport().size_changed.connect(_on_viewport_resized)
	# 等待 layout 完成后做首次定位
	await get_tree().process_frame
	_on_viewport_resized()

func _build() -> void:
	# ── 背景（占满整个 Control）─────────────────────────
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ── 化学拓扑地图（Node2D，位置在 _on_viewport_resized 中设置）
	_hex_map = ChemHexMap.new()
	add_child(_hex_map)

	# ── 右侧信息面板（Control + 锚点，自动跟随右边缘）─────
	_info_root = Control.new()
	_info_root.anchor_left   = 0.62
	_info_root.anchor_right  = 1.0
	_info_root.anchor_top    = 0.0
	_info_root.anchor_bottom = 1.0
	_info_root.offset_left   = 20
	_info_root.offset_right  = -30
	_info_root.offset_top    = 80
	_info_root.offset_bottom = -120
	add_child(_info_root)

	# 信息面板背景
	var panel_bg := ColorRect.new()
	panel_bg.color = Color(0.07, 0.09, 0.14, 0.92)
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_root.add_child(panel_bg)

	# 信息面板内容（VBox 垂直流式布局）
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 8)
	vb.offset_left = 20; vb.offset_right = -20
	vb.offset_top  = 22; vb.offset_bottom = -22
	_info_root.add_child(vb)

	var title := Label.new()
	title.text = "ChemBattle"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.80, 0.88, 1.00))
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "通过化学讲述人的故事"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.55, 0.68, 0.85))
	vb.add_child(sub)

	var line := ColorRect.new()
	line.color = Color(0.30, 0.50, 0.75, 0.50)
	line.custom_minimum_size = Vector2(0, 2)
	vb.add_child(line)

	var desc := Label.new()
	desc.text = (
		"回合制化学策略战斗\n\n" +
		"● 双方技能化学反应碰撞\n" +
		"● 勒夏特列环境平衡系统\n" +
		"● 分子结构活性位点攻击\n" +
		"● Boss 多形态叙事机制"
	)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90))
	vb.add_child(desc)

	# 占位空间（让按钮往下推）
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	# 开始按钮
	var btn := Button.new()
	btn.text = "▶  开始 Demo"
	btn.add_theme_font_size_override("font_size", 18)
	btn.custom_minimum_size = Vector2(0, 50)
	btn.modulate = Color(0.30, 0.80, 0.55)
	btn.pressed.connect(_on_start_pressed)
	vb.add_child(btn)

	# ── 底部说明 ──────────────────────────────────────────
	var map_lbl := Label.new()
	map_lbl.name = "MapLabel"
	map_lbl.text = "化学领域拓扑地图  （灰色=待解锁）"
	map_lbl.add_theme_font_size_override("font_size", 12)
	map_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.65))
	map_lbl.anchor_left = 0.0; map_lbl.anchor_right = 0.62
	map_lbl.anchor_top = 1.0; map_lbl.anchor_bottom = 1.0
	map_lbl.offset_top = -60; map_lbl.offset_bottom = -40
	map_lbl.offset_left = 50
	add_child(map_lbl)

	var ver := Label.new()
	ver.text = "Demo Build  |  Godot 4"
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(0.35, 0.38, 0.45))
	ver.anchor_left = 0.0; ver.anchor_top = 1.0
	ver.anchor_right = 0.0; ver.anchor_bottom = 1.0
	ver.offset_left = 20; ver.offset_top = -25
	add_child(ver)

func _on_viewport_resized() -> void:
	# 把 hex map 放在屏幕左侧约 31% 处，垂直居中偏上
	var vs: Vector2 = get_viewport_rect().size
	_hex_map.position = Vector2(vs.x * 0.31, vs.y * 0.48)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")
