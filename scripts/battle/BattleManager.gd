# BattleManager.gd
# 战斗管理器 v0.3 —— 多单位重构
# 核心变化：player/enemy → player_team/enemy_team（Array[Character]）
# 新增 ClashPair 碰撞配对描述，支持 N vs M 队伍对战
class_name BattleManager
extends RefCounted

# ══════════════════════════════════════════════════════════
# ClashPair：描述一次碰撞的完整信息
# 攻击方用某个行动 → 防御方用某个行动（双向解算）
# ══════════════════════════════════════════════════════════
class ClashPair:
	var attacker:        Character
	var attacker_action              # ReactionAction 或 Skill（鸭子类型）
	var defender:        Character
	var defender_action              # ReactionAction 或 Skill
	var target_node:     String = "" # 攻击目标的结构节点ID（""=不指定）

	func _init(atk: Character, atk_act, def: Character, def_act,
			node: String = "") -> void:
		attacker        = atk
		attacker_action = atk_act
		defender        = def
		defender_action = def_act
		target_node     = node

	# P3 解算顺序：活化能消耗（越低越先）
	func get_activation_cost() -> float:
		if attacker_action == null: return 999.0
		if attacker_action.has_method("get_activation_cost"):
			return attacker_action.get_activation_cost()
		return float(attacker_action.energy_cost.get("activation_energy", 10.0))

	# P2 解算顺序：先手关键字
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
			else:
				atk_name = attacker_action.get("skill_name", "?")
		return "  %s [%s] → %s" % [attacker.char_name, atk_name, defender.char_name]

# ══════════════════════════════════════════════════════════
# 字段
# ══════════════════════════════════════════════════════════
var player_team:  Array = []   # Array[Character]，玩家队伍
var enemy_team:   Array = []   # Array[Character]，敌方队伍
var environment:  BattleEnvironment
var reaction_db:  ReactionDatabase
var catalysts:    Array = []

var turn_count:  int  = 0
var battle_log:  Array = []

# 向后兼容别名（旧 TestBattle.gd 里的 battle.player / battle.enemy）
var player: Character:
	get: return player_team[0] if not player_team.is_empty() else null
var enemy: Character:
	get: return enemy_team[0] if not enemy_team.is_empty() else null

# ══════════════════════════════════════════════════════════
# 初始化
# ══════════════════════════════════════════════════════════

# 多单位：直接传入两个队伍数组
func setup_teams(p_team: Array, e_team: Array,
		rules_path: String = "res://data/reactions/reaction_rules.json") -> void:
	player_team = p_team
	enemy_team  = e_team
	_init_battle(rules_path)

# 单角色向后兼容：旧代码继续工作
func setup(p_player: Character, p_enemy: Character,
		rules_path: String = "res://data/reactions/reaction_rules.json") -> void:
	player_team = [p_player]
	enemy_team  = [p_enemy]
	_init_battle(rules_path)

func _init_battle(rules_path: String) -> void:
	environment = BattleEnvironment.new()
	reaction_db = ReactionDatabase.new()
	var ok := reaction_db.load_from_file(rules_path)
	if not ok:
		push_warning("BattleManager：规则文件加载失败，将全部触发惰性反应")

# ══════════════════════════════════════════════════════════
# 回合循环
# ══════════════════════════════════════════════════════════

func run_turn() -> String:
	turn_count += 1
	_log("\n══════════════════════════════════════")
	_log("  回合 %d" % turn_count)
	for chara: Character in _all_alive():
		_log("  %-35s" % chara.get_summary())
	_log("══════════════════════════════════════")

	# 所有存活角色恢复能量
	for chara: Character in _all_alive():
		chara.restore_energy_per_turn()

	phase_env_effects()
	var winner := phase_check_victory()
	if winner != "": return winner

	var clash_pairs: Array = phase_action_selection()
	var results:     Array = phase_resolution(clash_pairs)
	phase_apply(results)

	return phase_check_victory()

func run_battle(max_turns: int = 30) -> String:
	var team_names := ", ".join(player_team.map(func(c: Character) -> String: return c.char_name))
	var enemy_names := ", ".join(enemy_team.map(func(c: Character) -> String: return c.char_name))
	_log("⚗ 战斗开始")
	_log("  玩家队：[%s]" % team_names)
	_log("  敌方队：[%s]" % enemy_names)
	_log("  %s" % environment.get_summary())

	while turn_count < max_turns:
		var winner := run_turn()
		if winner != "":
			_log("\n══ 战斗结束 ══")
			_log("  胜利方：%s" % ("玩家队伍" if winner == "player" else "敌方队伍"))
			return winner

	_log("\n══ 超出回合上限（%d），战斗平局 ══" % max_turns)
	return "draw"

# ══════════════════════════════════════════════════════════
# 阶段一：环境效果生效（作用于所有存活角色）
# ══════════════════════════════════════════════════════════
func phase_env_effects() -> void:
	_log("\n[阶段一] 环境效果生效")
	_log("  " + environment.get_summary())
	for chara: Character in _all_alive():
		_apply_env_damage(chara)
		chara.tick_status_effects()

func _apply_env_damage(chara: Character) -> void:
	if environment.temperature > 80.0 and chara.has_skill_with_tag("hydroxyl"):
		var dmg: float = (environment.temperature - 80.0) * 0.2
		chara.take_damage(dmg)
		_log("  ⚡ [高温脱水] %s 受 %.1f 损伤" % [chara.char_name, dmg])

	if environment.pH < 3.0 and (chara.has_skill_with_element("Fe") or
			chara.has_skill_with_element("Cu") or chara.has_skill_with_element("Zn")):
		var dmg: float = (3.0 - environment.pH) * 5.0
		chara.take_damage(dmg)
		_log("  ⚡ [强酸酸蚀] %s 受 %.1f 损伤" % [chara.char_name, dmg])

	if environment.is_chaos_state():
		var dmg: float = (environment.entropy - 70.0) * 0.1
		chara.take_damage(dmg)
		_log("  ⚡ [混乱态] %s 受 %.1f 损伤" % [chara.char_name, dmg])

# ══════════════════════════════════════════════════════════
# 阶段二：行动选择 → 返回 Array[ClashPair]
# Demo 阶段：AI 自动分配（玩家/敌方各打随机存活对手）
# ══════════════════════════════════════════════════════════
func phase_action_selection() -> Array:
	_log("\n[阶段二] 行动选择")

	# Step 1：每个存活角色各自选出本回合行动
	var action_map: Dictionary = {}   # Character → action
	for chara: Character in _all_alive():
		var act = _pick_action(chara)
		if act != null:
			action_map[chara] = act
			var act_name: String = act.action_name if act.has_method("get_type_label") \
				else act.get("skill_name", "?")
			_log("  %s 选择：%s" % [chara.char_name, act_name])
		else:
			_log("  %s：无可负担行动（Pass）" % chara.char_name)

	# Step 2：分配攻击目标并创建 ClashPair
	var clash_pairs: Array = []

	# 玩家队每个角色打一个随机存活敌人
	for atk: Character in _alive_in(player_team):
		if not action_map.has(atk): continue
		var targets := _alive_in(enemy_team)
		if targets.is_empty(): break
		var def: Character = targets[randi() % targets.size()]
		var def_act = action_map.get(def)   # 防御方本回合的行动（可能为null）
		clash_pairs.append(ClashPair.new(atk, action_map[atk], def, def_act))

	# 敌方队每个角色打一个随机存活玩家
	for atk: Character in _alive_in(enemy_team):
		if not action_map.has(atk): continue
		var targets := _alive_in(player_team)
		if targets.is_empty(): break
		var def: Character = targets[randi() % targets.size()]
		var def_act = action_map.get(def)
		clash_pairs.append(ClashPair.new(atk, action_map[atk], def, def_act))

	# Step 3：按解算优先级排序（P2 先手 > P3 活化能低者优先）
	clash_pairs.sort_custom(func(a: ClashPair, b: ClashPair) -> bool:
		if a.has_first_strike() and not b.has_first_strike(): return true
		if b.has_first_strike() and not a.has_first_strike(): return false
		return a.get_activation_cost() < b.get_activation_cost()
	)

	_log("  共 %d 次碰撞，已按优先级排序" % clash_pairs.size())
	return clash_pairs

# Demo 版行动选择：优先从待机区取，待机区空则从行为谱抽取
func _pick_action(chara: Character):
	# 待机区没牌则先抽
	if chara.standby.is_empty():
		chara.draw_to_standby()
	# 从待机区取第一个可负担的行动
	var affordable := chara.get_affordable_standby()
	if affordable.is_empty():
		return null
	return affordable[0]

# ══════════════════════════════════════════════════════════
# 阶段三：逐对解算 → 返回 Array[Dictionary]
# ══════════════════════════════════════════════════════════
func phase_resolution(clash_pairs: Array) -> Array:
	_log("\n[阶段三] 反应解算")
	var results: Array = []

	for clash: ClashPair in clash_pairs:
		_log("\n  " + clash.get_label())
		if clash.attacker_action == null or clash.defender_action == null:
			_log("    （一方无行动，跳过）")
			continue

		# 正向：攻击方打防御方
		var attack  := resolve_reaction(clash.attacker_action, clash.defender_action,
										environment, catalysts)
		# 反向：防御方反击攻击方
		var counter := resolve_reaction(clash.defender_action, clash.attacker_action,
										environment, catalysts)

		# 消耗双方能量
		clash.attacker.spend_energy(clash.attacker_action.energy_cost)
		if clash.defender_action != null:
			clash.defender.spend_energy(clash.defender_action.energy_cost)

		# 将行动移入沉淀区
		clash.attacker.use_action_from_standby(clash.attacker_action)

		results.append({
			"attacker":      clash.attacker,
			"defender":      clash.defender,
			"attack_damage": attack.get("damage",   0.0),
			"counter_damage":counter.get("damage",  0.0),
			"attack_rule":   attack.get("rule_name", ""),
			"env_delta_atk": attack.get("env_delta",  {}),
			"env_delta_def": counter.get("env_delta", {}),
			"status_to_def": attack.get("status_effects", []),
			"status_to_atk": counter.get("status_effects",[]),
		})

	return results

# ══════════════════════════════════════════════════════════
# 阶段四：结果应用（逐条处理，环境扰动聚合）
# ══════════════════════════════════════════════════════════
func phase_apply(results: Array) -> void:
	_log("\n[阶段四] 结果应用")
	if results.is_empty():
		return

	var merged_delta: Dictionary = {}

	for res: Dictionary in results:
		var atk: Character = res["attacker"]
		var def: Character = res["defender"]

		var atk_dmg: float = res.get("attack_damage",  0.0)
		var def_dmg: float = res.get("counter_damage", 0.0)

		if atk_dmg > 0.0:
			def.take_damage(atk_dmg)
			_log("  ⚔ %s → %s  %.1f 伤害  HP %.0f/%.0f" % [
				atk.char_name, def.char_name, atk_dmg, def.hp, def.max_hp])

		if def_dmg > 0.0:
			atk.take_damage(def_dmg)
			_log("  ⚔ %s ↩ %s  %.1f 反伤  HP %.0f/%.0f" % [
				def.char_name, atk.char_name, def_dmg, atk.hp, atk.max_hp])

		# 聚合环境扰动
		_merge_env_delta(merged_delta, res.get("env_delta_atk", {}))
		_merge_env_delta(merged_delta, res.get("env_delta_def", {}))

	# 统一更新环境（一回合内所有反应的副产品合并写入）
	if not merged_delta.is_empty():
		var changes: Array = environment.apply_delta(merged_delta)
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
	var player_alive := _alive_in(player_team)
	var enemy_alive  := _alive_in(enemy_team)
	if enemy_alive.is_empty():  return "player"
	if player_alive.is_empty(): return "enemy"
	return ""

# ══════════════════════════════════════════════════════════
# 反应解算核心（与 v0.2 完全一致，鸭子类型兼容 Skill/ReactionAction）
# ══════════════════════════════════════════════════════════
func resolve_reaction(action_a, action_b, env: BattleEnvironment,
		active_catalysts: Array) -> Dictionary:

	# 提取标签（同时兼容 Skill 和 ReactionAction）
	var tags_a := _extract_tags(action_a)
	var tags_b := _extract_tags(action_b)

	var matched_rule: ReactionRule = reaction_db.find_most_specific_match(
		_make_pseudo_skill(tags_a), _make_pseudo_skill(tags_b))

	if matched_rule == null:
		_log("    → 惰性反应")
		return _inert_reaction(action_a, action_b)

	var rule_name: String = matched_rule.rule_name
	var eq: String = matched_rule.base_effect.get("equation_display", "")
	_log("    → 【%s】优先级=%d" % [rule_name, matched_rule.priority])

	var effect: Dictionary = matched_rule.base_effect.duplicate(true)
	for catalyst in active_catalysts:
		if catalyst.has_method("modify_effect"):
			effect = catalyst.modify_effect(effect, matched_rule)

	var efficiency: float = calculate_environmental_efficiency(matched_rule, env)
	var base_dmg:   float = (_get_intensity(action_a) + _get_intensity(action_b)) * 0.5
	var final_dmg:  float = base_dmg * float(effect.get("damage_multiplier", 1.0)) * efficiency
	_log("    效率=%.2f  强度=%.1f  最终=%.1f" % [efficiency, base_dmg, final_dmg])

	return {
		"damage":         final_dmg,
		"rule_name":      rule_name,
		"efficiency":     efficiency,
		"env_delta":      effect.get("env_delta",      {}),
		"status_effects": effect.get("status_effects", []),
	}

# 勒夏特列原理
func calculate_environmental_efficiency(rule: ReactionRule,
		env: BattleEnvironment) -> float:
	var eff: float = 1.0
	if rule.is_exothermic():
		var T := env.temperature - env.baseline_temperature
		eff *= (1.0 - rule.temperature_sensitivity * _sigmoid(T / 30.0))
	if rule.is_endothermic():
		var T := env.temperature - env.baseline_temperature
		eff *= (1.0 + rule.temperature_sensitivity * _sigmoid(T / 30.0) * 0.5)
	if rule.is_acid_base():
		eff *= exp(-abs(env.pH - rule.optimal_pH) * 0.3)
	if rule.is_stochastic():
		eff *= max(0.3, 1.0 - env.entropy * 0.002)
	return clamp(eff, 0.1, 2.0)

func _sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))

# ══════════════════════════════════════════════════════════
# 辅助工具
# ══════════════════════════════════════════════════════════

func _all_alive() -> Array:
	return _alive_in(player_team) + _alive_in(enemy_team)

func _alive_in(team: Array) -> Array:
	var result: Array = []
	for chara: Character in team:
		if chara.is_alive():
			result.append(chara)
	return result

# 从 Skill 或 ReactionAction 提取标签字典
func _extract_tags(action) -> Dictionary:
	if action == null: return {}
	return {
		"element_tags": action.get("element_tags", []),
		"chem_tags":    action.get("chem_tags",    []),
	}

# 构造临时 Skill 用于 ReactionDatabase 的标签匹配
func _make_pseudo_skill(tags: Dictionary) -> Skill:
	var s := Skill.new("_pseudo")
	s.element_tags = tags.get("element_tags", [])
	s.chem_tags    = tags.get("chem_tags",    [])
	return s

# 从行动对象提取强度（兼容 base_damage 和 base_intensity）
func _get_intensity(action) -> float:
	if action == null: return 0.0
	if action.has_method("get_base_damage"):
		return action.get_base_damage()
	if "base_intensity" in action:
		return float(action.base_intensity)
	return float(action.get("base_damage", 10.0))

func _inert_reaction(action_a, action_b) -> Dictionary:
	return {
		"damage":         (_get_intensity(action_a) + _get_intensity(action_b)) * 0.3,
		"rule_name":      "惰性反应",
		"efficiency":     1.0,
		"env_delta":      {"entropy_delta": 2.0},
		"status_effects": [],
	}

# ══════════════════════════════════════════════════════════
# 日志
# ══════════════════════════════════════════════════════════
func _log(msg: String) -> void:
	battle_log.append(msg)
	print(msg)

func get_battle_log() -> String:
	return "\n".join(battle_log)
