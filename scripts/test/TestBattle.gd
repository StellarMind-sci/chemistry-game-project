# TestBattle.gd v0.3
# 测试场景：2v1 多单位战斗演示
# 玩家2名角色 vs 敌方1名角色（演示多单位碰撞系统）
extends Node

func _ready() -> void:
	print("╔══════════════════════════════════════════╗")
	print("║   化学策略战斗游戏 · 原型 v0.3          ║")
	print("║   多单位战斗系统 · 2 vs 1               ║")
	print("╚══════════════════════════════════════════╝")
	_run_test_battle()

func _run_test_battle() -> void:
	var engine := ReactionInference.new()
	engine.load_databases(
		"res://data/substances/substance_registry.json",
		"res://data/reactions/reaction_rules.json"
	)

	# ── 玩家角色一：酸性攻击手 ───────────────────────────
	var player_a := Character.new("实验者·酸", "player", 300.0)
	player_a.draw_count = 2

	var hcl := ReactionAction.from_substance(engine, "HCl", ReactionAction.TYPE_STRIKE)
	hcl.action_name = "盐酸冲击"
	hcl.energy_cost = {Character.ENERGY_ACTIVATION: 15.0}

	var h2so4 := ReactionAction.from_substance(engine, "H2SO4", ReactionAction.TYPE_STRIKE)
	h2so4.action_name = "硫酸腐蚀"
	h2so4.energy_cost = {Character.ENERGY_ACTIVATION: 20.0}

	var heating := ReactionAction.make_field_intervention(
		"升温催化", {"temp_delta": 12.0}, 2)
	heating.energy_cost = {Character.ENERGY_ACTIVATION: 8.0}

	player_a.add_to_spectrum(hcl)
	player_a.add_to_spectrum(h2so4)
	player_a.add_to_spectrum(heating)

	# ── 玩家角色二：氧化攻击手 ───────────────────────────
	var player_b := Character.new("实验者·氧", "player", 280.0)
	player_b.draw_count = 2

	var kmno4 := ReactionAction.from_substance(engine, "KMnO4", ReactionAction.TYPE_STRIKE)
	kmno4.action_name   = "高锰酸钾氧化"
	kmno4.energy_cost   = {Character.ENERGY_ACTIVATION: 25.0, Character.ENERGY_ELECTRON: 2.0}
	kmno4.keywords      = ["先手"]   # 携带先手关键字（P2 优先解算）

	var na := ReactionAction.from_substance(engine, "Na", ReactionAction.TYPE_STRIKE)
	na.action_name = "钠焰爆燃"
	na.energy_cost = {Character.ENERGY_ACTIVATION: 30.0}

	player_b.add_to_spectrum(kmno4)
	player_b.add_to_spectrum(na)

	# ── 敌方角色：铜绿（占位用，未来换正式 Boss）────────
	var enemy_a := Character.new("铜绿 Cu₂(OH)₂CO₃", "enemy", 600.0)
	enemy_a.draw_count = 2

	var base_shield := ReactionAction.new("碱性防御")
	base_shield.substance_id  = "CuOH2"
	base_shield.element_tags  = ["Cu", "O", "H"]
	base_shield.chem_tags     = [ReactionAction.TAG_ALKALINE, ReactionAction.TAG_HYDROXYL]
	base_shield.energy_cost   = {Character.ENERGY_ACTIVATION: 10.0}
	base_shield.base_intensity = 12.0

	var cu_oxidize := ReactionAction.new("铜离子释放")
	cu_oxidize.substance_id   = "CuSO4"
	cu_oxidize.element_tags   = ["Cu", "O"]
	cu_oxidize.chem_tags      = [ReactionAction.TAG_OXIDIZING]
	cu_oxidize.energy_cost    = {Character.ENERGY_ACTIVATION: 20.0, Character.ENERGY_ELECTRON: 1.0}
	cu_oxidize.base_intensity  = 28.0

	var carbonate := ReactionAction.new("碳酸气泡")
	carbonate.substance_id    = "Na2CO3"
	carbonate.element_tags    = ["Cu", "C", "O"]
	carbonate.chem_tags       = [ReactionAction.TAG_ALKALINE]
	carbonate.energy_cost     = {Character.ENERGY_ACTIVATION: 15.0}
	carbonate.base_intensity   = 18.0

	enemy_a.add_to_spectrum(base_shield)
	enemy_a.add_to_spectrum(cu_oxidize)
	enemy_a.add_to_spectrum(carbonate)

	# ── 初始化多单位战斗 ─────────────────────────────────
	var battle := BattleManager.new()
	battle.setup_teams([player_a, player_b], [enemy_a])

	# ── 运行战斗 ─────────────────────────────────────────
	var winner := battle.run_battle(15)

	# ── 战后报告 ─────────────────────────────────────────
	print("\n═══ 战后报告 ═══")
	print("战斗进行 %d 回合" % battle.turn_count)
	for chara: Character in [player_a, player_b, enemy_a]:
		print("  %s" % chara.get_summary())
	print("最终环境：" + battle.environment.get_summary())
