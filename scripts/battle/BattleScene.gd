# BattleScene.gd  v0.2
# 新增：目标选择——玩家选行动后可指定攻击哪个敌人
extends Node

enum Phase { INIT, PLAYER_INPUT, TARGET_SELECT, RESOLVING, BATTLE_END }
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
const C_TARGET   := Color(0.90,  0.80,  0.10)   # 目标选择按钮颜色
const C_TEXT     := Color(0.90,  0.90,  0.95)
const C_DIMMED   := Color(0.45,  0.45,  0.50)

# ── 游戏数据 ─────────────────────────────────────────────
var bm:     BattleManager
var engine: ReactionInference
var turn_number: int = 0

# 玩家输入状态
var p_selections: Dictionary = {}   # Character → {action, target}
var select_queue: Array       = []
var cur_selector: Character   = null
var pending_action            = null  # 等待目标选择时暂存的行动
var pending_char: Character   = null

# ── UI 节点引用 ───────────────────────────────────────────
var env_label:  Label
var player_col: VBoxContainer
var enemy_col:  VBoxContainer
var log_rtl:    RichTextLabel
var prompt_lbl: Label
var action_row: HBoxContainer

var hp_bar_map:   Dictionary = {}
var hp_txt_map:   Dictionary = {}
var hand_lbl_map: Dictionary = {}

# ══════════════════════════════════════════════════════════
func _ready() -> void:
	_build_ui()
	_init_battle()
	call_deferred("_begin_turn")

# ══════════════════════════════════════════════════════════
# UI 构建
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

	# 环境状态栏
	var ep := _make_margin(Color(0.07, 0.10, 0.16))
	ep.custom_minimum_size = Vector2(0, 36)
	vb.add_child(ep)
	env_label = Label.new()
	env_label.add_theme_font_size_override("font_size", 13)
	env_label.add_theme_color_override("font_color", Color(0.60, 0.85, 1.00))
	ep.add_child(env_label)

	# 角色区
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

	# 战斗日志
	log_rtl = RichTextLabel.new()
	log_rtl.bbcode_enabled = true
	log_rtl.scroll_following = true
	log_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_rtl.size_flags_stretch_ratio = 0.45
	log_rtl.add_theme_font_size_override("normal_font_size", 13)
	_apply_sb(log_rtl, Color(0.06, 0.08, 0.13))
	vb.add_child(log_rtl)

	# 行动区
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

func _make_margin(color: Color) -> MarginContainer:
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
	sb.content_margin_top    = 8; sb.content_margin_bottom = 8
	sb.content_margin_left   = 12; sb.content_margin_right  = 12
	if node is RichTextLabel: node.add_theme_stylebox_override("normal", sb)

func _make_char_panel(chara: Character, is_player: bool) -> Control:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 2)
	var nl := Label.new()
	nl.text = chara.char_name
	nl.add_theme_font_size_override("font_size", 14)
	nl.add_theme_color_override("font_color", C_PLAYER if is_player else C_ENEMY)
	c.add_child(nl)
	var bar := ProgressBar.new()
	bar.max_value = chara.max_hp; bar.value = chara.hp
	bar.custom_minimum_size = Vector2(0, 14); bar.show_percentage = false
	hp_bar_map[chara] = bar; c.add_child(bar)
	var ht := Label.new()
	ht.text = "HP %.0f / %.0f" % [chara.hp, chara.max_hp]
	ht.add_theme_font_size_override("font_size", 12)
	ht.add_theme_color_override("font_color", Color(0.75, 0.90, 0.75))
	hp_txt_map[chara] = ht; c.add_child(ht)
	var hl := Label.new()
	hl.text = "谱:%d 手:%d 沉:%d" % [chara.behavior_spectrum.size(),
		chara.standby.size(), chara.sediment.size()]
	hl.add_theme_font_size_override("font_size", 11)
	hl.add_theme_color_override("font_color", C_DIMMED)
	hand_lbl_map[chara] = hl; c.add_child(hl)
	return c

# ══════════════════════════════════════════════════════════
# 战斗初始化
# ══════════════════════════════════════════════════════════
func _init_battle() -> void:
	engine = ReactionInference.new()
	engine.load_databases("res://data/substances/substance_registry.json",
		"res://data/reactions/reaction_rules.json")

	var pa := Character.new("实验者·酸", "player", 300.0)
	pa.draw_count = 2
	var hcl := ReactionAction.from_substance(engine, "HCl",   ReactionAction.TYPE_STRIKE)
	hcl.action_name = "盐酸冲击";   hcl.energy_cost = {Character.ENERGY_ACTIVATION: 15.0}
	var sul := ReactionAction.from_substance(engine, "H2SO4", ReactionAction.TYPE_STRIKE)
	sul.action_name = "硫酸腐蚀";   sul.energy_cost = {Character.ENERGY_ACTIVATION: 20.0}
	var heat := ReactionAction.make_field_intervention("升温催化", {"temp_delta": 8.0}, 2)
	heat.energy_cost = {Character.ENERGY_ACTIVATION: 8.0}
	pa.add_to_spectrum(hcl); pa.add_to_spectrum(sul); pa.add_to_spectrum(heat)

	var pb := Character.new("实验者·氧", "player", 280.0)
	pb.draw_count = 2
	var kmo := ReactionAction.from_substance(engine, "KMnO4", ReactionAction.TYPE_STRIKE)
	kmo.action_name = "高锰酸钾";   kmo.energy_cost = {Character.ENERGY_ACTIVATION: 25.0, Character.ENERGY_ELECTRON: 2.0}
	kmo.keywords = ["先手"]
	var nab := ReactionAction.from_substance(engine, "Na",    ReactionAction.TYPE_STRIKE)
	nab.action_name = "钠焰爆燃";   nab.energy_cost = {Character.ENERGY_ACTIVATION: 30.0}
	pb.add_to_spectrum(kmo); pb.add_to_spectrum(nab)

	var ea := Character.new("铜绿 Cu₂(OH)₂CO₃", "enemy", 600.0)
	ea.draw_count = 2
	var bs := ReactionAction.new("碱性防御")
	bs.element_tags = ["Cu","O","H"]; bs.chem_tags = [ReactionAction.TAG_ALKALINE, ReactionAction.TAG_HYDROXYL]
	bs.energy_cost = {Character.ENERGY_ACTIVATION: 10.0}; bs.base_intensity = 12.0
	var co := ReactionAction.new("铜离子冲击")
	co.element_tags = ["Cu","O"]; co.chem_tags = [ReactionAction.TAG_OXIDIZING]
	co.energy_cost = {Character.ENERGY_ACTIVATION: 20.0, Character.ENERGY_ELECTRON: 1.0}; co.base_intensity = 28.0
	ea.add_to_spectrum(bs); ea.add_to_spectrum(co)

	bm = BattleManager.new()
	bm.setup_teams([pa, pb], [ea])

	var hp_lbl := Label.new(); hp_lbl.text = "▶ 玩家队伍"
	hp_lbl.add_theme_color_override("font_color", C_PLAYER)
	hp_lbl.add_theme_font_size_override("font_size", 13)
	player_col.add_child(hp_lbl)
	for c in bm.player_team: player_col.add_child(_make_char_panel(c, true))

	var el := Label.new(); el.text = "◀ 敌方队伍"
	el.add_theme_color_override("font_color", C_ENEMY)
	el.add_theme_font_size_override("font_size", 13)
	enemy_col.add_child(el)
	for c in bm.enemy_team: enemy_col.add_child(_make_char_panel(c, false))

	_log_append("[color=#88ff88]⚗ 战斗开始！2 vs 1[/color]")
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
	if _check_and_end(): return
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

# ── 玩家选择行动 ─────────────────────────────────────────
func _on_action_picked(action, chara: Character) -> void:
	if phase != Phase.PLAYER_INPUT: return
	_clear_action_buttons()

	# 调控型行动不需要指定目标（作用于战场，不是特定敌人）
	if action.has_method("is_intervention") and action.is_intervention():
		_finalize_selection(action, chara, null)
		return

	var alive_enemies := _alive_in(bm.enemy_team)
	if alive_enemies.size() == 1:
		# 只有一个敌人，直接自动选中
		_finalize_selection(action, chara, alive_enemies[0])
	elif alive_enemies.is_empty():
		_finalize_selection(action, chara, null)
	else:
		# 多个敌人：进入目标选择阶段
		pending_action = action
		pending_char   = chara
		phase = Phase.TARGET_SELECT
		_show_target_selection(chara)

func _on_target_picked(target: Character) -> void:
	if phase != Phase.TARGET_SELECT: return
	phase = Phase.PLAYER_INPUT
	_clear_action_buttons()
	_finalize_selection(pending_action, pending_char, target)

func _finalize_selection(action, chara: Character, target) -> void:
	p_selections[chara] = {"action": action, "target": target}
	var target_name: String = (target as Character).char_name if target != null else "战场"
	_log_append("  [color=#44ccff]%s[/color] → [color=#ffdd44]%s[/color]  目标：[color=#ffaa44]%s[/color]" % [
		chara.char_name, action.action_name, target_name])
	_next_selector()

func _on_pass_pressed(chara: Character) -> void:
	if phase != Phase.PLAYER_INPUT: return
	_log_append("  [color=#888888]%s Pass[/color]" % chara.char_name)
	_clear_action_buttons()
	_next_selector()

# ── 展示目标选择按钮 ──────────────────────────────────────
func _show_target_selection(attacker: Character) -> void:
	_clear_action_buttons()
	prompt_lbl.text = "%s — 请选择攻击目标" % attacker.char_name
	for target in _alive_in(bm.enemy_team):
		var tgt := target as Character
		var btn := Button.new()
		btn.text = "⚡ %s\nHP %.0f/%.0f" % [tgt.char_name, tgt.hp, tgt.max_hp]
		btn.custom_minimum_size = Vector2(180, 60)
		btn.modulate = C_TARGET
		var cap = tgt
		btn.pressed.connect(func(): _on_target_picked(cap))
		action_row.add_child(btn)

# ══════════════════════════════════════════════════════════
# 解算回合
# ══════════════════════════════════════════════════════════
func _resolve_turn() -> void:
	phase = Phase.RESOLVING
	prompt_lbl.text = "解算中..."
	_clear_action_buttons()

	# 敌方 AI 自动选行动和目标
	var enemy_selections: Dictionary = {}
	for c in bm.enemy_team:
		if c.is_alive():
			var act = bm._pick_action(c)
			if act != null: enemy_selections[c] = act

	# 构建 ClashPairs（使用玩家存储的目标）
	var clash_pairs: Array = []
	for atk in bm.player_team:
		if not atk.is_alive() or not p_selections.has(atk): continue
		var sel: Dictionary = p_selections[atk]
		var act = sel.get("action")
		var tgt = sel.get("target")   # 注意：不用 def，def 在 GDScript 是保留字
		# 如果目标已死亡则重选
		if tgt != null and not (tgt as Character).is_alive():
			var alive_e := _alive_in(bm.enemy_team)
			tgt = alive_e[0] if not alive_e.is_empty() else null
		if tgt == null: continue
		clash_pairs.append(BattleManager.ClashPair.new(
			atk, act, tgt, enemy_selections.get(tgt)))

	for atk in bm.enemy_team:
		if not atk.is_alive() or not enemy_selections.has(atk): continue
		var alive_p := _alive_in(bm.player_team)
		if alive_p.is_empty(): break
		var tgt_p: Character = alive_p[randi() % alive_p.size()] as Character
		clash_pairs.append(BattleManager.ClashPair.new(
			atk, enemy_selections[atk], tgt_p, p_selections.get(tgt_p, {}).get("action")))

	# 按 P2/P3 排序
	clash_pairs.sort_custom(func(a, b) -> bool:
		var ca := a as BattleManager.ClashPair
		var cb := b as BattleManager.ClashPair
		if ca.has_first_strike() and not cb.has_first_strike(): return true
		if cb.has_first_strike() and not ca.has_first_strike(): return false
		return ca.get_activation_cost() < cb.get_activation_cost()
	)

	var results := bm.phase_resolution(clash_pairs)
	bm.phase_apply(results)
	_flush_bm_log()
	_update_all_chars()
	_update_env_bar()

	for atk in enemy_selections:
		(atk as Character).use_action_from_standby(enemy_selections[atk])

	if _check_and_end(): return
	prompt_lbl.text = "回合结束，准备下一回合..."
	await get_tree().create_timer(1.0).timeout
	_begin_turn()

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
	bar.value = c.hp; bar.max_value = c.max_hp
	bar.modulate = (C_HP_HI if ratio > 0.60 else (C_HP_MD if ratio > 0.30 else C_HP_LO)) \
		if c.is_alive() else Color(0.40, 0.40, 0.40)
	txt.text = "HP %.0f / %.0f%s" % [c.hp, c.max_hp, "" if c.is_alive() else "  ☠"]
	hnd.text = "谱:%d 手:%d 沉:%d  AE:%.0f" % [
		c.behavior_spectrum.size(), c.standby.size(), c.sediment.size(),
		c.energy_pool.get(Character.ENERGY_ACTIVATION, 0.0)]

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
		var btn := Button.new()
		var is_s: bool = not action.has_method("is_intervention") or action.is_strike()
		var type_tag: String = "[攻势]" if is_s else \
			("[调控·场地]" if (action.has_method("is_field_intervention") \
				and action.is_field_intervention()) else "[调控·定向]")
		var cost: float = float(action.energy_cost.get(Character.ENERGY_ACTIVATION, 0.0))
		var tags_str: String = ", ".join(action.chem_tags) if not action.chem_tags.is_empty() else "通用"
		var intensity: float = action.base_intensity if "base_intensity" in action else 0.0
		btn.text = "%s %s\n%s  AE:%.0f  强:%.0f" % [
			type_tag, action.action_name, tags_str, cost, intensity]
		btn.disabled = not affordable
		btn.custom_minimum_size = Vector2(155, 60)
		btn.modulate = (C_STRIKE if is_s else C_INTERV) if affordable else C_DIMMED
		var ca = action; var cc = chara
		btn.pressed.connect(func(): _on_action_picked(ca, cc))
		action_row.add_child(btn)
	var pb := Button.new()
	pb.text = "Pass\n（跳过）"
	pb.custom_minimum_size = Vector2(80, 60)
	pb.modulate = C_DIMMED
	var cap = chara
	pb.pressed.connect(func(): _on_pass_pressed(cap))
	action_row.add_child(pb)

func _clear_action_buttons() -> void:
	for ch in action_row.get_children(): ch.queue_free()

# ══════════════════════════════════════════════════════════
# 胜负
# ══════════════════════════════════════════════════════════
func _check_and_end() -> bool:
	var w := bm.phase_check_victory()
	if w == "": return false
	phase = Phase.BATTLE_END
	if w == "player":
		_log_append("\n[color=#44ffaa]★ 玩家队伍获胜！★[/color]")
		prompt_lbl.text = "★ 玩家胜利！"
	else:
		_log_append("\n[color=#ff6644]✖ 敌方获胜[/color]")
		prompt_lbl.text = "✖ 失败..."
	_log_append("共 %d 回合  最终环境：%s" % [turn_number, bm.environment.get_summary()])
	return true

# ══════════════════════════════════════════════════════════
# 日志辅助
# ══════════════════════════════════════════════════════════
func _log_append(text: String) -> void:
	if is_instance_valid(log_rtl): log_rtl.append_text(text + "\n")

func _flush_bm_log() -> void:
	if bm.battle_log.is_empty(): return
	var lines := "\n".join(bm.battle_log).split("\n")
	bm.battle_log.clear()
	for line in lines:
		if line.strip_edges().is_empty(): continue
		if "命中规则" in line:    _log_append("[color=#ffdd55]" + line + "[/color]")
		elif "⚔" in line:        _log_append("[color=#ffaa66]" + line + "[/color]")
		elif "环境" in line:     _log_append("[color=#88aaff]" + line + "[/color]")
		else:                    _log_append("[color=#cccccc]" + line + "[/color]")

# ══════════════════════════════════════════════════════════
# 工具
# ══════════════════════════════════════════════════════════
func _all_alive() -> Array:
	return _alive_in(bm.player_team) + _alive_in(bm.enemy_team)

func _alive_in(team: Array) -> Array:
	var r: Array = []
	for c in team:
		if (c as Character).is_alive(): r.append(c)
	return r
