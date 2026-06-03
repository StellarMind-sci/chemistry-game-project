# TestReactionAction.gd
# 验证脚本：测试 ReactionAction 数据结构 + 与推演引擎联动
# 使用方法：挂到 Node 节点，按 F6 运行当前场景
extends Node

func _ready() -> void:
	print("\n╔══════════════════════════════════════════╗")
	print("║   反应行动系统 · 验证测试                ║")
	print("╚══════════════════════════════════════════╝\n")
	_run_tests()

func _run_tests() -> void:
	# ── 准备推演引擎 ─────────────────────────────────────
	var engine := ReactionInference.new()
	if not engine.load_databases(
		"res://data/substances/substance_registry.json",
		"res://data/reactions/reaction_rules.json"):
		print("❌ 推演引擎加载失败")
		return

	# ══════════════════════════════════════════════════════
	# 测试一：从物质档案构造攻势型反应行动
	# ══════════════════════════════════════════════════════
	print("═══ 测试一：攻势型反应行动（自动从物质档案填充）═══\n")

	for sub_id in ["HCl", "Na", "KMnO4", "C2H5OH", "C6H12O6", "Glycine"]:
		var ra := ReactionAction.from_substance(engine, sub_id, ReactionAction.TYPE_STRIKE)
		print("  %s" % ra.get_summary())
		print("    占攻击箭头：%s" % str(ra.uses_attack_arrow()))
		print("    酸性=%s  碱性=%s  氧化性=%s  还原性=%s" % [
			str(ra.is_acidic()), str(ra.is_alkaline()),
			str(ra.is_oxidizing()), str(ra.is_reducing())
		])
		print("")

	# ══════════════════════════════════════════════════════
	# 测试二：构造调控-场地型反应行动
	# ══════════════════════════════════════════════════════
	print("═══ 测试二：调控-场地型反应行动 ═══\n")

	var heating := ReactionAction.make_field_intervention(
		"升温催化", {"temp_delta": 20.0}, 3)
	print("  %s" % heating.get_summary())
	print("    持续 %d 回合 | 占箭头：%s | 环境扰动：%s" % [
		heating.persist_turns, str(heating.uses_attack_arrow()),
		str(heating.environment_change)])

	var alkalize := ReactionAction.make_field_intervention(
		"碱化处理", {"pH_delta": 2.5}, 2)
	print("\n  %s" % alkalize.get_summary())
	print("    持续 %d 回合 | 占箭头：%s | 环境扰动：%s" % [
		alkalize.persist_turns, str(alkalize.uses_attack_arrow()),
		str(alkalize.environment_change)])

	# ══════════════════════════════════════════════════════
	# 测试三：构造调控-定向型反应行动
	# ══════════════════════════════════════════════════════
	print("\n═══ 测试三：调控-定向型反应行动 ═══\n")

	var protonate := ReactionAction.make_directed_intervention(
		"质子化处理", "NH2_group", "protonated")
	protonate.energy_cost = {ReactionAction.ENERGY_ACTIVATION: 15.0}
	protonate.prerequisite = "目标含有氨基"
	protonate.description  = "向对手的氨基注入质子，将其转化为铵盐形态"
	print("  %s" % protonate.get_summary())
	print("    目标节点：%s  状态变化：%s" % [
		protonate.target_node, protonate.target_state_change])
	print("    前置条件：%s" % protonate.prerequisite)

	# ══════════════════════════════════════════════════════
	# 测试四：反应行动直接接入推演引擎（模拟战斗碰撞）
	# ══════════════════════════════════════════════════════
	print("\n═══ 测试四：反应行动碰撞 → 推演引擎 ═══\n")

	var attacker := ReactionAction.from_substance(engine, "HCl", ReactionAction.TYPE_STRIKE)
	var defender := ReactionAction.from_substance(engine, "NaOH", ReactionAction.TYPE_STRIKE)

	print("  攻击方：%s  %s" % [attacker.action_name, attacker.get_tag_summary()])
	print("  防御方：%s  %s" % [defender.action_name, defender.get_tag_summary()])

	# 用 infer_from_tags 接口推演
	var result: ReactionInference.InferenceResult = engine.infer_from_tags(
		{"element_tags": attacker.element_tags, "chem_tags": attacker.chem_tags},
		{"element_tags": defender.element_tags, "chem_tags": defender.chem_tags}
	)

	if result.matched:
		print("\n  ✅ 命中规则：%s" % result.rule_name)
		print("  方程式：%s" % result.equation)
		print("  游戏效果：%s" % str(result.game_effects))
	else:
		print("\n  ⚪ 未匹配规则")

	# ══════════════════════════════════════════════════════
	# 测试五：解算顺序辅助（五级优先）
	# ══════════════════════════════════════════════════════
	print("\n═══ 测试五：解算顺序属性 ═══\n")

	var quick_action := ReactionAction.from_substance(engine, "HCl")
	quick_action.energy_cost = {ReactionAction.ENERGY_ACTIVATION: 8.0}
	quick_action.keywords    = ["先手"]

	var slow_action := ReactionAction.from_substance(engine, "Na")
	slow_action.energy_cost  = {ReactionAction.ENERGY_ACTIVATION: 30.0}

	var actions := [quick_action, slow_action]
	print("  原顺序：")
	for a: ReactionAction in actions:
		print("    %-8s 活化能=%.0f  先手=%s" % [
			a.action_name, a.get_activation_cost(),
			str(a.is_priority_first())])

	# 按 P2（先手优先）+ P3（活化能升序）排序
	actions.sort_custom(func(a: ReactionAction, b: ReactionAction) -> bool:
		# P2：先手优先
		if a.is_priority_first() and not b.is_priority_first():
			return true
		if b.is_priority_first() and not a.is_priority_first():
			return false
		# P3：活化能低者优先
		return a.get_activation_cost() < b.get_activation_cost()
	)

	print("\n  按 P2 + P3 排序后：")
	for a: ReactionAction in actions:
		print("    %-8s 活化能=%.0f  先手=%s" % [
			a.action_name, a.get_activation_cost(),
			str(a.is_priority_first())])

	print("\n✅ 所有测试完成")
