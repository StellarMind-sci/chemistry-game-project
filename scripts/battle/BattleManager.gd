# BattleManager.gd
# 战斗管理器：实现完整的五阶段战斗回合循环
# 这是整个战斗系统的心脏：所有模块在这里汇聚、解算、输出结果
class_name BattleManager
extends RefCounted

var player:       Character
var enemy:        Character
var environment:  Environment
var reaction_db:  ReactionDatabase
var catalysts:    Array = []   # 当前战场上活动的催化剂

var turn_count: int = 0
var battle_log: Array = []    # 战斗记录，供 UI 读取

# ── 初始化 ───────────────────────────────────────────────

func setup(p_player: Character, p_enemy: Character, rules_path: String = "res://data/reactions/reaction_rules.json") -> void:
	player      = p_player
	enemy       = p_enemy
	environment = Environment.new()
	reaction_db = ReactionDatabase.new()
	var ok := reaction_db.load_from_file(rules_path)
	if not ok:
		push_warning("BattleManager：规则文件加载失败，将全部触发惰性反应")

# ── 完整回合入口 ─────────────────────────────────────────

# 运行一个完整回合。返回值：""=继续, "player"=玩家胜, "enemy"=敌方胜
func run_turn() -> String:
	turn_count += 1
	_log("\n══════════════════════════════════════")
	_log("  回合 %d" % turn_count)
	_log("  %-30s" % player.get_summary())
	_log("  %-30s" % enemy.get_summary())
	_log("══════════════════════════════════════")

	# 每回合开始：恢复能量
	player.restore_energy_per_turn()
	enemy.restore_energy_per_turn()

	phase_env_effects()
	var winner := phase_check_victory()
	if winner != "": return winner

	var actions := phase_action_selection()
	var result  := phase_resolution(actions)
	phase_apply(result)

	return phase_check_victory()

# 运行整场战斗（调试 / 原型阶段使用）
func run_battle(max_turns: int = 30) -> String:
	_log("⚗ 战斗开始：%s  vs  %s" % [player.char_name, enemy.char_name])
	_log("  %s" % environment.get_summary())

	while turn_count < max_turns:
		var winner := run_turn()
		if winner != "":
			_log("\n══ 战斗结束 ══")
			if winner == "player":
				_log("  玩家【%s】获胜" % player.char_name)
			else:
				_log("  敌人【%s】获胜" % enemy.char_name)
			return winner

	_log("\n══ 超出回合上限（%d），战斗平局 ══" % max_turns)
	return "draw"

# ════════════════════════════════════════════════════════════
# 阶段一：回合开始，环境效果生效
# ════════════════════════════════════════════════════════════
func phase_env_effects() -> void:
	_log("\n[阶段一] 环境效果生效")
	_log("  " + environment.get_summary())

	for char: Character in [player, enemy]:
		_apply_env_damage(char)
		char.tick_status_effects()

func _apply_env_damage(char: Character) -> void:
	# 高温（>80°C）对含羟基角色造成脱水损伤
	if environment.temperature > 80.0 and char.has_skill_with_tag(Skill.TAG_HYDROXYL):
		var dmg: float = (environment.temperature - 80.0) * 0.2
		char.take_damage(dmg)
		_log("  ⚡ [高温脱水] %s 受到 %.1f 点损伤" % [char.char_name, dmg])

	# 强酸（pH < 3）对含金属角色造成酸蚀
	if environment.pH < 3.0 and (char.has_skill_with_element("Fe") or char.has_skill_with_element("Cu") or char.has_skill_with_element("Zn")):
		var dmg: float = (3.0 - environment.pH) * 5.0
		char.take_damage(dmg)
		_log("  ⚡ [强酸酸蚀] %s 受到 %.1f 点损伤" % [char.char_name, dmg])

	# 混乱态（熵 > 70）所有角色受到小量混乱损伤
	if environment.is_chaos_state():
		var dmg: float = (environment.entropy - 70.0) * 0.1
		char.take_damage(dmg)
		_log("  ⚡ [混乱态] %s 受到 %.1f 点混乱损伤" % [char.char_name, dmg])

# ════════════════════════════════════════════════════════════
# 阶段二：行动选择（Demo 版：自动选第一个可负担技能）
# ════════════════════════════════════════════════════════════
func phase_action_selection() -> Dictionary:
	_log("\n[阶段二] 行动选择")
	var player_skill := _select_skill_auto(player)
	var enemy_skill  := _select_skill_auto(enemy)
	_log("  玩家：%s" % (player_skill.skill_name if player_skill else "（无法行动）"))
	_log("  敌人：%s" % (enemy_skill.skill_name  if enemy_skill  else "（无法行动）"))
	return {"player": player_skill, "enemy": enemy_skill}

func _select_skill_auto(char: Character) -> Skill:
	# Demo 阶段：轮流使用技能（用 turn_count 取模）
	var available: Array = []
	for skill: Skill in char.skills:
		if char.can_afford(skill.energy_cost):
			available.append(skill)
	if available.is_empty():
		return null
	return available[turn_count % available.size()]

# ════════════════════════════════════════════════════════════
# 阶段三：反应解算（战斗的核心）
# ════════════════════════════════════════════════════════════
func phase_resolution(actions: Dictionary) -> Dictionary:
	_log("\n[阶段三] 反应解算")
	var ps: Skill = actions.get("player")
	var es: Skill = actions.get("enemy")

	if ps == null or es == null:
		_log("  有角色无法行动，本回合跳过解算")
		return {}

	_log("  玩家技能标签：%s" % ps.get_tag_summary())
	_log("  敌人技能标签：%s" % es.get_tag_summary())

	return resolve_reaction(ps, es, environment, catalysts)

# 反应解算核心算法（可单独调用，供 AI 评估和预览 UI 使用）
func resolve_reaction(skill_a: Skill, skill_b: Skill,
		env: Environment, active_catalysts: Array) -> Dictionary:

	# 3a + 3b：提取标签，查最特异规则
	var matched_rule: ReactionRule = reaction_db.find_most_specific_match(skill_a, skill_b)

	if matched_rule == null:
		# 惰性反应：双方无化学相互作用，仅基础碰撞伤害
		_log("  → 惰性反应（无匹配规则）")
		return _create_inert_reaction(skill_a, skill_b)

	_log("  → 命中规则：【%s】 优先级=%d" % [matched_rule.rule_name, matched_rule.priority])

	# 3c：复制基础效果，应用催化剂修正
	var effect: Dictionary = matched_rule.base_effect.duplicate(true)
	for catalyst in active_catalysts:
		if catalyst.has_method("modify_effect"):
			effect = catalyst.modify_effect(effect, matched_rule)

	# 3d：应用环境修正（勒夏特列原理）
	var efficiency: float = calculate_environmental_efficiency(matched_rule, env)
	var base_dmg:   float = (skill_a.base_damage + skill_b.base_damage) * 0.5
	var final_dmg:  float = base_dmg * effect.get("damage_multiplier", 1.0) * efficiency

	_log("  效率系数=%.2f  基础伤害=%.1f  最终伤害=%.1f" % [efficiency, base_dmg, final_dmg])

	return {
		"damage":         final_dmg,
		"rule_name":      matched_rule.rule_name,
		"efficiency":     efficiency,
		"env_delta":      effect.get("env_delta",      {}),
		"status_effects": effect.get("status_effects", []),
	}

# 勒夏特列原理的数值化实现：把"体系自动抵抗外界扰动"变成可计算的乘数
func calculate_environmental_efficiency(rule: ReactionRule, env: Environment) -> float:
	var efficiency: float = 1.0

	# 温度对放热/吸热反应的非对称影响
	# 放热反应在高温下被压制（体系抵抗），吸热反应在高温下被加成
	if rule.is_exothermic():
		var T_excess: float = env.temperature - env.baseline_temperature
		efficiency *= (1.0 - rule.temperature_sensitivity * _sigmoid(T_excess / 30.0))

	if rule.is_endothermic():
		var T_excess: float = env.temperature - env.baseline_temperature
		# 高温加成吸热反应（体系试图通过吸热降温）
		efficiency *= (1.0 + rule.temperature_sensitivity * _sigmoid(T_excess / 30.0) * 0.5)

	# pH 偏离最适值的指数衰减
	# 偏离 1 单位可忍，偏离 3 单位几乎失效
	if rule.is_acid_base():
		efficiency *= exp(-abs(env.pH - rule.optimal_pH) * 0.3)

	# 熵对概率反应的扰动（高熵让方差变大，效率更不稳定）
	if rule.is_stochastic():
		var entropy_factor: float = 1.0 - env.entropy * 0.002
		efficiency *= max(0.3, entropy_factor)

	# 钳制在合理范围：不让任何单一配置把反应推到归零或无限增益
	return clamp(efficiency, 0.1, 2.0)

func _sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))

func _create_inert_reaction(skill_a: Skill, skill_b: Skill) -> Dictionary:
	return {
		"damage":         (skill_a.base_damage + skill_b.base_damage) * 0.3,
		"rule_name":      "惰性反应",
		"efficiency":     1.0,
		"env_delta":      {"entropy_delta": 2.0},   # 惰性碰撞轻微增熵
		"status_effects": [],
	}

# ════════════════════════════════════════════════════════════
# 阶段四：结果应用
# ════════════════════════════════════════════════════════════
func phase_apply(result: Dictionary) -> void:
	_log("\n[阶段四] 结果应用")
	if result.is_empty():
		return

	var damage: float = result.get("damage", 0.0)

	# 伤害应用（Demo：玩家技能打敌人，双方同回合但玩家先造成伤害）
	if damage > 0.0:
		enemy.take_damage(damage)
		_log("  %s 受到 %.1f 点伤害  HP → %.0f/%.0f" % [
			enemy.char_name, damage, enemy.hp, enemy.max_hp])

	# 环境变量聚合更新
	var env_delta: Dictionary = result.get("env_delta", {})
	if not env_delta.is_empty():
		var changes := environment.apply_delta(env_delta)
		if not changes.is_empty():
			_log("  [环境变化] " + "  ".join(changes))
		_log("  [环境当前] " + environment.get_summary())

	# 状态效果应用（Demo：打印状态名，不展开实现）
	for status in result.get("status_effects", []):
		_log("  [状态] %s 获得状态：%s" % [enemy.char_name, str(status)])

# ════════════════════════════════════════════════════════════
# 阶段五：胜负判定
# ════════════════════════════════════════════════════════════
func phase_check_victory() -> String:
	# 普通胜利条件：生命值归零
	if not enemy.is_alive():  return "player"
	if not player.is_alive(): return "enemy"
	return ""

# ── 日志 ─────────────────────────────────────────────────

func _log(msg: String) -> void:
	battle_log.append(msg)
	print(msg)

func get_battle_log() -> String:
	return "\n".join(battle_log)
