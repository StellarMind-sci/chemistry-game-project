# Character.gd
# 角色数据类 v0.3
# 新增：行为谱（牌库）/ 待机区（手牌）/ 沉淀区（弃牌堆）三区系统
class_name Character
extends RefCounted

# ── 能量常量 ──────────────────────────────────────────────
const ENERGY_ACTIVATION = "activation_energy"
const ENERGY_ELECTRON   = "electron_count"
const ENERGY_FREE       = "free_energy"

# ── 基本属性 ──────────────────────────────────────────────
var char_name: String
var faction:   String
var hp:        float
var max_hp:    float
var structure

# ── 能量池 ────────────────────────────────────────────────
var energy_pool: Dictionary

# ── 状态效果 ──────────────────────────────────────────────
var status_effects: Array

# ══════════════════════════════════════════════════════════
# 行为谱三区
# behavior_spectrum：行为谱（完整牌库）
# standby：          待机区（本回合手牌）
# sediment：         沉淀区（已用待重置）
# ══════════════════════════════════════════════════════════
var behavior_spectrum: Array = []
var standby:           Array = []
var sediment:          Array = []

var draw_count: int = 3   # 每回合抽取数，化学特性/装备可改

# 向后兼容：skills 属性别名，旧代码不需要改
var skills: Array:
	get: return behavior_spectrum
	set(v): behavior_spectrum = v

# ── 初始化 ────────────────────────────────────────────────

func _init(p_name: String, p_faction: String, p_max_hp: float) -> void:
	char_name      = p_name
	faction        = p_faction
	max_hp         = p_max_hp
	hp             = p_max_hp
	structure      = null
	status_effects = []
	energy_pool    = {
		ENERGY_ACTIVATION: 100.0,
		ENERGY_ELECTRON:    10.0,
		ENERGY_FREE:        50.0,
	}

# ══════════════════════════════════════════════════════════
# 行为谱操作
# ══════════════════════════════════════════════════════════

# 向行为谱添加反应行动（建立角色时调用）
func add_to_spectrum(action) -> void:
	behavior_spectrum.append(action)

# 从行为谱随机抽取到待机区（行为谱耗尽时自动从沉淀区重置）
func draw_to_standby(count: int = -1) -> Array:
	var n: int = count if count > 0 else draw_count
	var drawn: Array = []
	for _i in range(n):
		if behavior_spectrum.is_empty():
			_reset_spectrum()
			if behavior_spectrum.is_empty():
				break
		var idx: int = randi() % behavior_spectrum.size()
		var action = behavior_spectrum[idx]
		behavior_spectrum.remove_at(idx)
		standby.append(action)
		drawn.append(action)
	return drawn

# 使用待机区中的一个反应行动（移入沉淀区）
func use_action_from_standby(action) -> bool:
	var idx: int = standby.find(action)
	if idx == -1:
		push_warning("use_action_from_standby：行动不在待机区")
		return false
	standby.remove_at(idx)
	if action.consumes_on_use:
		sediment.append(action)
	return true

# Pass：不使用，待机区该行动回沉淀区，手牌保留逻辑由调用方控制
func discard_from_standby(action) -> void:
	var idx: int = standby.find(action)
	if idx != -1:
		standby.remove_at(idx)
		sediment.append(action)

# 回合结束，待机区未使用的行动全部冲入沉淀区
func flush_standby_to_sediment() -> void:
	for action in standby:
		sediment.append(action)
	standby.clear()

# 内部：沉淀区归位并洗牌
func _reset_spectrum() -> void:
	for action in sediment:
		behavior_spectrum.append(action)
	sediment.clear()
	_shuffle_array(behavior_spectrum)

func _shuffle_array(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# 获取三区总行动数
func get_total_action_count() -> int:
	return behavior_spectrum.size() + standby.size() + sediment.size()

# 获取待机区中当前可负担的行动
func get_affordable_standby() -> Array:
	var result: Array = []
	for action in standby:
		if can_afford(action.energy_cost):
			result.append(action)
	return result

# ══════════════════════════════════════════════════════════
# 生命值
# ══════════════════════════════════════════════════════════

func is_alive() -> bool:
	return hp > 0.0

func take_damage(amount: float) -> void:
	hp = max(0.0, hp - amount)

func heal(amount: float) -> void:
	hp = min(max_hp, hp + amount)

# ══════════════════════════════════════════════════════════
# 能量管理
# ══════════════════════════════════════════════════════════

func restore_energy_per_turn() -> void:
	energy_pool[ENERGY_ACTIVATION] = min(100.0, energy_pool[ENERGY_ACTIVATION] + 15.0)
	energy_pool[ENERGY_FREE]       = min(50.0,  energy_pool[ENERGY_FREE]       + 5.0)

func can_afford(cost: Dictionary) -> bool:
	for res_type: String in cost:
		if energy_pool.get(res_type, 0.0) < float(cost[res_type]):
			return false
	return true

func spend_energy(cost: Dictionary) -> void:
	for res_type: String in cost:
		energy_pool[res_type] = max(0.0, energy_pool[res_type] - float(cost[res_type]))

# ══════════════════════════════════════════════════════════
# 状态效果
# ══════════════════════════════════════════════════════════

func add_status(effect: Dictionary) -> void:
	status_effects.append(effect)

func tick_status_effects() -> void:
	var remaining: Array = []
	for eff: Dictionary in status_effects:
		eff["duration"] = eff.get("duration", 1) - 1
		if eff["duration"] > 0:
			remaining.append(eff)
	status_effects = remaining

# ══════════════════════════════════════════════════════════
# 辅助查询（向后兼容 BattleManager 的现有调用）
# ══════════════════════════════════════════════════════════

func has_skill_with_element(element: String) -> bool:
	for action in behavior_spectrum + standby + sediment:
		if action.has_element(element):
			return true
	return false

func has_skill_with_tag(tag: String) -> bool:
	for action in behavior_spectrum + standby + sediment:
		if action.has_chem_tag(tag):
			return true
	return false

func get_hp_ratio() -> float:
	if max_hp == 0.0: return 0.0
	return hp / max_hp

func get_summary() -> String:
	return "%s | HP %.0f/%.0f | AE %.0f | 谱%d 手%d 沉%d" % [
		char_name, hp, max_hp,
		energy_pool[ENERGY_ACTIVATION],
		behavior_spectrum.size(), standby.size(), sediment.size()
	]
