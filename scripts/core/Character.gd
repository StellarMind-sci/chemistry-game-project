# Character.gd
# 角色数据类：存储战斗中一个角色的全部状态
# 生命值与结构完整性是两个不同概念——关键官能团被破坏可能使角色陷入崩溃
class_name Character
extends RefCounted

var char_name: String          # 角色名称（用 char_name 避免与内置 name 冲突）
var faction: String            # 阵营："player" 或 "enemy"
var hp: float                  # 当前生命值
var max_hp: float              # 最大生命值
var skills: Array              # 技能列表（Array[Skill]，运行时类型由 Skill 类保证）
var status_effects: Array      # 当前状态效果列表，每项为 Dictionary
var energy_pool: Dictionary    # 能量池

# 能量池的三个维度
const ENERGY_ACTIVATION   = "activation_energy"   # 活化能：核心资源，每回合恢复 +15
const ENERGY_ELECTRON     = "electron_count"       # 电子数：氧化还原专用
const ENERGY_FREE         = "free_energy"          # 自由能：综合资源，恢复慢

func _init(p_name: String, p_faction: String, p_max_hp: float) -> void:
	char_name   = p_name
	faction     = p_faction
	max_hp      = p_max_hp
	hp          = p_max_hp
	skills         = []
	status_effects = []
	energy_pool = {
		ENERGY_ACTIVATION: 100.0,
		ENERGY_ELECTRON:    10.0,
		ENERGY_FREE:        50.0,
	}

# ── 生命值 ──────────────────────────────────────────────

func is_alive() -> bool:
	return hp > 0.0

func take_damage(amount: float) -> void:
	hp = max(0.0, hp - amount)

func heal(amount: float) -> void:
	hp = min(max_hp, hp + amount)

# ── 能量管理 ────────────────────────────────────────────

func restore_energy_per_turn() -> void:
	# 每回合活化能自然恢复 +15；自由能恢复 +5；电子数不自然恢复
	energy_pool[ENERGY_ACTIVATION] = min(100.0, energy_pool[ENERGY_ACTIVATION] + 15.0)
	energy_pool[ENERGY_FREE]       = min(50.0,  energy_pool[ENERGY_FREE]       + 5.0)

func can_afford(cost: Dictionary) -> bool:
	# 双重约束：属性系统决定"能不能用"，资源系统决定"能不能负担"
	# 这里只检查资源层（属性层由 BattleManager 在选技能时检查）
	for resource_type: String in cost:
		if energy_pool.get(resource_type, 0.0) < cost[resource_type]:
			return false
	return true

func spend_energy(cost: Dictionary) -> void:
	for resource_type: String in cost:
		energy_pool[resource_type] = max(0.0, energy_pool[resource_type] - cost[resource_type])

# ── 状态效果 ────────────────────────────────────────────

func add_status(effect: Dictionary) -> void:
	status_effects.append(effect)

func tick_status_effects() -> void:
	# 每回合所有持续状态持续时间 -1，移除到期的
	var remaining: Array = []
	for eff: Dictionary in status_effects:
		eff["duration"] = eff.get("duration", 1) - 1
		if eff["duration"] > 0:
			remaining.append(eff)
	status_effects = remaining

# ── 辅助查询 ────────────────────────────────────────────

func has_skill_with_element(element: String) -> bool:
	for skill in skills:
		if skill.has_element(element):
			return true
	return false

func has_skill_with_tag(tag: String) -> bool:
	for skill in skills:
		if skill.has_chem_tag(tag):
			return true
	return false

func get_hp_ratio() -> float:
	if max_hp == 0.0:
		return 0.0
	return hp / max_hp

func get_summary() -> String:
	return "%s | HP %.0f/%.0f | AE %.0f | EL %.0f | GE %.0f" % [
		char_name, hp, max_hp,
		energy_pool[ENERGY_ACTIVATION],
		energy_pool[ENERGY_ELECTRON],
		energy_pool[ENERGY_FREE],
	]
