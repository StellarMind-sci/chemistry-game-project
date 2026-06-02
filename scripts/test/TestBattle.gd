# TestBattle.gd
# 测试场景入口脚本 v0.2
extends Node

func _ready() -> void:
	print("╔══════════════════════════════════════════╗")
	print("║   化学策略战斗游戏 · 原型 v0.2          ║")
	print("║   新增：对称伤害解算 · 双方互打          ║")
	print("╚══════════════════════════════════════════╝")
	_run_test_battle()

func _run_test_battle() -> void:
	# ── 构建玩家角色 ─────────────────────────────────────
	var player := Character.new("实验者·甲", "player", 350.0)
	player.skills.append(Skill.make_hcl_attack())
	player.skills.append(Skill.make_oxidizer())
	player.skills.append(Skill.make_sodium_attack())

	# ── 构建敌人：铜绿 Cu₂(OH)₂CO₃ ──────────────────────
	var enemy := Character.new("铜绿 Cu₂(OH)₂CO₃", "enemy", 500.0)

	var base_shield := Skill.new("碱性防御")
	base_shield.element_tags = ["Cu", "O", "H"]
	base_shield.chem_tags    = [Skill.TAG_ALKALINE, Skill.TAG_HYDROXYL]
	base_shield.energy_cost  = {Character.ENERGY_ACTIVATION: 10.0}
	base_shield.base_damage  = 12.0
	enemy.skills.append(base_shield)

	var carbonate_counter := Skill.new("碳酸气泡")
	carbonate_counter.element_tags = ["Cu", "C", "O"]
	carbonate_counter.chem_tags    = [Skill.TAG_ALKALINE]
	carbonate_counter.energy_cost  = {Character.ENERGY_ACTIVATION: 18.0}
	carbonate_counter.base_damage  = 20.0
	enemy.skills.append(carbonate_counter)

	var copper_oxidize := Skill.new("铜离子释放")
	copper_oxidize.element_tags = ["Cu", "O"]
	copper_oxidize.chem_tags    = [Skill.TAG_OXIDIZING]
	copper_oxidize.energy_cost  = {Character.ENERGY_ACTIVATION: 22.0, Character.ENERGY_ELECTRON: 1.0}
	copper_oxidize.base_damage  = 28.0
	enemy.skills.append(copper_oxidize)

	# ── 构建铜绿的无机组分图结构 ─────────────────────────
	var structure := ChemicalStructure.InorganicStructure.new()
	structure.add_cation("Cu2+_1", "Cu²⁺ (1)", 1.0)
	structure.add_cation("Cu2+_2", "Cu²⁺ (2)", 1.0)
	structure.add_anion("OH-_1",  "OH⁻ (1)",  0.8)
	structure.add_anion("OH-_2",  "OH⁻ (2)",  0.8)
	structure.add_anion("CO3-",   "CO₃²⁻",   0.9)
	structure.add_ionic_bond("Cu2+_1", "OH-_1", 0.8)
	structure.add_ionic_bond("Cu2+_1", "CO3-",  0.9)
	structure.add_ionic_bond("Cu2+_2", "OH-_2", 0.8)
	structure.add_ionic_bond("Cu2+_2", "CO3-",  0.9)
	enemy.structure = structure   # 现在 Character 有 structure 字段了

	print("\n敌人结构：" + structure.get_integrity_summary())

	# ── 初始化战斗管理器 ──────────────────────────────────
	var battle := BattleManager.new()
	battle.setup(player, enemy)

	# ── 运行战斗（_winner 前缀表示有意不使用该变量）────────
	var _winner := battle.run_battle(20)

	# ── 战后报告 ──────────────────────────────────────────
	print("\n═══ 战后报告 ═══")
	print("战斗进行了 %d 回合" % battle.turn_count)
	print("玩家最终 HP：%.0f / %.0f" % [player.hp, player.max_hp])
	print("敌人最终 HP：%.0f / %.0f" % [enemy.hp,   enemy.max_hp])
	print("最终环境：" + battle.environment.get_summary())
	if enemy.structure != null:
		print("铜绿结构：" + enemy.structure.get_integrity_summary())
