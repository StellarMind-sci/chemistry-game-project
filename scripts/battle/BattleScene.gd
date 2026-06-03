# BattleScene.gd
# 最小战斗 UI 控制器 v0.1
# 架构：BattleScene 手动管理回合流程，玩家点击选择行动，敌方 AI 自动应对
# 所有 UI 节点由代码创建，无需编辑器布局
extends Node

# ══════════════════════════════════════════════════════════
# 枚举与常量
# ══════════════════════════════════════════════════════════
enum Phase { INIT, PLAYER_INPUT, RESOLVING, BATTLE_END }
var phase: Phase = Phase.INIT

const C_BG       := Color(0.055, 0.065, 0.100)
const C_PANEL    := Color(0.095, 0.115, 0.175)
const C_PLAYER   := Color(0.35,  0.75,  1.00)
const C_ENEMY    := Color(1.00,  0.50,  0.25)
const C_HP_HI    := Color(0.25,  0.85,  0.45)
const C_HP_MD    := Color(0.95,  0.80,  0.15)
const C_HP_LO    := Color(0.92,  0.22,  0.18)
const C_STRIKE   := Color(0.80,  0.35,  0.18)
const C_INTERV   := Color(0.18,  0.50,  0.85)
const C_TEXT     := Color(0.90,  0.90,  0.95)
const C_DIMMED   := Color(0.45,  0.45,  0.50)

# ══════════════════════════════════════════════════════════
# 游戏数据
# ══════════════════════════════════════════════════════════
var bm:     BattleManager
var engine: ReactionInference
var turn_number: int = 0

# 玩家输入状态
var p_selections: Dictionary = {}   # Character → ReactionAction
var select_queue: Array       = []   # 待选队列
var cur_selector: Character   = null

# ══════════════════════════════════════════════════════════
# UI 节点引用（在 _build_ui 中赋值）
# ══════════════════════════════════════════════════════════
var env_label:    Label
var player_col:   VBoxContainer
var enemy_col:    VBoxContainer
var log_rtl:      RichTextLabel
var prompt_lbl:   Label
var action_row:   HBoxContainer

# 角色 UI 映射
var hp_bar_map:  Dictionary = {}   # Character → ProgressBar
var hp_txt_map:  Dictionary = {}   # Character → Label
var hand_lbl_map: Dictionary = {}  # Character → Label

# ══════════════════════════════════════════════════════════
# 启动
# ══════════════════════════════════════════════════════════
func _ready() -> void:
	_build_ui()
	_init_battle()
	call_deferred("_begin_turn")

# ══════════════════════════════════════════════════════════
# UI 构建
# ══════════════════════════════════════════════════════════
func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 根布局
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)

	# ── 环境状态栏 ────────────────────────────────────────
	var env_panel := _make_color_panel(Color(0.07, 0.10, 0.16))
	env_panel.custom_minimum_size = Vector2(0, 36)
	vb.add_child(env_panel)
	env_label = Label.new()
	env_label.add_theme_font_size_override("font_size", 13)
	env_label.add_theme_color_override("font_color", Color(0.60, 0.85, 1.00))
	env_panel.add_child(env_label)

	# ── 角色区（左=玩家，右=敌方）────────────────────────
	var char_row := HBoxContainer.new()
	char_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	char_row.size_flags_stretch_ratio = 0.32
	char_row.add_theme_constant_override("separation", 6)
	vb.add_child(char_row)

	player_col = VBoxContainer.new()
	player_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_col.add_theme_constant_override("separation", 4)
	char_row.add_child(player_col)

	var divider := ColorRect.new()
	divider.color = Color(0.25, 0.40, 0.65, 0.50)
	divider.custom_minimum_size = Vector2(2, 0)
	char_row.add_child(divider)

	enemy_col = VBoxContainer.new()
	enemy_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_col.add_theme_constant_override("separation", 4)
	char_row.add_child(enemy_col)

	# ── 战斗日志 ──────────────────────────────────────────
	log_rtl = RichTextLabel.new()
	log_rtl.bbcode_enabled = true
	log_rtl.scroll_following = true
	log_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_rtl.size_flags_stretch_ratio = 0.43
	log_rtl.add_theme_font_size_override("normal_font_size", 13)
	_apply_sb(log_rtl, Color(0.06, 0.08, 0.13))
	vb.add_child(log_rtl)

	# ── 行动区 ────────────────────────────────────────────
	var action_panel := _make_color_panel(Color(0.07, 0.09, 0.15))
	action_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_panel.size_flags_stretch_ratio = 0.25
	vb.add_child(action_panel)

	var action_vb := VBoxContainer.new()
	action_vb.add_theme_constant_override("separation", 5)
	action_vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	action_panel.add_child(action_vb)

	prompt_lbl = Label.new()
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.add_theme_font_size_override("font_size", 14)
	prompt_lbl.add_theme_color_override("font_color", Color(0.92, 0.85, 0.35))
	action_vb.add_child(prompt_lbl)

	action_row = HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 8)
	action_vb.add_child(action_row)

# ── 辅助：创建带 StyleBox 的 ColorRect 容器 ──────────────
func _make_color_panel(color: Color) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_top",    6)
	mc.add_theme_constant_override("margin_bottom", 6)
	mc.add_theme_constant_override("margin_left",   10)
	mc.add_theme_constant_override("margin_right",  10)
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
	sb.content_margin_top    = 8
	sb.content_margin_bottom = 8
	sb.content_margin_left   = 12
	sb.content_margin_right  = 12
	if node is RichTextLabel:
		node.add_theme_stylebox_override("normal", sb)

# ── 为角色创建一组 UI 小部件 ──────────────────────────────
func _make_char_panel(chara: Character, is_player: bool) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	# 名称行
	var name_lbl := Label.new()
	name_lbl.text = chara.char_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color",
		C_PLAYER if is_player else C_ENEMY)
	container.add_child(name_lbl)

	# HP 条
	var hp_bar := ProgressBar.new()
	hp_bar.max_value    = chara.max_hp
	hp_bar.value        = chara.hp
	hp_bar.custom_minimum_size = Vector2(0, 14)
	hp_bar.show_percentage = false
	hp_bar_map[chara] = hp_bar
	container.add_child(hp_bar)

	# HP 数值文字
	var hp_txt := Label.new()
	hp_txt.text = "HP %.0f / %.0f" % [chara.hp, chara.max_hp]
	hp_txt.add_theme_font_size_override("font_size", 12)
	hp_txt.add_theme_color_override("font_color", Color(0.75, 0.90, 0.75))
	hp_txt_map[chara] = hp_txt
	container.add_child(hp_txt)

	# 手牌信息
	var hand_lbl := Label.new()
	hand_lbl.text = "谱:%d 手:%d 沉:%d" % [
		chara.behavior_spectrum.size(), chara.standby.size(), chara.sediment.size()]
	hand_lbl.add_theme_font_size_override("font_size", 11)
	hand_lbl.add_theme_color_override("font_color", C_DIMMED)
	hand_lbl_map[chara] = hand_lbl
	container.add_child(hand_lbl)

	return container

# ══════════════════════════════════════════════════════════
# 战斗初始化
# ══════════════════════════════════════════════════════════
func _init_battle() -> void:
	engine = ReactionInference.new()
	engine.load_databases(
		"res://data/substances/substance_registry.json",
		"res://data/reactions/reaction_rules.json")

	# 玩家角色一：酸性攻击手
	var pa := Character.new("实验者·酸", "player", 300.0)
	pa.draw_count = 2
	var hcl := ReactionAction.from_substance(engine, "HCl", ReactionAction.TYPE_STRIKE)
	hcl.action_name = "盐酸冲击"
	hcl.energy_cost = {Character.ENERGY_ACTIVATION: 15.0}
	var sul := ReactionAction.from_substance(engine, "H2SO4", ReactionAction.TYPE_STRIKE)
	sul.action_name = "硫酸腐蚀"
	sul.energy_cost = {Character.ENERGY_ACTIVATION: 20.0}
	var heat := ReactionAction.make_field_intervention("升温催化", {"temp_delta": 12.0}, 2)
	heat.energy_cost = {Character.ENERGY_ACTIVATION: 8.0}
	pa.add_to_spectrum(hcl)
	pa.add_to_spectrum(sul)
	pa.add_to_spectrum(heat)

	# 玩家角色二：氧化攻击手
	var pb := Character.new("实验者·氧", "player", 280.0)
	pb.draw_count = 2
	var kmo := ReactionAction.from_substance(engine, "KMnO4", ReactionAction.TYPE_STRIKE)
	kmo.action_name = "高锰酸钾"
	kmo.energy_cost = {Character.ENERGY_ACTIVATION: 25.0, Character.ENERGY_ELECTRON: 2.0}
	kmo.keywords    = ["先手"]
	var nab := ReactionAction.from_substance(engine, "Na", ReactionAction.TYPE_STRIKE)
	nab.action_name = "钠焰爆燃"
	nab.energy_cost = {Character.ENERGY_ACTIVATION: 30.0}
	pb.add_to_spectrum(kmo)
	pb.add_to_spectrum(nab)

	# 敌方：铜绿（占位）
	var ea := Character.new("铜绿 Cu₂(OH)₂CO₃", "enemy", 600.0)
	ea.draw_count = 2
	var bs := ReactionAction.new("碱性防御")
	bs.element_tags = ["Cu","O","H"]
	bs.chem_tags    = [ReactionAction.TAG_ALKALINE, ReactionAction.TAG_HYDROXYL]
	bs.energy_cost  = {Character.ENERGY_ACTIVATION: 10.0}
	bs.base_intensity = 12.0
	var co := ReactionAction.new("铜离子冲击")
	co.element_tags = ["Cu","O"]
	co.chem_tags    = [ReactionAction.TAG_OXIDIZING]
	co.energy_cost  = {Character.ENERGY_ACTIVATION: 20.0, Character.ENERGY_ELECTRON: 1.0}
	co.base_intensity = 28.0
	ea.add_to_spectrum(bs)
	ea.add_to_spectrum(co)

	# 初始化 BattleManager
	bm = BattleManager.new()
	bm.setup_teams([pa, pb], [ea])

	# 构建角色面板
	var hdr_p := Label.new()
	hdr_p.text = "▶ 玩家队伍"
	hdr_p.add_theme_color_override("font_color", C_PLAYER)
	hdr_p.add_theme_font_size_override("font_size", 13)
	player_col.add_child(hdr_p)
	for c in bm.player_team:
		player_col.add_child(_make_char_panel(c, true))

	var hdr_e := Label.new()
	hdr_e.text = "◀ 敌方队伍"
	hdr_e.add_theme_color_override("font_color", C_ENEMY)
	hdr_e.add_theme_font_size_override("font_size", 13)
	enemy_col.add_child(hdr_e)
	for c in bm.enemy_team:
		enemy_col.add_child(_make_char_panel(c, false))

	_log_append("[color=#88ff88]⚗ 战斗开始！玩家2名 vs 敌人1名[/color]")
	_update_env_bar()

# ══════════════════════════════════════════════════════════
# 回合流程
# ══════════════════════════════════════════════════════════
func _begin_turn() -> void:
	if phase == Phase.BATTLE_END: return
	turn_number += 1
	bm.turn_count = turn_number

	# 所有存活角色恢复能量
	for c in _all_alive():
		c.restore_energy_per_turn()

	# 阶段一：环境效果
	bm.phase_env_effects()
	_update_all_chars()
	_update_env_bar()
	_flush_bm_log()

	# 检查胜负（开始就有死亡？）
	if _check_and_end(): return

	# 所有角色抽牌
	for c in _all_alive():
		if c.standby.is_empty():
			c.draw_to_standby()
	_update_all_chars()

	_log_append("\n[color=#aaffaa]── 回合 %d ──[/color]" % turn_number)
	_start_player_input()

func _start_player_input() -> void:
	phase = Phase.PLAYER_INPUT
	p_selections.clear()
	# 收集有手牌且存活的玩家角色
	select_queue = []
	for c in bm.player_team:
		if c.is_alive() and not c.standby.is_empty():
			select_queue.append(c)
	_next_selector()

func _next_selector() -> void:
	if select_queue.is_empty():
		# 所有玩家角色已选完 → 开始解算
		_resolve_turn()
		return
	cur_selector = select_queue.pop_front()
	prompt_lbl.text = "%s — 请选择反应行动" % cur_selector.char_name
	_rebuild_action_buttons(cur_selector)

func _on_action_picked(action, chara: Character) -> void:
	if phase != Phase.PLAYER_INPUT: return
	p_selections[chara] = action
	_log_append("  [color=%s]%s[/color] 选择：[color=#ffdd44]%s[/color]" % [
		"#44ccff", chara.char_name, action.action_name])
	_clear_action_buttons()
	_next_selector()

func _on_pass_pressed(chara: Character) -> void:
	if phase != Phase.PLAYER_INPUT: return
	_log_append("  [color=#888888]%s Pass（跳过）[/color]" % chara.char_name)
	_clear_action_buttons()
	_next_selector()

# ── 解算回合 ─────────────────────────────────────────────
func _resolve_turn() -> void:
	phase = Phase.RESOLVING
	prompt_lbl.text = "解算中..."

	# 敌方 AI 自动选行动
	var enemy_selections: Dictionary = {}
	for c in bm.enemy_team:
		if c.is_alive():
			var act = bm._pick_action(c)
			if act != null:
				enemy_selections[c] = act

	# 构建 ClashPairs
	var clash_pairs: Array = []
	for atk in bm.player_team:
		if not atk.is_alive() or not p_selections.has(atk): continue
		var targets := _alive_in(bm.enemy_team)
		if targets.is_empty(): break
		var def = targets[randi() % targets.size()]
		clash_pairs.append(BattleManager.ClashPair.new(
			atk, p_selections[atk], def, enemy_selections.get(def)))

	for atk in bm.enemy_team:
		if not atk.is_alive() or not enemy_selections.has(atk): continue
		var targets := _alive_in(bm.player_team)
		if targets.is_empty(): break
		var def = targets[randi() % targets.size()]
		clash_pairs.append(BattleManager.ClashPair.new(
			atk, enemy_selections[atk], def, p_selections.get(def)))

	# 按 P2/P3 排序
	clash_pairs.sort_custom(func(a, b) -> bool:
		var ca := a as BattleManager.ClashPair
		var cb := b as BattleManager.ClashPair
		if ca.has_first_strike() and not cb.has_first_strike(): return true
		if cb.has_first_strike() and not ca.has_first_strike(): return false
		return ca.get_activation_cost() < cb.get_activation_cost()
	)

	# 执行阶段三四
	var results := bm.phase_resolution(clash_pairs)
	bm.phase_apply(results)
	_flush_bm_log()
	_update_all_chars()
	_update_env_bar()

	# 消耗行动进沉淀区（enemy）
	for atk in enemy_selections:
		(atk as Character).use_action_from_standby(enemy_selections[atk])

	if _check_and_end(): return
	prompt_lbl.text = "回合结束，准备下一回合..."
	# 短暂延迟后开始下一回合
	await get_tree().create_timer(1.2).timeout
	_begin_turn()

# ══════════════════════════════════════════════════════════
# UI 更新
# ══════════════════════════════════════════════════════════
func _update_all_chars() -> void:
	for c in hp_bar_map.keys():
		_update_char_ui(c)

func _update_char_ui(c: Character) -> void:
	var bar: ProgressBar = hp_bar_map[c]
	var txt: Label       = hp_txt_map[c]
	var hnd: Label       = hand_lbl_map[c]
	var ratio := c.get_hp_ratio()
	bar.value     = c.hp
	bar.max_value = c.max_hp
	# 根据血量比例动态改变颜色
	var hp_color: Color
	if ratio > 0.60:   hp_color = C_HP_HI
	elif ratio > 0.30: hp_color = C_HP_MD
	else:              hp_color = C_HP_LO
	bar.modulate = hp_color if c.is_alive() else Color(0.40, 0.40, 0.40)
	txt.text = "HP %.0f / %.0f%s" % [c.hp, c.max_hp, "" if c.is_alive() else "  ☠"]
	hnd.text = "谱:%d 手:%d 沉:%d  AE:%.0f" % [
		c.behavior_spectrum.size(), c.standby.size(), c.sediment.size(),
		c.energy_pool.get(Character.ENERGY_ACTIVATION, 0.0)]

func _update_env_bar() -> void:
	if env_label and is_instance_valid(env_label):
		var env := bm.environment
		env_label.text = (
			"⚗ pH=%.1f(%s)  🌡温度=%.0f°C(%s)  🌀熵=%.0f(%s)  |  回合 %d") % [
			env.pH,         env.get_pH_zone(),
			env.temperature, env.get_temp_zone(),
			env.entropy,    env.get_entropy_zone(),
			turn_number]

func _rebuild_action_buttons(chara: Character) -> void:
	_clear_action_buttons()
	for action in chara.standby:
		var affordable: bool = chara.can_afford(action.energy_cost)
		var btn := Button.new()
		var is_strike: bool = not action.has_method("is_intervention") \
			or action.is_strike()
		var type_str: String = "[攻势]" if is_strike else \
			("[调控·场地]" if (action.has_method("is_field_intervention") \
				and action.is_field_intervention()) else "[调控·定向]")
		var cost: float = float(action.energy_cost.get(Character.ENERGY_ACTIVATION, 0.0))
		btn.text = "%s %s\n%s  AE:%.0f  强度:%.0f" % [
			type_str, action.action_name,
			", ".join(action.chem_tags) if not action.chem_tags.is_empty() else "通用",
			cost, action.base_intensity if "base_intensity" in action else 0.0]
		btn.disabled = not affordable
		btn.custom_minimum_size = Vector2(160, 60)
		btn.modulate = (C_STRIKE if is_strike else C_INTERV) if affordable else C_DIMMED
		var cap_act = action
		var cap_char = chara
		btn.pressed.connect(func(): _on_action_picked(cap_act, cap_char))
		action_row.add_child(btn)

	# Pass 按钮
	var pass_btn := Button.new()
	pass_btn.text = "Pass\n（跳过）"
	pass_btn.custom_minimum_size = Vector2(80, 60)
	pass_btn.modulate = C_DIMMED
	var cap = chara
	pass_btn.pressed.connect(func(): _on_pass_pressed(cap))
	action_row.add_child(pass_btn)

func _clear_action_buttons() -> void:
	for child in action_row.get_children():
		child.queue_free()

# ══════════════════════════════════════════════════════════
# 胜负判定
# ══════════════════════════════════════════════════════════
func _check_and_end() -> bool:
	var w := bm.phase_check_victory()
	if w == "": return false
	phase = Phase.BATTLE_END
	if w == "player":
		_log_append("\n[color=#44ffaa]★ 玩家队伍获胜！★[/color]")
		prompt_lbl.text = "★ 玩家胜利！"
	else:
		_log_append("\n[color=#ff6644]✖ 敌方队伍获胜[/color]")
		prompt_lbl.text = "✖ 失败..."
	_log_append("共进行 %d 回合  最终环境：%s" % [turn_number, bm.environment.get_summary()])
	return true

# ══════════════════════════════════════════════════════════
# 日志辅助
# ══════════════════════════════════════════════════════════
func _log_append(text: String) -> void:
	if log_rtl and is_instance_valid(log_rtl):
		log_rtl.append_text(text + "\n")

func _flush_bm_log() -> void:
	# 把 BattleManager 积累的纯文本日志推入 RichTextLabel
	if bm.battle_log.is_empty(): return
	var raw: String = "\n".join(bm.battle_log)
	bm.battle_log.clear()
	# 简单着色：将命中规则的行标黄
	var lines := raw.split("\n")
	for line in lines:
		if line.strip_edges().is_empty(): continue
		if "命中规则" in line:
			_log_append("[color=#ffdd55]" + line + "[/color]")
		elif "⚔" in line:
			_log_append("[color=#ffaa66]" + line + "[/color]")
		elif "环境" in line:
			_log_append("[color=#88aaff]" + line + "[/color]")
		else:
			_log_append("[color=#cccccc]" + line + "[/color]")

# ══════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════
func _all_alive() -> Array:
	return _alive_in(bm.player_team) + _alive_in(bm.enemy_team)

func _alive_in(team: Array) -> Array:
	var r: Array = []
	for c in team:
		if (c as Character).is_alive(): r.append(c)
	return r
