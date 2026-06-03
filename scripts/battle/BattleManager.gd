# BattleManager.gd
# 战斗管理器 v0.3 —— 多单位重构
# 核心变化：player/enemy → player_team/enemy_team（Array[Character]）
# 新增 ClashPair 碰撞配对描述，支持 N vs M 队伍对战
class_name BattleManager
extends RefCounted

# ══════════════════════════════════════════════════════════
# ClashPair：描述一次碰撞的完整信息
# ══════════════════════════════════════════════════════════
class ClashPair:
	var attacker:        Character
	var attacker_action
	var defender:        Character
	var defender_action
	var target_node: String = ""

	func _init(atk: Character, atk_act, def: Character, def_act,
			node: String = "") -> void:
		attacker        = atk
		attacker_action = atk_act
		defender        = def
		defender_action = def_act
		target_node     = node

	# P3：活化能越低越先解算
	func get_activation_cost() -> float:
		if attacker_action == null: return 999.0
		if attacker_action.has_method("get_activation_cost"):
			return attacker_action.get_activation_cost()
		return float(attacker_action.energy_cost.get("activation_energy", 10.0))

	# P2：先手关键字
	func has_first_strike() -> bool:
		if attacker_action == null: return false
		if attacker_action.has_method("is_priority_first"):
			return attacker_action.is_priority_first()
		if attacker_action.has_method("has_keyword"):
			return attacker_action.has_keyword("先手")
		return false

	func get_label() -> String:
		var atk_name: String = ""
		if attacker_action != null:
			if attacker_action.has_method("get_type_label"):
				atk_name = attacker_action.action_name
			elif "skill_name" in attacker_action:
				atk_name = attacker_action.skill_name
		return "  %s [%s] → %s" % [attacker.char_name, atk_name, defender.char_name]

# ══════════════════════════════════════════════════════════
# 字段
# ══════════════════════════════════════════════════════════
var player_team: Array = []
var enemy_team:  Array = []
var environment: BattleEnvironment
var reaction_db: ReactionDatabase
var catalysts:   Array = []
var turn_count:  int   = 0
var battle_log:  Array = []

# 向后兼容别名
var player: Character:
	get: return player_team[0] if not player_team.is_empty() else null
var enemy: Character:
	get: return enemy_team[0] if not enemy_team.is_empty() else null

# ══════════════════════════════════════════════════════════
# 初始化
# ══════════════════════════════════════════════════════════

func setup_teams(p_team: Array, e_team: Array,
		rules_path: String = "res://data/reactions/reaction_rules.json") -> void:
	player_team = p_team
	enemy_team  = e_team
	_init_battle(rules_path)

func setup(p_player: Character, p_enemy: Character,
		rules_path: String = "res://data/reactions/reaction_rules.json") -> void:
	player_team = [p_player]
	enemy_team  = [p_enemy]
	_init_battle(rules_path)

func _init_battle(rules_path: String) -> void:
	environment = BattleEnvironment.new()
	reaction_db = ReactionDatabase.new()
	if not reaction_db.load_from_file(rules_path):
		push_warning("BattleManager：规则文件加载失败")

# ══════════════════════════════════════════════════════════
# 回合循环
# ══════════════════════════════════════════════════════════

func run_turn() -> String:
	turn_count += 1
	_log("\n══════════════════════════════════════")
	_log("  回合 %d" % turn_count)
	for chara in _all_alive():
		_log("  " + (chara as Character).get_summary())
	_log("══════════════════════════════════════")
	for chara in _all_alive():
		(chara as Character).restore_energy_per_turn()
	phase_env_effects()
	var winner := phase_check_victory()
	if winner != "": return winner
	var clash_pairs := phase_action_selection()
	var results     := phase_resolution(clash_pairs)
	phase_apply(results)
	return phase_check_victory()

func run_battle(max_turns: int = 30) -> String:
	# 修正：避免 .map() 带类型化 lambda，改用普通循环
	var p_names: Array = []
	var e_names: Array = []
	for c in player_team: p_names.append((c as Character).char_name)
	for c in enemy_team:  e_names.append((c as Character).char_name)
	_log("⚗ 战斗开始")
	_log("  玩家队：[%s]" % ", ".join(p_names))
	_log("  敌方队：[%s]" % ", ".join(e_names))
	_log("  %s" % environment.get_summary())

	while turn_count < max_turns:
		var winner := run_turn()
		if winner != "":
			_log("\n══ 战斗结束 ══")
			_log("  胜利方：%s" % ("玩家队伍" if winner == "player" else "敌方队伍"))
			return winner
	_log("\n══ 超出回合上限（%d），平局 ══" % max_turns)
	return "draw"

# ══════════════════════════════════════════════════════════
# 阶段一：环境效果
# ══════════════════════════════════════════════════════════
func phase_env_effects() -> void:
	_log("\n[阶段一] 环境效果生效")
	_log("  " + environment.get_summary())
	for chara in _all_alive():
		_apply_env_damage(chara as Character)
		(chara as Character).tick_status_effects()

func _apply_env_damage(chara: Character) -> void:
	if environment.temperature > 80.0 and chara.has_skill_with_tag("hydroxyl"):
		var dmg: float = (environment.temperature - 80.0) * 0.2
		chara.take_damage(dmg)
		_log("  ⚡ [高温脱水] %s 受 %.1f" % [chara.char_name, dmg])
	if environment.pH < 3.0 and (chara.has_skill_with_element("Fe") or
			chara.has_skill_with_element("Cu") or chara.has_skill_with_element("Zn")):
		var dmg: float = (3.0 - environment.pH) * 5.0
		chara.take_damage(dmg)
		_log("  ⚡ [强酸酸蚀] %s 受 %.1f" % [chara.char_name, dmg])
	if environment.is_chaos_state():
		var dmg: float = (environment.entropy - 70.0) * 0.1
		chara.take_damage(dmg)
		_log("  ⚡ [混乱态] %s 受 %.1f" % [chara.char_name, dmg])

# ══════════════════════════════════════════════════════════
# 阶段二：行动选择 → Array[ClashPair]
# ══════════════════════════════════════════════════════════
func phase_action_selection() -> Array:
	_log("\n[阶段二] 行动选择")
	var action_map: Dictionary = {}
	for chara in _all_alive():
		var c := chara as Character
		var act = _pick_action(c)
		if act != null:
			action_map[c] = act
			var nm: String = act.action_name if act.has_method("get_type_label") \
				else act.get("skill_name", "?")
			_log("  %s 选择：%s" % [c.char_name, nm])
		else:
			_log("  %s：无可负担行动（Pass）" % c.char_name)

	var clash_pairs: Array = []
	for atk in _alive_in(player_team):
		var a := atk as Character
		if not action_map.has(a): continue
		var targets := _alive_in(enemy_team)
		if targets.is_empty(): break
		var def := targets[randi() % targets.size()] as Character
		clash_pairs.append(ClashPair.new(a, action_map[a], def, action_map.get(def)))
	for atk in _alive_in(enemy_team):
		var a := atk as Character
		if not action_map.has(a): continue
		var targets := _alive_in(player_team)
		if targets.is_empty(): break
		var def := targets[randi() % targets.size()] as Character
		clash_pairs.append(ClashPair.new(a, action_map[a], def, action_map.get(def)))

	# 修正：sort_custom 使用无类型 lambda 避免嵌套类型注解问题
	clash_pairs.sort_custom(func(a, b) -> bool:
		var ca := a as ClashPair
		var cb := b as ClashPair
		if ca.has_first_strike() and not cb.has_first_strike(): return true
		if cb.has_first_strike() and not ca.has_first_strike(): return false
		return ca.get_activation_cost() < cb.get_activation_cost()
	)
	_log("  共 %d 次碰撞，已按优先级排序" % clash_pairs.size())
	return clash_pairs

func _pick_action(chara: Character):
	if chara.standby.is_empty():
		chara.draw_to_standby()
	var affordable := chara.get_affordable_standby()
	if affordable.is_empty(): return null
	return affordable[0]

# ══════════════════════════════════════════════════════════
# 阶段三：逐对解算
# ══════════════════════════════════════════════════════════
func phase_resolution(clash_pairs: Array) -> Array:
	_log("\n[阶段三] 反应解算")
	var results: Array = []
	# 修正：for 循环不使用嵌套类类型注解
	for item in clash_pairs:
		var clash := item as ClashPair
		_log("\n" + clash.get_label())
		if clash.attacker_action == null or clash.defender_action == null:
			_log("    （一方无行动，跳过）")
			continue
		var attack  := resolve_reaction(clash.attacker_action, clash.defender_action,
										environment, catalysts)
		var counter := resolve_reaction(clash.defender_action, clash.attacker_action,
										environment, catalysts)
		clash.attacker.spend_energy(clash.attacker_action.energy_cost)
		clash.defender.spend_energy(clash.defender_action.energy_cost)
		clash.attacker.use_action_from_standby(clash.attacker_action)
		results.append({
			"attacker":       clash.attacker,
			"defender":       clash.defender,
			"attack_damage":  attack.get("damage",          0.0),
			"counter_damage": counter.get("damage",         0.0),
			"attack_rule":    attack.get("rule_name",        ""),
			"env_delta_atk":  attack.get("env_delta",        {}),
			"env_delta_def":  counter.get("env_delta",       {}),
			"status_to_def":  attack.get("status_effects",  []),
			"status_to_atk":  counter.get("status_effects", []),
		})
	return results

# ══════════════════════════════════════════════════════════
# 阶段四：结果应用
# ══════════════════════════════════════════════════════════
func phase_apply(results: Array) -> void:
	_log("\n[阶段四] 结果应用")
	if results.is_empty(): return
	var merged: Dictionary = {}
	for res in results:
		var atk: Character = res["attacker"]
		var def: Character = res["defender"]
		var a_dmg: float = float(res.get("attack_damage",  0.0))
		var d_dmg: float = float(res.get("counter_damage", 0.0))
		if a_dmg > 0.0:
			def.take_damage(a_dmg)
			_log("  ⚔ %s→%s  %.1f伤  HP%.0f/%.0f" % [
				atk.char_name, def.char_name, a_dmg, def.hp, def.max_hp])
		if d_dmg > 0.0:
			atk.take_damage(d_dmg)
			_log("  ⚔ %s↩%s  %.1f反  HP%.0f/%.0f" % [
				def.char_name, atk.char_name, d_dmg, atk.hp, atk.max_hp])
		_merge_env_delta(merged, res.get("env_delta_atk", {}))
		_merge_env_delta(merged, res.get("env_delta_def", {}))
	if not merged.is_empty():
		var changes: Array = environment.apply_delta(merged)
		if not changes.is_empty():
			_log("  [环境变化] " + "  ".join(changes))
		_log("  [环境当前] " + environment.get_summary())

func _merge_env_delta(base: Dictionary, extra: Dictionary) -> void:
	for key: String in extra:
		base[key] = base.get(key, 0.0) + float(extra[key])

# ══════════════════════════════════════════════════════════
# 阶段五：胜负判定
# ══════════════════════════════════════════════════════════
func phase_check_victory() -> String:
	if _alive_in(enemy_team).is_empty():  return "player"
	if _alive_in(player_team).is_empty(): return "enemy"
	return ""

# ══════════════════════════════════════════════════════════
# 反应解算核心（兼容 Skill / ReactionAction 鸭子类型）
# ══════════════════════════════════════════════════════════
func resolve_reaction(action_a, action_b,
		env: BattleEnvironment, active_catalysts: Array) -> Dictionary:
	var tags_a := _extract_tags(action_a)
	var tags_b := _extract_tags(action_b)
	var matched: ReactionRule = reaction_db.find_most_specific_match(
		_make_pseudo_skill(tags_a), _make_pseudo_skill(tags_b))
	if matched == null:
		_log("    → 惰性反应")
		return _inert_reaction(action_a, action_b)
	_log("    → 【%s】优先级=%d" % [matched.rule_name, matched.priority])
	var effect: Dictionary = matched.base_effect.duplicate(true)
	for catalyst in active_catalysts:
		if catalyst.has_method("modify_effect"):
			effect = catalyst.modify_effect(effect, matched)
	var eff:   float = calculate_environmental_efficiency(matched, env)
	var base:  float = (_get_intensity(action_a) + _get_intensity(action_b)) * 0.5
	var final: float = base * float(effect.get("damage_multiplier", 1.0)) * eff
	_log("    效率=%.2f 基础=%.1f 最终=%.1f" % [eff, base, final])
	return {
		"damage":         final,
		"rule_name":      matched.rule_name,
		"efficiency":     eff,
		"env_delta":      effect.get("env_delta",      {}),
		"status_effects": effect.get("status_effects", []),
	}

func calculate_environmental_efficiency(rule: ReactionRule,
		env: BattleEnvironment) -> float:
	var e: float = 1.0
	if rule.is_exothermic():
		var T: float = env.temperature - env.baseline_temperature
		e *= (1.0 - rule.temperature_sensitivity * _sigmoid(T / 30.0))
	if rule.is_endothermic():
		var T: float = env.temperature - env.baseline_temperature
		e *= (1.0 + rule.temperature_sensitivity * _sigmoid(T / 30.0) * 0.5)
	if rule.is_acid_base():
		e *= exp(-abs(env.pH - rule.optimal_pH) * 0.3)
	if rule.is_stochastic():
		e *= max(0.3, 1.0 - env.entropy * 0.002)
	return clamp(e, 0.1, 2.0)

func _sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))

# ══════════════════════════════════════════════════════════
# 辅助
# ══════════════════════════════════════════════════════════
func _all_alive() -> Array:
	return _alive_in(player_team) + _alive_in(enemy_team)

func _alive_in(team: Array) -> Array:
	var r: Array = []
	for c in team:
		if (c as Character).is_alive(): r.append(c)
	return r

func _extract_tags(action) -> Dictionary:
	if action == null: return {}
	# Object.get() 只接受1个参数，无法提供默认值，改用 in 判断后直接访问属性
	var elem: Array = action.element_tags if "element_tags" in action else []
	var chem: Array = action.chem_tags    if "chem_tags"    in action else []
	return {"element_tags": elem, "chem_tags": chem}

func _make_pseudo_skill(tags: Dictionary) -> Skill:
	var s := Skill.new("_pseudo")
	s.element_tags = tags.get("element_tags", [])
	s.chem_tags    = tags.get("chem_tags",    [])
	return s

func _get_intensity(action) -> float:
	if action == null: return 0.0
	if action.has_method("get_base_damage"):  return action.get_base_damage()
	if "base_intensity" in action:            return float(action.base_intensity)
	if "base_damage" in action:               return float(action.base_damage)
	return 10.0

func _inert_reaction(a, b) -> Dictionary:
	return {
		"damage":         (_get_intensity(a) + _get_intensity(b)) * 0.3,
		"rule_name":      "惰性反应",
		"efficiency":     1.0,
		"env_delta":      {"entropy_delta": 2.0},
		"status_effects": [],
	}

func _log(msg: String) -> void:
	battle_log.append(msg)
	print(msg)

func get_battle_log() -> String:
	return "\n".join(battle_log)
