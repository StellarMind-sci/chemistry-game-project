# TestCharacterSpectrum.gd
# 验证脚本：测试 Character v0.3 的行为谱三区系统
# 挂到 Node 节点后按 F6 运行
extends Node

func _ready() -> void:
	print("\n╔══════════════════════════════════════════╗")
	print("║   行为谱系统 · 验证测试                  ║")
	print("╚══════════════════════════════════════════╝\n")
	_run_tests()

func _run_tests() -> void:
	var engine := ReactionInference.new()
	engine.load_databases(
		"res://data/substances/substance_registry.json",
		"res://data/reactions/reaction_rules.json"
	)

	# ── 构建角色并填入行为谱 ────────────────────────────
	print("═══ 测试一：构建角色行为谱 ═══\n")

	var player := Character.new("实验者·甲", "player", 350.0)
	player.draw_count = 2   # 每回合抽 2 张

	# 用 ReactionAction 工厂方法从物质档案构建行动
	var hcl_strike := ReactionAction.from_substance(engine, "HCl", ReactionAction.TYPE_STRIKE)
	hcl_strike.action_name = "盐酸冲击"
	hcl_strike.energy_cost = {Character.ENERGY_ACTIVATION: 15.0}

	var kmno4_strike := ReactionAction.from_substance(engine, "KMnO4", ReactionAction.TYPE_STRIKE)
	kmno4_strike.action_name = "高锰酸钾氧化"
	kmno4_strike.energy_cost = {Character.ENERGY_ACTIVATION: 25.0, Character.ENERGY_ELECTRON: 2.0}

	var na_strike := ReactionAction.from_substance(engine, "Na", ReactionAction.TYPE_STRIKE)
	na_strike.action_name = "钠焰爆燃"
	na_strike.keywords    = ["先手"]
	na_strike.energy_cost = {Character.ENERGY_ACTIVATION: 30.0}

	var heating := ReactionAction.make_field_intervention(
		"升温催化", {"temp_delta": 15.0}, 2)
	heating.energy_cost = {Character.ENERGY_ACTIVATION: 10.0}

	# 加入行为谱
	player.add_to_spectrum(hcl_strike)
	player.add_to_spectrum(kmno4_strike)
	player.add_to_spectrum(na_strike)
	player.add_to_spectrum(heating)
	player.add_to_spectrum(ReactionAction.from_substance(engine, "H2SO4", ReactionAction.TYPE_STRIKE))

	print("  角色：%s" % player.get_summary())
	print("  行为谱总量：%d 个反应行动" % player.get_total_action_count())

	# ── 模拟三个回合的抽取循环 ──────────────────────────
	print("\n═══ 测试二：三回合抽取循环 ═══\n")

	for turn in range(3):
		print("  ── 回合 %d ──" % (turn + 1))

		# 回合开始：从行为谱抽取到待机区
		var drawn: Array = player.draw_to_standby()
		print("  抽取了 %d 个行动到待机区：" % drawn.size())
		for action in drawn:
			print("    [%s] %s  活化能=%.0f" % [
				action.get_type_label(),
				action.action_name,
				action.get_activation_cost()
			])

		# 使用待机区第一个可负担的行动
		var affordable: Array = player.get_affordable_standby()
		if not affordable.is_empty():
			var chosen = affordable[0]
			player.use_action_from_standby(chosen)
			player.spend_energy(chosen.energy_cost)
			print("\n  使用了：[%s] %s" % [chosen.get_type_label(), chosen.action_name])
		else:
			print("\n  无可负担行动，Pass（待机区保留）")

		# 回合结束状态
		player.restore_energy_per_turn()
		print("  回合结束状态：%s" % player.get_summary())
		print("  待机区剩余：%d  沉淀区：%d" % [
			player.standby.size(), player.sediment.size()])

		# 保留待机区（pass 保留手牌机制，不 flush）
		print("")

	# ── 测试行为谱耗尽后自动重置 ────────────────────────
	print("═══ 测试三：行为谱耗尽自动重置 ═══\n")

	var test_char := Character.new("测试角色", "player", 100.0)
	test_char.draw_count = 2

	# 只放 2 个行动，确保快速耗尽
	test_char.add_to_spectrum(
		ReactionAction.from_substance(engine, "HCl", ReactionAction.TYPE_STRIKE))
	test_char.add_to_spectrum(
		ReactionAction.from_substance(engine, "NaOH", ReactionAction.TYPE_STRIKE))

	print("  初始行为谱：%d 个" % test_char.behavior_spectrum.size())

	# 抽两次清空行为谱
	var d1 := test_char.draw_to_standby()
	test_char.flush_standby_to_sediment()
	print("  第一轮抽取 %d 个后 → 谱=%d 沉=%d" % [
		d1.size(), test_char.behavior_spectrum.size(), test_char.sediment.size()])

	# 行为谱已空，下次抽取应触发自动重置
	var d2 := test_char.draw_to_standby()
	test_char.flush_standby_to_sediment()
	print("  行为谱耗尽后重置再抽 %d 个 → 谱=%d 沉=%d" % [
		d2.size(), test_char.behavior_spectrum.size(), test_char.sediment.size()])
	print("  ✅ 自动重置正常" if d2.size() > 0 else "  ❌ 重置失败")

	print("\n✅ 所有测试完成")
