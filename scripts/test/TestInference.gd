# TestInference.gd
# 验证脚本：测试化学反应推演系统是否正常工作
# 使用方法：把这个脚本挂到任意 Node 节点，F5 运行，看输出面板
extends Node

func _ready() -> void:
	print("\n╔══════════════════════════════════════════╗")
	print("║   化学反应推演系统 · 验证测试            ║")
	print("╚══════════════════════════════════════════╝\n")
	_run_inference_tests()

func _run_inference_tests() -> void:
	# ── 初始化推演引擎 ──────────────────────────────────
	var engine := ReactionInference.new()
	var ok := engine.load_databases(
		"res://data/substances/substance_registry.json",
		"res://data/reactions/reaction_rules.json"
	)

	if not ok:
		print("❌ 数据库加载失败，请检查文件路径")
		return

	print("✅ 数据库加载成功")
	print("   物质档案：%d 种" % engine.get_substance_count())
	print("   反应规则：%d 条\n" % engine.get_rule_count())

	# ── 测试组一：无机反应（应命中具体规则）──────────────
	print("═══ 测试组一：无机反应 ═══")
	_test(engine, "Na",    "Cl2",   "钠 + 氯气")
	_test(engine, "HCl",   "NaOH",  "盐酸 + 氢氧化钠")
	_test(engine, "Na",    "H2O",   "钠 + 水")
	_test(engine, "Fe",    "HCl",   "铁 + 盐酸")
	_test(engine, "Cu",    "HNO3",  "铜 + 硝酸")
	_test(engine, "Zn",    "H2SO4", "锌 + 硫酸")
	_test(engine, "CuO",   "H2SO4", "氧化铜 + 硫酸")
	_test(engine, "CO2",   "NaOH",  "二氧化碳 + 氢氧化钠")
	_test(engine, "CaCO3", "HCl",   "碳酸钙 + 盐酸")

	# ── 测试组二：有机反应（应命中有机规则）──────────────
	print("\n═══ 测试组二：有机反应 ═══")
	_test(engine, "C2H4",       "Cl2",       "乙烯 + 氯气")
	_test(engine, "C2H5OH",     "CH3COOH",   "乙醇 + 乙酸（酯化）")
	_test(engine, "C2H5OH",     "H2SO4",     "乙醇 + 浓硫酸（消去）")
	_test(engine, "CH3CHO",     "KMnO4",     "乙醛 + 高锰酸钾")
	_test(engine, "C6H12O6",    "CuOH2",     "葡萄糖 + 氢氧化铜")
	_test(engine, "CH3COOC2H5", "NaOH",      "乙酸乙酯 + 氢氧化钠（皂化）")
	_test(engine, "C6H5OH",     "NaOH",      "苯酚 + 氢氧化钠")
	_test(engine, "Glycine",    "Glycine",   "甘氨酸 + 甘氨酸（缩合）")
	_test(engine, "HCOOH",      "CuOH2",     "甲酸 + 氢氧化铜（银镜类）")

	# ── 测试组三：无反应（应返回惰性结果）──────────────
	print("\n═══ 测试组三：惰性接触 ═══")
	_test(engine, "Cu",  "NaOH",  "铜 + 氢氧化钠（应无反应）")
	_test(engine, "CH4", "H2O",   "甲烷 + 水（应无明显反应）")

	# ── 测试组四：标签推演接口（战斗中使用）──────────────
	print("\n═══ 测试组四：标签推演接口（战斗模拟）═══")
	var tags_acid   := {"element_tags": ["H","Cl"], "chem_tags": ["acidic"]}
	var tags_alkali := {"element_tags": ["Na","O","H"], "chem_tags": ["alkaline","hydroxyl"]}
	var tags_redox  := {"element_tags": ["K","Mn","O"], "chem_tags": ["oxidizing"]}
	var tags_reduce := {"element_tags": ["C","H","O"], "chem_tags": ["reducing","aldehyde"]}

	_test_tags(engine, tags_acid,  tags_alkali, "酸性手段 vs 碱性角色")
	_test_tags(engine, tags_redox, tags_reduce, "氧化性手段 vs 还原性醛基")

	# ── 测试组五：结构节点查询 ─────────────────────────
	print("\n═══ 测试组五：结构节点查询 ═══")
	for sub_id in ["CuOH2", "C2H5OH", "Glycine", "C6H6"]:
		var nodes: Array = engine.get_structure_nodes(sub_id)
		var sub: Dictionary = engine.get_substance(sub_id)
		print("  %s (%s)：%d 个结构节点" % [
			sub.get("display_name","?"), sub_id, nodes.size()])
		for node: Dictionary in nodes:
			print("    └── [%s] %s  稳定性=%.2f  活性位点=%s" % [
				node.get("type","?"),
				node.get("label","?"),
				float(node.get("stability", 0.0)),
				str(node.get("active_sites", []))
			])

	print("\n✅ 所有测试完成")

# ── 辅助函数 ─────────────────────────────────────────────

func _test(engine: ReactionInference, id_a: String, id_b: String, label: String) -> void:
	var result: ReactionInference.InferenceResult = engine.infer(id_a, id_b)
	var matched_mark := "✅" if result.matched else "⚪"
	print("\n  %s %s" % [matched_mark, label])
	print("     方程式：%s" % result.equation)
	if result.matched:
		var effects: Dictionary = result.game_effects
		print("     规则：%s | 伤害倍率：%.1f | 热效应：%s" % [
			result.rule_name,
			float(effects.get("damage_multiplier", 1.0)),
			result.heat_type
		])
		var env: Dictionary = effects.get("env_delta", {})
		if not env.is_empty():
			print("     环境扰动：%s" % str(env))

func _test_tags(engine: ReactionInference, tags_a: Dictionary,
		tags_b: Dictionary, label: String) -> void:
	var result: ReactionInference.InferenceResult = engine.infer_from_tags(tags_a, tags_b)
	var matched_mark := "✅" if result.matched else "⚪"
	print("\n  %s %s" % [matched_mark, label])
	print("     方程式：%s" % result.equation)
	if result.matched:
		print("     规则：%s" % result.rule_name)
