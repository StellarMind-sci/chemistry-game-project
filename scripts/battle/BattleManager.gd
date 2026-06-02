# BattleManager.gd
# 战斗管理器：实现完整的五阶段战斗回合循环
# v0.2：对称伤害解算——双方技能两两碰撞，各自受到伤害
class_name BattleManager
extends RefCounted

var player:       Character
var enemy:        Character
var environment:  BattleEnvironment
var reaction_db:  ReactionDatabase
var catalysts:    Array = []

var turn_count: int = 0
var battle_log: Array = []

# ── 初始化 ───────────────────────────────────────────────

func setup(p_player: Character, p_enemy: Character, rules_path: String = "res://data/reactions/reaction_rules.json") -> void:
	player      = p_player
	enemy       = p_enemy
	environment = BattleEnvironment.new()
	reaction_db = ReactionDatabase.new()
	var ok := reaction_db.load_from_file(rules_path)
	if not ok:
		push_warning("BattleManager：规则文件加载失败，将全部触发惰性反应")

# ── 完整回合入口 ─────────────────────────────────────────

func run_turn() -> String:
	turn_count += 1
	_log("\n══════════════════════════════════════")
	_log("  回合 %d" % turn_count)
	_log("  %-30s" % player.get_summary())
	_log("  %-30s" % enemy.get_summary())
	_log("══════════════════════════════════════")

	player.restore_energy_per_turn()
	enemy.restore_energy_per_turn()

	phase_env_effects()
	var winner := phase_check_victory()
	if winner != "": return winner

	var actions := phase_action_selection()
	var result  := phase_resolution(actions)
	phase_apply(result)

	return phase_check_victory()

func run_battle(max_turns: int = 30) -> String:
	_log("⚗ 战斗开始：%s  vs  %s" % [player.char_name, enemy.char_name])
	_log("  %s" % environment.get_summary())

	while turn_count < max_turns:
		var winner := run_turn()
		if winner != "":
			_log("\n══ 战斗结束 ══")
			if winner == "player":
				_log("  玩家【%s】获胜！" % player.char_name)
			else:
				_log("  敌人【%s】获胜！" % enemy.char_name)
			return winner

	_log("\n══ 超出回合上限（%d），战斗平局 ══" % max_turns)
	return "draw"

# ════════════════════════════════════════════════════════════
# 阶段一：环境效果生效
# ════════════════════════════════════════════════════════════
func phase_env_effects() -> void:
	_log("\n[阶段一] 环境效果生效")
	_log("  " + environment.get_summary())

	# 修正：变量名改为 chara，避免与内置 char() 函数冲突
	for chara: Character in [player, enemy]:
		_apply_env_damage(chara)
		chara.tick_status_effects()

func _apply_env_damage(chara: Character) -> void:
	# 高温（>80°C）对含羟基角色造成脱水损伤
	if environment.temperature > 80.0 and chara.has_skill_with_tag(Skill.TAG_HYDROXYL):
		var dmg: float = (environment.temperature - 80.0) * 0.2
		chara.take_damage(dmg)
		_log("  ⚡ [高温脱水] %s 受到 %.1f 点损伤" % [chara.char_name, dmg])

	# 强酸（pH < 3）对含金属角色造成酸蚀
	if environment.pH < 3.0 and (chara.has_skill_with_element("Fe") or chara.has_skill_with_element("Cu") or chara.has_skill_with_element("Zn")):
		var dmg: float = (3.0 - environment.pH) * 5.0
		chara.take_damage(dmg)
		_log("  ⚡ [强酸酸蚀] %s 受到 %.1f 点损伤" % [chara.char_name, dmg])

	# 混乱态（熵 > 70）所有角色受到混乱损伤
	if environment.is_chaos_state():
		var dmg: float = (environment.entropy - 70.0) * 0.1
		chara.take_damage(dmg)
		_log("  ⚡ [混乱态] %s 受到 %.1f 点混乱损伤" % [chara.char_name, dmg])

# ════════════════════════════════════════════════════════════
# 阶段二：行动选择
# ════════════════════════════════════════════════════════════
func phase_action_selection() -> Dictionary:
	_log("\n[阶段二] 行动选择")
	var player_skill := _select_skill_auto(player)
	var enemy_skill  := _select_skill_auto(enemy)
	_log("  玩家：%s" % (player_skill.skill_name if player_skill else "（无法行动）"))
	_log("  敌人：%s" % (enemy_skill.skill_name  if enemy_skill  else "（无法行动）"))
	return {"player": player_skill, "enemy": enemy_skill}

# 修正：参数名改为 chara 避免与内置 char() 冲突
func _select_skill_auto(chara: Character) -> Skill:
	var available: Array = []
	for skill: Skill in chara.skills:
		if chara.can_afford(skill.energy_cost):
			available.append(skill)
	if available.is_empty():
		return null
	return available[turn_count % available.size()]

# ════════════════════════════════════════════════════════════
# 阶段三：反应解算（v0.2 对称双向）
# ════════════════════════════════════════════════════════════
func phase_resolution(actions: Dictionary) -> Dictionary:
	_log("\n[阶段三] 反应解算")
	var ps: Skill = actions.get("player")
	var es: Skill = actions.get("enemy")

	if ps == null or es == null:
		_log("  有角色无法行动，本回合跳过解算")
		return {}

	_log("  玩家出招：%s" % ps.get_tag_summary())
	_log("  敌人出招：%s" % es.get_tag_summary())

	_log("  ── 正向碰撞（玩家 → 敌人）")
	var attack: Dictionary = resolve_reaction(ps, es, environment, catalysts)

	_log("  ── 反向碰撞（敌人 → 玩家）")
	var counter: Dictionary = resolve_reaction(es, ps, environment, catalysts)

	player.spend_energy(ps.energy_cost)
	enemy.spend_energy(es.energy_cost)

	return {"attack": attack, "counter": counter}

func resolve_reaction(skill_a: Skill, skill_b: Skill,
		env: BattleEnvironment, active_catalysts: Array) -> Dictionary:

	var matched_rule: ReactionRule = reaction_db.find_most_specific_match(skill_a, skill_b)

	if matched_rule == null:
		_log("    → 惰性反应（无匹配规则）")
		return _create_inert_reaction(skill_a, skill_b)

	_log("    → 命中规则：【%s】 优先级=%d" % [matched_rule.rule_name, matched_rule.priority])

	var effect: Dictionary = matched_rule.base_effect.duplicate(true)
	for catalyst in active_catalysts:
		if catalyst.has_method("modify_effect"):
			effect = catalyst.modify_effect(effect, matched_rule)

	var efficiency: float = calculate_environmental_efficiency(matched_rule, env)
	var base_dmg:   float = (skill_a.base_damage + skill_b.base_damage) * 0.5
	var final_dmg:  float = base_dmg * effect.get("damage_multiplier", 1.0) * efficiency

	_log("    效率=%.2f  基础伤害=%.1f  最终伤害=%.1f" % [efficiency, base_dmg, final_dmg])

	return {
		"damage":         final_dmg,
		"rule_name":      matched_rule.rule_name,
		"efficiency":     efficiency,
		"env_delta":      effect.get("env_delta",      {}),
		"status_effects": effect.get("status_effects", []),
	}

# ════════════════════════════════════════════════════════════
# 阶段四：结果应用
# ════════════════════════════════════════════════════════════
func phase_apply(result: Dictionary) -> void:
	_log("\n[阶段四] 结果应用")
	if result.is_empty():
		return

	var attack:  Dictionary = result.get("attack",  {})
	var counter: Dictionary = result.get("counter", {})

	if not attack.is_empty():
		var dmg: float = attack.get("damage", 0.0)
		if dmg > 0.0:
			enemy.take_damage(dmg)
			_log("  ⚔ [玩家→敌人] %s 受到 %.1f 伤害  HP %.0f/%.0f" % [
				enemy.char_name, dmg, enemy.hp, enemy.max_hp])

	if not counter.is_empty():
		var dmg: float = counter.get("damage", 0.0)
		if dmg > 0.0:
			player.take_damage(dmg)
			_log("  ⚔ [敌人→玩家] %s 受到 %.1f 伤害  HP %.0f/%.0f" % [
				player.char_name, dmg, player.hp, player.max_hp])

	var merged_delta: Dictionary = {}
	_merge_env_delta(merged_delta, attack.get("env_delta",  {}))
	_merge_env_delta(merged_delta, counter.get("env_delta", {}))

	if not merged_delta.is_empty():
		var changes: Array = environment.apply_delta(merged_delta)
		if not changes.is_empty():
			_log("  [环境变化] " + "  ".join(changes))
		_log("  [环境当前] " + environment.get_summary())

	for status in attack.get("status_effects",  []):
		_log("  [状态→敌人] %s" % str(status))
	for status in counter.get("status_effects", []):
		_log("  [状态→玩家] %s" % str(status))

func _merge_env_delta(base: Dictionary, extra: Dictionary) -> void:
	for key: String in extra:
		base[key] = base.get(key, 0.0) + float(extra[key])

# ════════════════════════════════════════════════════════════
# 阶段五：胜负判定
# ════════════════════════════════════════════════════════════
func phase_check_victory() -> String:
	if not enemy.is_alive():  return "player"
	if not player.is_alive(): return "enemy"
	return ""

# ── 勒夏特列：环境效率计算 ──────────────────────────────

func calculate_environmental_efficiency(rule: ReactionRule, env: BattleEnvironment) -> float:
	var efficiency: float = 1.0

	if rule.is_exothermic():
		var T_excess: float = env.temperature - env.baseline_temperature
		efficiency *= (1.0 - rule.temperature_sensitivity * _sigmoid(T_excess / 30.0))

	if rule.is_endothermic():
		var T_excess: float = env.temperature - env.baseline_temperature
		efficiency *= (1.0 + rule.temperature_sensitivity * _sigmoid(T_excess / 30.0) * 0.5)

	if rule.is_acid_base():
		efficiency *= exp(-abs(env.pH - rule.optimal_pH) * 0.3)

	if rule.is_stochastic():
		var entropy_factor: float = 1.0 - env.entropy * 0.002
		efficiency *= max(0.3, entropy_factor)

	return clamp(efficiency, 0.1, 2.0)

func _sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))

func _create_inert_reaction(skill_a: Skill, skill_b: Skill) -> Dictionary:
	return {
		"damage":         (skill_a.base_damage + skill_b.base_damage) * 0.3,
		"rule_name":      "惰性反应",
		"efficiency":     1.0,
		"env_delta":      {"entropy_delta": 2.0},
		"status_effects": [],
	}

# ── 日志 ─────────────────────────────────────────────────

func _log(msg: String) -> void:
	battle_log.append(msg)
	print(msg)

func get_battle_log() -> String:
	return "\n".join(battle_log)
