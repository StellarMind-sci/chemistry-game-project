# Character.gd
# 角色数据类：存储战斗中一个角色的全部状态
class_name Character
extends RefCounted

var char_name: String
var faction: String
var hp: float
var max_hp: float
var skills: Array
var status_effects: Array
var energy_pool: Dictionary
var structure          # 化学结构（OrganicStructure 或 InorganicStructure），可为 null

const ENERGY_ACTIVATION   = "activation_energy"
const ENERGY_ELECTRON     = "electron_count"
const ENERGY_FREE         = "free_energy"

func _init(p_name: String, p_faction: String, p_max_hp: float) -> void:
	char_name      = p_name
	faction        = p_faction
	max_hp         = p_max_hp
	hp             = p_max_hp
	skills         = []
	status_effects = []
	structure      = null
	energy_pool    = {
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
	energy_pool[ENERGY_ACTIVATION] = min(100.0, energy_pool[ENERGY_ACTIVATION] + 15.0)
	energy_pool[ENERGY_FREE]       = min(50.0,  energy_pool[ENERGY_FREE]       + 5.0)

func can_afford(cost: Dictionary) -> bool:
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
	if max_hp == 0.0: return 0.0
	return hp / max_hp

func get_summary() -> String:
	return "%s | HP %.0f/%.0f | AE %.0f | EL %.0f | GE %.0f" % [
		char_name, hp, max_hp,
		energy_pool[ENERGY_ACTIVATION],
		energy_pool[ENERGY_ELECTRON],
		energy_pool[ENERGY_FREE],
	]
