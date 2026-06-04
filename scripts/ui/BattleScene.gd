# BattleScene.gd  v0.3
# 新增：Boss 多形态支持，形态切换视觉反馈，特殊胜利条件
extends Node

enum Phase { INIT, PLAYER_INPUT, TARGET_SELECT, NODE_SELECT, RESOLVING, BATTLE_END }
var phase: Phase = Phase.INIT

const C_BG       := Color(0.055, 0.065, 0.100)
const C_PLAYER   := Color(0.35,  0.75,  1.00)
const C_ENEMY    := Color(1.00,  0.50,  0.25)
const C_HP_HI    := Color(0.25,  0.85,  0.45)
const C_HP_MD    := Color(0.95,  0.80,  0.15)
const C_HP_LO    := Color(0.92,  0.22,  0.18)
const C_STRIKE   := Color(0.80,  0.35,  0.18)
const C_INTERV   := Color(0.18,  0.50,  0.85)
const C_TARGET   := Color(0.90,  0.80,  0.10)
const C_DIMMED   := Color(0.45,  0.45,  0.50)

var bm:     BattleManager
var engine: ReactionInference
var turn_number: int = 0

var p_selections: Dictionary = {}
var select_queue: Array       = []
var cur_selector: Character   = null
var pending_action            = null
var pending_char: Character   = null
var pending_target: Character = null

var env_label:  Label
var player_col: VBoxContainer
var enemy_col:  VBoxContainer
var log_rtl:    RichTextLabel
var prompt_lbl: Label
var action_row: HBoxContainer

var hp_bar_map:  Dictionary = {}
var hp_txt_map:  Dictionary = {}
var hand_lbl_map: Dictionary = {}
# Boss 专用：形态名称标签
var phase_lbl_map:   Dictionary = {}   # Boss → Label
var status_lbl_map:  Dictionary = {}   # Character → Label（状态效果）
var node_display_map: Dictionary = {}   # Character → Label（结构节点）

func _ready() -> void:
	_build_ui()
	_init_battle()
	call_deferred("_show_battle_intro")  # 先显示引导，引导结束后开始战斗

# ══════════════════════════════════════════════════════════
# UI 构建（与 v0.2 相同，增加 phase_lbl 支持）
# ══════════════════════════════════════════════════════════
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)

	var ep := _make_margin(Color(0.07, 0.10, 0.16))
	ep.custom_minimum_size = Vector2(0, 36)
	vb.add_child(ep)
	env_label = Label.new()
	env_label.add_theme_font_size_override("font_size", 13)
	env_label.add_theme_color_override("font_color", Color(0.60, 0.85, 1.00))
	ep.add_child(env_label)

	var cr := HBoxContainer.new()
	cr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cr.size_flags_stretch_ratio = 0.30
	cr.add_theme_constant_override("separation", 6)
	vb.add_child(cr)

	player_col = VBoxContainer.new()
	player_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_col.add_theme_constant_override("separation", 4)
	cr.add_child(player_col)
	var div := ColorRect.new()
	div.color = Color(0.25, 0.40, 0.65, 0.50)
	div.custom_minimum_size = Vector2(2, 0)
	cr.add_child(div)
	enemy_col = VBoxContainer.new()
	enemy_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_col.add_theme_constant_override("separation", 4)
	cr.add_child(enemy_col)

	log_rtl = RichTextLabel.new()
	log_rtl.bbcode_enabled = true
	log_rtl.scroll_following = true
	log_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_rtl.size_flags_stretch_ratio = 0.45
	log_rtl.add_theme_font_size_override("normal_font_size", 13)
	_apply_sb(log_rtl, Color(0.06, 0.08, 0.13))
	vb.add_child(log_rtl)

	var ap := _make_margin(Color(0.07, 0.09, 0.15))
	ap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ap.size_flags_stretch_ratio = 0.25
	vb.add_child(ap)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 5)
	av.set_anchors_preset(Control.PRESET_FULL_RECT)
	ap.add_child(av)
	prompt_lbl = Label.new()
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_font_size_override("font_size", 14)
	prompt_lbl.add_theme_color_override("font_color", Color(0.92, 0.85, 0.35))
	av.add_child(prompt_lbl)
	action_row = HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 8)
	av.add_child(action_row)

# ══════════════════════════════════════════════════════════
# 战斗引导面板（Demo 开始前向玩家说明三个核心机制）
# ══════════════════════════════════════════════════════════
func _show_battle_intro() -> void:
	var overlay := _make_overlay(Color(0.03, 0.04, 0.10, 0.94))
	# 用锚点让 vb 自动居中、占视口中央 60%
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.anchor_left = 0.20; vb.anchor_right  = 0.80
	vb.anchor_top  = 0.18; vb.anchor_bottom = 0.85
	overlay.add_child(vb)

	_add_intro_label(vb, "⚗  战斗规则速览", 26, Color(0.85, 0.90, 1.00))
	_add_intro_label(vb, "", 10, Color.WHITE)

	var rules := [
		["🔷 反应行动系统",
		 "选择技能卡攻击敌人，双方技能通过化学反应规则碰撞解算。\n" +
		 "技能的元素标签决定能触发哪些反应，反应类型决定伤害倍率。"],
		["🌡 环境平衡系统",
		 "战场有 pH / 温度 / 熵 三个环境变量，会被每次反应改变。\n" +
		 "勒夏特列原理：环境变化会反向抑制触发该变化的反应效率。"],
		["⬡ 活性位点攻击",
		 "攻击时可选择敌方角色的具体结构节点（如官能团）。\n" +
		 "若行动的化学标签与节点的弱点匹配，伤害 ×1.45。节点稳定性归零时永久损毁。"],
	]
	for rule in rules:
		_add_intro_label(vb, rule[0], 16, Color(0.70, 0.88, 1.00))
		_add_intro_label(vb, rule[1], 13, Color(0.78, 0.82, 0.90))

	_add_intro_label(vb, "", 8, Color.WHITE)
	var btn := Button.new()
	btn.text = "▶  开始战斗"
	btn.add_theme_font_size_override("font_size", 18)
	btn.custom_minimum_size = Vector2(200, 48)
	btn.modulate = Color(0.35, 0.85, 0.55)
	btn.pressed.connect(func():
		overlay.queue_free()
		_begin_turn()
	)
	vb.add_child(btn)
	add_child(overlay)

func _add_intro_label(parent: Node, text: String, size: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)

# ══════════════════════════════════════════════════════════
# Boss 形态切换公告（2秒戏剧性停顿）
# ══════════════════════════════════════════════════════════
func _show_phase_announcement(phase_name: String, msg: String, phase_color: Color) -> void:
	var overlay := _make_overlay(Color(0.02, 0.02, 0.06, 0.88))
	# 横条背景：左右贯穿，垂直居中
	var bar := ColorRect.new()
	bar.color = phase_color * Color(0.12, 0.12, 0.12, 1.0)
	bar.anchor_left = 0.0; bar.anchor_right  = 1.0
	bar.anchor_top  = 0.40; bar.anchor_bottom = 0.60
	overlay.add_child(bar)
	# 形态名（左侧 8% 缩进，顶部居中区域）
	var name_lbl := Label.new()
	name_lbl.text = phase_name
	name_lbl.add_theme_font_size_override("font_size", 32)
	name_lbl.add_theme_color_override("font_color", phase_color)
	name_lbl.anchor_left = 0.06; name_lbl.anchor_right  = 0.94
	name_lbl.anchor_top  = 0.42; name_lbl.anchor_bottom = 0.48
	overlay.add_child(name_lbl)
	# 形态描述（同区域下方）
	var msg_lbl := Label.new()
	msg_lbl.text = msg
	msg_lbl.add_theme_font_size_override("font_size", 15)
	msg_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.anchor_left = 0.06; msg_lbl.anchor_right  = 0.94
	msg_lbl.anchor_top  = 0.50; msg_lbl.anchor_bottom = 0.60
	overlay.add_child(msg_lbl)
	add_child(overlay)
	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(overlay): overlay.queue_free()

# ══════════════════════════════════════════════════════════
# 胜负结算界面
# ══════════════════════════════════════════════════════════
func _show_result_screen(won: bool) -> void:
	var overlay := _make_overlay(Color(0.03, 0.04, 0.08, 0.92))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.anchor_left = 0.25; vb.anchor_right  = 0.75
	vb.anchor_top  = 0.25; vb.anchor_bottom = 0.78
	overlay.add_child(vb)

	if won:
		_add_intro_label(vb, "★  实验成功  ★", 38, Color(0.40, 1.00, 0.65))
		_add_intro_label(vb, "所有结构节点已瓦解，反应链完成", 16, Color(0.75, 0.90, 0.80))
	else:
		_add_intro_label(vb, "✖  实验失败", 38, Color(1.00, 0.40, 0.30))
		_add_intro_label(vb, "团队全员无力化，战场被对方掌控", 16, Color(0.90, 0.70, 0.70))

	_add_intro_label(vb, "共进行 %d 回合" % turn_number, 14, Color(0.65, 0.70, 0.80))
	var env := bm.environment
	_add_intro_label(vb,
		"最终环境：%s" % env.get_summary(),
		13, Color(0.55, 0.65, 0.80))

	_add_intro_label(vb, "", 8, Color.WHITE)
	var btn := Button.new()
	btn.text = "↩  返回主菜单"
	btn.add_theme_font_size_override("font_size", 17)
	btn.custom_minimum_size = Vector2(220, 48)
	btn.modulate = Color(0.60, 0.75, 1.00)
	btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn"))
	vb.add_child(btn)
	add_child(overlay)

# ── 通用半透明遮罩层 ──────────────────────────────────────
func _make_overlay(bg_color: Color) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = bg_color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	return overlay

func _make_margin(color: Color) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["top","bottom","left","right"]:
		mc.add_theme_constant_override("margin_" + side, 6 if side in ["top","bottom"] else 10)
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.add_child(bg)
	return mc

func _apply_sb(node: Control, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_width_top = 1
	sb.border_color = Color(0.22, 0.38, 0.60, 0.70)
	for s in ["top","bottom","left","right"]:
		sb.set("content_margin_" + s, 8 if s in ["top","bottom"] else 12)
	if node is RichTextLabel: node.add_theme_stylebox_override("normal", sb)

func _make_char_panel(chara: Character, is_player: bool) -> Control:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 2)

	# 名称
	var nl := Label.new()
	nl.text = chara.char_name
	nl.add_theme_font_size_override("font_size", 14)
	nl.add_theme_color_override("font_color",
		C_PLAYER if is_player else chara.get_phase_color() if chara is Boss else C_ENEMY)
	c.add_child(nl)

	# Boss 形态标签
	if chara is Boss:
		var boss := chara as Boss
		var pl := Label.new()
		var p := boss.get_current_phase()
		pl.text = p.phase_name if p else ""
		pl.add_theme_font_size_override("font_size", 12)
		pl.add_theme_color_override("font_color", boss.get_phase_color())
		phase_lbl_map[chara] = pl
		c.add_child(pl)

	# HP 条
	var bar := ProgressBar.new()
	bar.max_value = chara.max_hp
	bar.value     = chara.hp
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	hp_bar_map[chara] = bar
	c.add_child(bar)

	var ht := Label.new()
	ht.text = "HP %.0f / %.0f" % [chara.hp, chara.max_hp]
	ht.add_theme_font_size_override("font_size", 12)
	ht.add_theme_color_override("font_color", Color(0.75, 0.90, 0.75))
	hp_txt_map[chara] = ht
	c.add_child(ht)

	var hl := Label.new()
	hl.text = "谱:%d 手:%d 沉:%d  AE:%.0f" % [
		chara.behavior_spectrum.size(), chara.standby.size(), chara.sediment.size(),
		chara.energy_pool.get(Character.ENERGY_ACTIVATION, 0.0)]
	hl.add_theme_font_size_override("font_size", 11)
	hl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50))
	hand_lbl_map[chara] = hl
	c.add_child(hl)

	# 状态效果显示行
	var sl := Label.new()
	sl.text = ""
	sl.add_theme_font_size_override("font_size", 11)
	sl.add_theme_color_override("font_color", Color(0.90, 0.65, 0.30))
	status_lbl_map[chara] = sl
	c.add_child(sl)

	# 结构节点显示
	var ndl := Label.new()
	ndl.text = ""
	ndl.add_theme_font_size_override("font_size", 11)
	ndl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ndl.add_theme_color_override("font_color", Color(0.75, 0.55, 0.90))
	node_display_map[chara] = ndl
	c.add_child(ndl)

	return c

# ══════════════════════════════════════════════════════════
# 战斗初始化
# ══════════════════════════════════════════════════════════
func _init_battle() -> void:
	engine = ReactionInference.new()
	engine.load_databases(
		"res://data/substances/substance_registry.json",
		"res://data/reactions/reaction_rules.json")

	# 玩家队
	var pa := Character.new("实验者·酸", "player", 300.0)
	pa.draw_count = 2
	var hcl := ReactionAction.from_substance(engine, "HCl", ReactionAction.TYPE_STRIKE)
	hcl.action_name = "盐酸冲击"; hcl.energy_cost = {Character.ENERGY_ACTIVATION: 15.0}
	var sul := ReactionAction.from_substance(engine, "H2SO4", ReactionAction.TYPE_STRIKE)
	sul.action_name = "硫酸腐蚀"; sul.energy_cost = {Character.ENERGY_ACTIVATION: 20.0}
	var heat := ReactionAction.make_field_intervention("升温催化", {"temp_delta": 8.0}, 2)
	heat.energy_cost = {Character.ENERGY_ACTIVATION: 8.0}
	# HNO₃ 氧化性酸攻击
	var hno3 := ReactionAction.from_substance(engine, "HNO3", ReactionAction.TYPE_STRIKE)
	hno3.action_name = "硝酸侵蚀"
	hno3.energy_cost = {Character.ENERGY_ACTIVATION: 22.0}
	pa.add_to_spectrum(hcl); pa.add_to_spectrum(sul); pa.add_to_spectrum(hno3)
	pa.add_to_spectrum(heat)
	# 注意：催化剂部署行动移出默认谱（调试催化剂时手动添加）

	var pb := Character.new("实验者·氧", "player", 300.0)  # HP 与酸持平，避免被优先集火
	pb.draw_count = 3   # 每回合多看一张，保证有攻击手段
	var kmo := ReactionAction.from_substance(engine, "KMnO4", ReactionAction.TYPE_STRIKE)
	kmo.action_name = "高锰酸钾"; kmo.energy_cost = {Character.ENERGY_ACTIVATION: 25.0, Character.ENERGY_ELECTRON: 2.0}
	kmo.keywords = ["先手"]
	var red := ReactionAction.from_substance(engine, "C2H5OH", ReactionAction.TYPE_STRIKE)
	red.action_name = "还原冲击"; red.energy_cost = {Character.ENERGY_ACTIVATION: 18.0}
	var na := ReactionAction.from_substance(engine, "Na", ReactionAction.TYPE_STRIKE)
	na.action_name = "钠焰爆燃"; na.energy_cost = {Character.ENERGY_ACTIVATION: 30.0}
	var ph_field := ReactionAction.make_field_intervention("氧化催化场", {"temp_delta": 6.0}, 2)
	ph_field.action_name = "氧化催化场"
	ph_field.energy_cost = {Character.ENERGY_ACTIVATION: 10.0}
	ph_field.description = "升温6°C，持续2回合，为氧化反应提供温度支持"
	pb.add_to_spectrum(kmo); pb.add_to_spectrum(red)
	pb.add_to_spectrum(na); pb.add_to_spectrum(ph_field)

	# 占位 Boss（3 形态机制测试，叙事内容待后续角色设计阶段）
	var boss := Boss.new("多形态测试 Boss", "enemy", 600.0)
	boss.draw_count = 2

	# 形态一（HP > 55%）：标准氧化攻击
	var p1 := Boss.BossPhase.new()
	p1.phase_name   = "形态一"
	p1.hp_threshold = 1.01
	p1.phase_color  = Color(0.90, 0.40, 0.10)
	p1.entry_message = ""
	p1.env_on_enter = {}
	var ba1 := ReactionAction.new("氧化攻击")
	ba1.element_tags = ["Cu","O"]; ba1.chem_tags = [ReactionAction.TAG_OXIDIZING]
	ba1.energy_cost = {Character.ENERGY_ACTIVATION: 20.0}; ba1.base_intensity = 30.0
	var ba2 := ReactionAction.new("碱性防御")
	ba2.element_tags = ["Cu","O","H"]; ba2.chem_tags = [ReactionAction.TAG_ALKALINE, ReactionAction.TAG_HYDROXYL]
	ba2.energy_cost = {Character.ENERGY_ACTIVATION: 10.0}; ba2.base_intensity = 12.0
	p1.actions = [ba1, ba2]

	# 形态二（HP < 55%）：更强攻击 + 环境扰动
	var p2 := Boss.BossPhase.new()
	p2.phase_name   = "形态二"
	p2.hp_threshold = 0.55
	p2.phase_color  = Color(0.50, 0.25, 0.08)
	p2.entry_message = "【形态切换】Boss 进入形态二"
	p2.env_on_enter = {"entropy_delta": 8.0}
	var bb1 := ReactionAction.new("强化攻击")
	bb1.element_tags = ["Cu"]; bb1.chem_tags = [ReactionAction.TAG_OXIDIZING, ReactionAction.TAG_REDUCING]
	bb1.energy_cost = {Character.ENERGY_ACTIVATION: 18.0}; bb1.base_intensity = 40.0
	bb1.keywords = ["先手"]
	var bb2 := ReactionAction.make_field_intervention("混乱扰动", {"entropy_delta": 6.0}, 1)
	bb2.energy_cost = {Character.ENERGY_ACTIVATION: 12.0}
	p2.actions = [bb1, bb2]

	# 形态三（HP < 25%）：最终形态
	var p3 := Boss.BossPhase.new()
	p3.phase_name   = "形态三"
	p3.hp_threshold = 0.25
	p3.phase_color  = Color(0.70, 0.70, 0.80)
	p3.entry_message = "【形态切换】Boss 进入最终形态"
	p3.env_on_enter = {"entropy_delta": 15.0, "temp_delta": 5.0}
	var bc1 := ReactionAction.new("最终攻击")
	bc1.element_tags = ["Cu"]; bc1.chem_tags = [ReactionAction.TAG_OXIDIZING]
	bc1.energy_cost = {Character.ENERGY_ACTIVATION: 15.0}; bc1.base_intensity = 52.0
	bc1.keywords = ["先手"]
	p3.actions = [bc1]

	boss.phases = [p1, p2, p3]
	boss.init_first_phase()
	boss.load_nodes([
		{"id":"defense_shell","label":"防御外壳 Cu²⁺","type":"cation",
		 "stability":1.0,"active_sites":["oxidant_site"],
		 "vulnerable_to":["acidic","reducing"]},
		{"id":"oxide_layer","label":"氧化层 O²⁻","type":"anion",
		 "stability":0.9,"active_sites":[],
		 "vulnerable_to":["acidic"]},
		{"id":"carbonate_core","label":"碳酸基 CO₃²⁻","type":"anion",
		 "stability":0.8,"active_sites":["proton_acceptor"],
		 "vulnerable_to":["acidic","alkaline"]},
	])

	bm = BattleManager.new()
	bm.setup_teams([pa, pb], [boss])

	# 构建角色面板
	var ph := Label.new(); ph.text = "▶ 玩家队伍"
	ph.add_theme_color_override("font_color", C_PLAYER)
	ph.add_theme_font_size_override("font_size", 13)
	player_col.add_child(ph)
	for c in bm.player_team: player_col.add_child(_make_char_panel(c, true))

	var eh := Label.new(); eh.text = "◀ 敌方"
	eh.add_theme_color_override("font_color", C_ENEMY)
	eh.add_theme_font_size_override("font_size", 13)
	enemy_col.add_child(eh)
	for c in bm.enemy_team: enemy_col.add_child(_make_char_panel(c, false))

	_log_append("[color=#ffaa44]⚔ 战斗开始！玩家2名 vs 多形态测试 Boss[/color]")
	_update_env_bar()

# ══════════════════════════════════════════════════════════
# 回合流程
# ══════════════════════════════════════════════════════════
func _begin_turn() -> void:
	if phase == Phase.BATTLE_END: return
	turn_number += 1
	bm.turn_count = turn_number
	for c in _all_alive(): c.restore_energy_per_turn()
	bm.phase_env_effects()
	_update_all_chars(); _update_env_bar(); _flush_bm_log()
	if await _check_and_end(): return
	for c in _all_alive():
		if c.standby.is_empty(): c.draw_to_standby()
	_update_all_chars()
	_log_append("\n[color=#aaffaa]── 回合 %d ──[/color]" % turn_number)
	_start_player_input()

func _start_player_input() -> void:
	phase = Phase.PLAYER_INPUT
	p_selections.clear()
	select_queue = []
	for c in bm.player_team:
		if c.is_alive() and not c.standby.is_empty():
			select_queue.append(c)
	_next_selector()

func _next_selector() -> void:
	if select_queue.is_empty():
		_resolve_turn()
		return
	cur_selector = select_queue.pop_front()
	prompt_lbl.text = "%s — 请选择反应行动" % cur_selector.char_name
	_rebuild_action_buttons(cur_selector)

func _on_action_picked(action, chara: Character) -> void:
	if phase != Phase.PLAYER_INPUT: return
	_clear_action_buttons()
	if action.has_method("is_intervention") and action.is_intervention():
		if "催化剂" in action.action_name or "催化" in action.action_name:
			_deploy_catalyst_from_action(action, chara)
		_finalize_selection(action, chara, null, "")
		return
	var alive_e := _alive_in(bm.enemy_team)
	if alive_e.is_empty():
		_finalize_selection(action, chara, null, "")
	elif alive_e.size() == 1:
		_after_target_known(action, chara, alive_e[0] as Character)
	else:
		pending_action = action; pending_char = chara
		phase = Phase.TARGET_SELECT
		_show_target_selection(chara)

func _on_target_picked(target: Character) -> void:
	if phase != Phase.TARGET_SELECT: return
	_clear_action_buttons()
	_after_target_known(pending_action, pending_char, target)

func _finalize_selection(action, chara: Character, target, node_id: String = "") -> void:
	p_selections[chara] = {"action": action, "target": target, "node_id": node_id}
	var tn: String = (target as Character).char_name if target != null else "战场"
	var node_str: String = ""
	if node_id != "" and target != null:
		var node_lbl: String = (target as Character).get_node_label(node_id)
		node_str = "  →节点[%s]" % node_lbl
	_log_append("  [color=#44ccff]%s[/color] → [color=#ffdd44]%s[/color]  目标：[color=#ffaa44]%s[/color]%s" % [
		chara.char_name, action.action_name, tn, node_str])
	_next_selector()

func _on_pass_pressed(chara: Character) -> void:
	if phase != Phase.PLAYER_INPUT: return
	_log_append("  [color=#888888]%s Pass[/color]" % chara.char_name)
	_clear_action_buttons(); _next_selector()

func _after_target_known(action, chara: Character, target: Character) -> void:
	phase = Phase.PLAYER_INPUT
	var is_strike: bool = not action.has_method("is_intervention") or action.is_strike()
	var active_nodes := target.get_active_nodes() if target != null else []
	if is_strike and not active_nodes.is_empty():
		pending_action = action; pending_char = chara; pending_target = target
		phase = Phase.NODE_SELECT
		_show_node_selection(action, chara, target)
	else:
		_finalize_selection(action, chara, target, "")

func _show_node_selection(action, chara: Character, target: Character) -> void:
	_clear_action_buttons()
	prompt_lbl.text = "%s — 选择攻击节点" % chara.char_name
	for node in target.get_active_nodes():
		var nid: String  = node.get("id", "")
		var nlbl: String = node.get("label", "?")
		var stab: float  = float(node.get("stability", 1.0))
		var vulns: Array = node.get("vulnerable_to", [])
		var atags: Array = action.chem_tags if "chem_tags" in action else []
		var is_vuln := false
		for tag in atags:
			if tag in vulns: is_vuln = true; break
		var btn := Button.new()
		btn.text = "[%s]
稳定 %.0f%%%s" % [nlbl, stab*100.0, "  ★克制" if is_vuln else ""]
		btn.custom_minimum_size = Vector2(145, 58)
		btn.modulate = Color(0.95, 0.75, 0.20) if is_vuln else Color(0.70, 0.55, 0.85)
		var cn=nid; var ca=action; var cc=chara; var ct=target
		btn.pressed.connect(func(): _on_node_picked(cn, ca, cc, ct))
		action_row.add_child(btn)
	var skip := Button.new()
	skip.text = "不指定节点
直接攻击"
	skip.custom_minimum_size = Vector2(95, 58)
	skip.modulate = Color(0.45, 0.45, 0.50)
	var ca2=action; var cc2=chara; var ct2=target
	skip.pressed.connect(func(): _on_skip_node(ca2, cc2, ct2))
	action_row.add_child(skip)

func _on_node_picked(node_id: String, action, chara: Character, target: Character) -> void:
	if phase != Phase.NODE_SELECT: return
	phase = Phase.PLAYER_INPUT; _clear_action_buttons()
	_finalize_selection(action, chara, target, node_id)

func _on_skip_node(action, chara: Character, target: Character) -> void:
	if phase != Phase.NODE_SELECT: return
	phase = Phase.PLAYER_INPUT; _clear_action_buttons()
	_finalize_selection(action, chara, target, "")

func _show_target_selection(attacker: Character) -> void:
	_clear_action_buttons()
	prompt_lbl.text = "%s — 请选择攻击目标" % attacker.char_name
	for tgt in _alive_in(bm.enemy_team):
		var t := tgt as Character
		var btn := Button.new()
		btn.text = "⚡ %s\nHP %.0f/%.0f" % [t.char_name, t.hp, t.max_hp]
		btn.custom_minimum_size = Vector2(180, 60)
		btn.modulate = C_TARGET
		var cap := t
		btn.pressed.connect(func(): _on_target_picked(cap))
		action_row.add_child(btn)

# ══════════════════════════════════════════════════════════
# 解算 + Boss 形态检测
# ══════════════════════════════════════════════════════════
func _resolve_turn() -> void:
	phase = Phase.RESOLVING
	prompt_lbl.text = "解算中..."
	_clear_action_buttons()

	# ── 敌方智能AI：评分选行动 + 化学克制选目标 ────────────
	var enemy_sel: Dictionary = {}   # Character → {action, target}
	_log_append("\n[color=#ffaa44]── 敌方行动 ──[/color]")
	for c in bm.enemy_team:
		if c.is_alive():
			var sel := _ai_pick_action_and_target(c as Character)
			if not sel.is_empty():
				enemy_sel[c] = sel
				var e_act = sel.get("action")
				var e_tgt = sel.get("target")
				var act_nm: String = e_act.action_name if e_act != null and "action_name" in e_act else "?"
				var tgt_nm: String = (e_tgt as Character).char_name if e_tgt != null else "战场"
				var act_type: String = "[调控]" if (e_act != null and e_act.has_method("is_intervention") and e_act.is_intervention()) else "[攻势]"
				_log_append("  [color=#ff8844]⚡ %s 选择 %s%s → [目标] %s[/color]" % [
					(c as Character).char_name, act_type, act_nm, tgt_nm])

	var clash_pairs: Array = []
	for atk in bm.player_team:
		if not atk.is_alive() or not p_selections.has(atk): continue
		var sel: Dictionary = p_selections[atk]
		var act = sel.get("action")
		var tgt = sel.get("target")
		if tgt != null and not (tgt as Character).is_alive():
			var ae := _alive_in(bm.enemy_team)
			tgt = ae[0] if not ae.is_empty() else null
		if tgt == null: continue
		var enemy_counter = enemy_sel.get(tgt, {}).get("action")
		clash_pairs.append(BattleManager.ClashPair.new(atk, act, tgt, enemy_counter))

	for atk in bm.enemy_team:
		if not atk.is_alive() or not enemy_sel.has(atk): continue
		var ai_sel: Dictionary = enemy_sel[atk]
		var ai_act  = ai_sel.get("action")
		var ai_tgt  = ai_sel.get("target")
		if ai_tgt == null or not (ai_tgt as Character).is_alive():
			var ap := _alive_in(bm.player_team)
			if ap.is_empty(): break
			ai_tgt = ap[randi() % ap.size()] as Character
		var player_counter = p_selections.get(ai_tgt, {}).get("action")
		clash_pairs.append(BattleManager.ClashPair.new(
			atk, ai_act, ai_tgt, player_counter))

	clash_pairs.sort_custom(func(a, b) -> bool:
		var ca := a as BattleManager.ClashPair
		var cb := b as BattleManager.ClashPair
		if ca.has_first_strike() and not cb.has_first_strike(): return true
		if cb.has_first_strike() and not ca.has_first_strike(): return false
		return ca.get_activation_cost() < cb.get_activation_cost()
	)

	var results := bm.phase_resolution(clash_pairs)

	# 活性位点：加成伤害 + 节点稳定性损耗
	for i in range(results.size()):
		var res: Dictionary = results[i]
		var atk: Character = res.get("attacker")
		var def: Character = res.get("defender")
		if atk == null or def == null or def.structure_nodes.is_empty(): continue
		var node_id: String = str(p_selections.get(atk, {}).get("node_id", ""))
		if node_id == "": continue
		var act = p_selections.get(atk, {}).get("action")
		var act_tags: Array = act.chem_tags if act != null and "chem_tags" in act else []
		var is_vuln := def.check_node_vulnerability(node_id, act_tags)
		var mult: float = 1.45 if is_vuln else 1.0
		res["attack_damage"] = float(res.get("attack_damage", 0.0)) * mult
		var dmg_r := def.damage_node(node_id, 0.25)
		if dmg_r.get("hit"):
			if is_vuln:
				_log_append("[color=#ffee44]  ★ 活性位点命中！[%s] 伤害×%.2f  稳定→%.0f%%[/color]" % [
					dmg_r.get("label","?"), mult, float(dmg_r.get("remaining",0))*100])
			if dmg_r.get("destroyed"):
				_log_append("[color=#ff4444]  ❌ 节点[%s]摧毁！[/color]" % dmg_r.get("label","?"))

	bm.phase_apply(results)

	# ── 记录 Boss 被命中的规则（用于特殊胜利条件）────────
	for res in results:
		var def: Character = res.get("defender")
		if def is Boss:
			(def as Boss).last_hit_rule = res.get("attack_rule", "")

	_flush_bm_log()
	_update_all_chars()
	_update_env_bar()

	# ── Boss 形态切换检测 ─────────────────────────────────
	_check_boss_phase_transitions()

	for atk in enemy_sel:
		var ai_act = enemy_sel[atk].get("action")
		if ai_act != null:
			(atk as Character).use_action_from_standby(ai_act)

	# ── 特殊胜利条件检测 ──────────────────────────────────
	for c in bm.enemy_team:
		if c is Boss:
			var b := c as Boss
			if b.special_win_condition.is_valid() and b.special_win_condition.call():
				_trigger_special_ending(b)
				return

	if await _check_and_end(): return
	prompt_lbl.text = "回合结束..."
	await get_tree().create_timer(1.0).timeout
	_begin_turn()

func _check_boss_phase_transitions() -> void:
	for c in bm.enemy_team:
		if not (c is Boss): continue
		var boss := c as Boss
		var new_phase = boss.check_and_advance_phase()
		if new_phase != null:
			var p := new_phase as Boss.BossPhase
			# 日志记录
			_log_append("\n[color=#ffffff]══════════════════════════════[/color]")
			if p.entry_message != "":
				_log_append("[color=#ccaaff]%s[/color]" % p.entry_message)
			_log_append("[color=#ffffff]══════════════════════════════[/color]\n")
			# 环境扰动
			if not p.env_on_enter.is_empty():
				var changes := bm.environment.apply_delta(p.env_on_enter)
				if not changes.is_empty():
					_log_append("[color=#88aaff][形态切换环境扰动] " + "  ".join(changes) + "[/color]")
			_update_all_chars()
			_update_env_bar()
			# 戏剧性公告（异步，2秒后自动消失）
			if p.entry_message != "":
				_show_phase_announcement(p.phase_name, p.entry_message, p.phase_color)

func _trigger_special_ending(boss: Boss) -> void:
	phase = Phase.BATTLE_END
	_log_append("\n[color=#ffffff]══════════════════════════════[/color]")
	_log_append("[color=#ccaaff]" + boss.special_win_message + "[/color]")
	_log_append("[color=#ffffff]══════════════════════════════[/color]")
	_log_append("\n[color=#44ffcc]✦ 特殊结局：完全还原 ✦[/color]")
	prompt_lbl.text = "✦ 特殊结局达成"

# ══════════════════════════════════════════════════════════
# UI 更新
# ══════════════════════════════════════════════════════════
func _update_all_chars() -> void:
	for c in hp_bar_map.keys(): _update_char_ui(c)

func _update_char_ui(c: Character) -> void:
	var bar: ProgressBar = hp_bar_map[c]
	var txt: Label       = hp_txt_map[c]
	var hnd: Label       = hand_lbl_map[c]
	var ratio := c.get_hp_ratio()

	# Boss 使用形态颜色；其他角色使用 HP 颜色
	var bar_color: Color
	if c is Boss:
		bar_color = (c as Boss).get_phase_color() if c.is_alive() else Color(0.35, 0.35, 0.35)
		# 更新形态标签
		if phase_lbl_map.has(c):
			var pl: Label = phase_lbl_map[c]
			var p := (c as Boss).get_current_phase()
			pl.text = p.phase_name if p else ""
			pl.add_theme_color_override("font_color", (c as Boss).get_phase_color())
	else:
		bar_color = (C_HP_HI if ratio > 0.60 else (C_HP_MD if ratio > 0.30 else C_HP_LO)) \
			if c.is_alive() else Color(0.40, 0.40, 0.40)

	bar.value = c.hp; bar.max_value = c.max_hp
	bar.modulate = bar_color
	txt.text = "HP %.0f / %.0f%s" % [c.hp, c.max_hp, "" if c.is_alive() else "  ☠"]
	hnd.text = "谱:%d 手:%d 沉:%d  AE:%.0f" % [
		c.behavior_spectrum.size(), c.standby.size(), c.sediment.size(),
		c.energy_pool.get(Character.ENERGY_ACTIVATION, 0.0)]
	# 状态效果列表
	if status_lbl_map.has(c):
		var sl: Label = status_lbl_map[c]
		if c.status_effects.is_empty():
			sl.text = ""
		else:
			var parts: Array = []
			for eff in c.status_effects:
				var etype: String = str(eff.get("type", ""))
				var dur: int = int(eff.get("duration", 0))
				parts.append("[%s×%d]" % [etype, dur])
			sl.text = "状态：" + " ".join(parts)
	if node_display_map.has(c) and not c.structure_nodes.is_empty():
		var nl: Label = node_display_map[c]
		var parts2: Array = []
		for node in c.structure_nodes:
			var stab: float = float(node.get("stability", 1.0))
			var lbl: String = node.get("label", "?")
			if stab <= 0.0:       parts2.append("[☠%s]" % lbl)
			elif stab < 0.40:    parts2.append("[⚠%s %.0f%%]" % [lbl, stab*100])
			else:                parts2.append("[%s %.0f%%]" % [lbl, stab*100])
		nl.text = "节点：" + "  ".join(parts2)

func _update_env_bar() -> void:
	if not is_instance_valid(env_label): return
	var e := bm.environment
	env_label.text = "⚗ pH=%.1f(%s)  🌡%.0f°C(%s)  🌀熵=%.0f(%s)  |  回合 %d" % [
		e.pH, e.get_pH_zone(), e.temperature, e.get_temp_zone(),
		e.entropy, e.get_entropy_zone(), turn_number]

func _rebuild_action_buttons(chara: Character) -> void:
	_clear_action_buttons()
	for action in chara.standby:
		var affordable: bool = chara.can_afford(action.energy_cost)
		var is_s: bool = not action.has_method("is_intervention") or action.is_strike()
		var type_tag: String = "[攻势]" if is_s else \
			("[调控·场地]" if (action.has_method("is_field_intervention") \
				and action.is_field_intervention()) else "[调控·定向]")
		var cost: float = float(action.energy_cost.get(Character.ENERGY_ACTIVATION, 0.0))
		var tags_str: String = ", ".join(action.chem_tags) if not action.chem_tags.is_empty() else "通用"
		var intensity: float = action.base_intensity if "base_intensity" in action else 0.0
		var btn := Button.new()
		btn.text = "%s %s\n%s  AE:%.0f  强:%.0f" % [type_tag, action.action_name, tags_str, cost, intensity]
		btn.disabled = not affordable
		btn.custom_minimum_size = Vector2(155, 60)
		btn.modulate = (C_STRIKE if is_s else C_INTERV) if affordable else Color(0.45, 0.45, 0.50)
		var ca = action; var cc = chara
		btn.pressed.connect(func(): _on_action_picked(ca, cc))
		action_row.add_child(btn)
	var pb := Button.new()
	pb.text = "Pass\n（跳过）"; pb.custom_minimum_size = Vector2(80, 60)
	pb.modulate = Color(0.45, 0.45, 0.50)
	var cap := chara
	pb.pressed.connect(func(): _on_pass_pressed(cap))
	action_row.add_child(pb)

func _clear_action_buttons() -> void:
	for ch in action_row.get_children(): ch.queue_free()

# ── 敌方AI：综合评分选行动，化学克制关系选目标 ─────────────────
func _ai_pick_action_and_target(enemy: Character) -> Dictionary:
	if enemy.standby.is_empty():
		enemy.draw_to_standby()
	var affordable := enemy.get_affordable_standby()
	if affordable.is_empty(): return {}

	# 行动评分
	var best_action = null
	var best_action_score := -999.0
	for action in affordable:
		var score := 0.0
		var intensity: float = action.base_intensity if "base_intensity" in action else 10.0
		score += intensity
		# 血量低于30%时更激进（优先高伤害）
		if enemy.get_hp_ratio() < 0.30:
			score += intensity * 0.6
		# 携带先手关键字加分
		if action.has_method("has_keyword") and action.has_keyword("先手"):
			score += 12.0
		# 调控型行动：根据战场状态决定是否值得
		if action.has_method("is_intervention") and action.is_intervention():
			# 熵过高时优先降熵，否则降低优先级
			var entropy: float = bm.environment.entropy
			score = 18.0 if entropy > 60.0 else 10.0
		if score > best_action_score:
			best_action_score = score
			best_action = action

	if best_action == null: return {}

	# 目标评分：优先低血 + 化学克制
	var alive_players := _alive_in(bm.player_team)
	if alive_players.is_empty(): return {}

	var best_target: Character = null
	var best_target_score := -999.0
	var action_tags: Array = best_action.chem_tags if "chem_tags" in best_action else []

	for p in alive_players:
		var pc := p as Character
		# 基础分：血量越低越优先（瞄准快倒下的目标）
		var tscore := (1.0 - pc.get_hp_ratio()) * 60.0
		# 化学克制：如果敌方行动能克制这名玩家，额外加分
		for tag in action_tags:
			var weak_tag := _chemical_counter(tag)
			if weak_tag != "" and pc.has_skill_with_tag(weak_tag):
				tscore += 10.0   # 降低克制加分（原25），避免集中火力单人死亡
				break
		if tscore > best_target_score:
			best_target_score = tscore
			best_target = pc

	if best_target == null:
		best_target = alive_players[0] as Character

	return {"action": best_action, "target": best_target}

# 化学克制关系：氧化剂克制还原性目标，酸克制碱，等
func _chemical_counter(attacker_tag: String) -> String:
	match attacker_tag:
		"oxidizing":   return "reducing"
		"reducing":    return "oxidizing"
		"acidic":      return "alkaline"
		"alkaline":    return "acidic"
		"halogen":     return "reducing"
		"exothermic":  return "endothermic"
		_:             return ""


func _deploy_catalyst_from_action(action, chara: Character) -> void:
	var cat: Catalyst
	if "镍" in action.action_name:
		cat = Catalyst.make_nickel_catalyst(3)
	elif "H₂SO₄" in action.action_name or "硫酸" in action.action_name:
		cat = Catalyst.make_sulfuric_catalyst(2)
	else:
		return
	bm.deploy_catalyst(cat, chara)
	_log_append("[color=#aaff88]  ✦ %s 部署了 [%s][/color]" % [
		chara.char_name, cat.catalyst_name])

func _check_and_end() -> bool:
	var w := bm.phase_check_victory()
	if w == "": return false
	phase = Phase.BATTLE_END
	var won: bool = (w == "player")
	if won:
		_log_append("\n[color=#44ffaa]★ 玩家队伍获胜！★[/color]")
	else:
		_log_append("\n[color=#ff6644]✖ 敌方获胜[/color]")
	_log_append("共 %d 回合  最终环境：%s" % [turn_number, bm.environment.get_summary()])
	_clear_action_buttons()
	prompt_lbl.text = "战斗结束"
	# 短暂延迟后显示结算界面（让玩家看到最后一轮日志）
	await get_tree().create_timer(1.5).timeout
	_show_result_screen(won)
	return true

func _log_append(text: String) -> void:
	if is_instance_valid(log_rtl): log_rtl.append_text(text + "\n")

func _flush_bm_log() -> void:
	if bm.battle_log.is_empty(): return
	var lines := "\n".join(bm.battle_log).split("\n")
	bm.battle_log.clear()
	for line in lines:
		if line.strip_edges().is_empty(): continue
		if "命中规则" in line:  _log_append("[color=#ffdd55]" + line + "[/color]")
		elif "⚔" in line:      _log_append("[color=#ffaa66]" + line + "[/color]")
		elif "环境" in line:   _log_append("[color=#88aaff]" + line + "[/color]")
		else:                  _log_append("[color=#cccccc]" + line + "[/color]")

func _all_alive() -> Array:
	return _alive_in(bm.player_team) + _alive_in(bm.enemy_team)

func _alive_in(team: Array) -> Array:
	var r: Array = []
	for c in team:
		if (c as Character).is_alive(): r.append(c)
	return r
