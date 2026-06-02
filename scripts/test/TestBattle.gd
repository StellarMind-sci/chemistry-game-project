# TestBattle.gd
# 第一个可运行战斗原型：把这个脚本挂到 Godot 场景的任意 Node 节点上
# 运行场景后在【输出面板】查看完整战斗过程
# ──────────────────────────────────────────────────────────
# 测试对战设定：
#   玩家：实验者（盐酸冲击 + 高锰酸钾氧化 + 钠焰爆燃）
#   敌人：铜绿 Cu₂(OH)₂CO₃（碱性防御 + 氧化铜反击 + 碳酸释放）
# 预期命中规则：强酸强碱中和、铜溶于氧化性酸、氧化还原反应
extends Node

func _ready() -> void:
	print("╔══════════════════════════════════════════╗")
	print("║   化学策略战斗游戏 · 原型 v0.1          ║")
	print("╚══════════════════════════════════════════╝")
	_run_test_battle()

func _run_test_battle() -> void:
	# ── 构建玩家角色 ─────────────────────────────────────
	var player := Character.new("实验者·甲", "player", 350.0)

	var hcl := Skill.make_hcl_attack()
	player.skills.append(hcl)

	var oxidizer := Skill.make_oxidizer()
	player.skills.append(oxidizer)

	var sodium := Skill.make_sodium_attack()
	player.skills.append(sodium)

	# ── 构建敌人角色：铜绿（碱式碳酸铜 Cu₂(OH)₂CO₃）────────
	# 碱式碳酸铜是无机系角色，用组分图建模
	var enemy := Character.new("铜绿 Cu₂(OH)₂CO₃", "enemy", 500.0)

	# 为敌人的技能设置对应的化学标签，体现铜绿的化学性质
	var base_shield := Skill.new("碱性防御")
	base_shield.element_tags = ["Cu", "O", "H"]
	base_shield.chem_tags    = [Skill.TAG_ALKALINE, Skill.TAG_HYDROXYL]
	base_shield.energy_cost  = {Character.ENERGY_ACTIVATION: 10.0}
	base_shield.base_damage  = 12.0
	base_shield.description  = "铜绿含碱性羟基，对酸性攻击有吸附反制"
	enemy.skills.append(base_shield)

	var carbonate_counter := Skill.new("碳酸气泡")
	carbonate_counter.element_tags = ["Cu", "C", "O"]
	carbonate_counter.chem_tags    = [Skill.TAG_ALKALINE]
	carbonate_counter.energy_cost  = {Character.ENERGY_ACTIVATION: 18.0}
	carbonate_counter.base_damage  = 20.0
	carbonate_counter.description  = "释放 CO₂ 气泡，扰动酸碱平衡"
	enemy.skills.append(carbonate_counter)

	var copper_oxidize := Skill.new("铜离子释放")
	copper_oxidize.element_tags = ["Cu", "O"]
	copper_oxidize.chem_tags    = [Skill.TAG_OXIDIZING]
	copper_oxidize.energy_cost  = {Character.ENERGY_ACTIVATION: 22.0, Character.ENERGY_ELECTRON: 1.0}
	copper_oxidize.base_damage  = 28.0
	copper_oxidize.description  = "Cu²⁺ 具有氧化性，攻击对手的还原性官能团"
	enemy.skills.append(copper_oxidize)

	# ── 给敌人构建无机组分图结构 ─────────────────────────
	var structure := ChemicalStructure.InorganicStructure.new()
	structure.add_cation("Cu2+_1", "Cu²⁺ (1)", 1.0)
	structure.add_cation("Cu2+_2", "Cu²⁺ (2)", 1.0)
	structure.add_anion("OH-_1",  "OH⁻ (1)",  0.8)
	structure.add_anion("OH-_2",  "OH⁻ (2)",  0.8)
	structure.add_anion("CO3-",   "CO₃²⁻",   0.9)
	structure.add_ionic_bond("Cu2+_1", "OH-_1",  0.8)
	structure.add_ionic_bond("Cu2+_1", "CO3-",   0.9)
	structure.add_ionic_bond("Cu2+_2", "OH-_2",  0.8)
	structure.add_ionic_bond("Cu2+_2", "CO3-",   0.9)
	enemy.structure = structure

	print("\n敌人结构：" + structure.get_integrity_summary())

	# ── 初始化战斗管理器 ──────────────────────────────────
	var battle := BattleManager.new()
	battle.setup(player, enemy)

	# ── 运行完整战斗 ──────────────────────────────────────
	var winner := battle.run_battle(20)

	# ── 战斗结束，输出结构损伤报告 ─────────────────────────
	print("\n═══ 战后结构报告 ═══")
	if is_instance_valid(enemy.structure):
		print("铜绿结构：" + enemy.structure.get_integrity_summary())
	print("战斗共进行 %d 回合" % battle.turn_count)
	print("最终环境：" + battle.environment.get_summary())
	print("\n[提示] 下一步：")
	print("  1. 修改 TestBattle.gd 里的技能标签，观察命中的规则变化")
	print("  2. 在 reaction_rules.json 添加新反应，无需改任何 .gd 文件")
	print("  3. 调整 Environment 的基准值，观察勒夏特列反馈效果")
