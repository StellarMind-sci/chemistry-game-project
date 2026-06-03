# Catalyst.gd
# 催化剂：部署到战场后持续影响特定类型反应的效率和能量门槛
# 设计原则：催化剂是装备型机制，不消耗手牌，每回合持续生效
class_name Catalyst
extends RefCounted

# ── 标识 ─────────────────────────────────────────────────
var catalyst_id:   String
var catalyst_name: String
var description:   String

# ── 影响范围（空 = 影响全部）─────────────────────────────
var affects_rule_types: Array = []  # ["redox", "exothermic", ...] 空=全部
var affects_elements:   Array = []  # ["H","C",...] 空=不限元素

# ── 效果修正 ──────────────────────────────────────────────
var efficiency_multiplier:   float = 1.0   # 反应效率倍率（1.2 = +20%）
var activation_reduction:    float = 0.0   # 降低活化能消耗（绝对值）
var damage_multiplier_bonus: float = 0.0   # 伤害倍率附加值

# ── 持续性 ────────────────────────────────────────────────
var turns_remaining: int  = -1    # -1 = 永久直到被移除
var is_active:       bool = true

# ── 来源 ─────────────────────────────────────────────────
var deployed_by: Character = null  # 谁部署了这个催化剂

# ══════════════════════════════════════════════════════════
# 初始化
# ══════════════════════════════════════════════════════════
func _init(p_id: String = "", p_name: String = "") -> void:
	catalyst_id   = p_id
	catalyst_name = p_name

# ══════════════════════════════════════════════════════════
# 每回合 tick（由 BattleManager 在 phase_env_effects 末尾调用）
# 返回 false 表示催化剂本回合到期失效
# ══════════════════════════════════════════════════════════
func tick() -> bool:
	if turns_remaining == -1: return true
	turns_remaining -= 1
	is_active = turns_remaining > 0
	return is_active

# ══════════════════════════════════════════════════════════
# 判断是否对特定规则生效
# ══════════════════════════════════════════════════════════
func applies_to_rule(rule: ReactionRule) -> bool:
	if not is_active: return false
	# 检查反应类型限制
	if not affects_rule_types.is_empty():
		var rt: String = rule.get("reaction_type") if "reaction_type" in rule \
			else rule.base_effect.get("reaction_type", "")
		if rt not in affects_rule_types: return false
	return true

# ══════════════════════════════════════════════════════════
# 修正反应效果（在 BattleManager.resolve_reaction 中调用）
# ══════════════════════════════════════════════════════════
func modify_effect(effect: Dictionary, rule: ReactionRule) -> Dictionary:
	if not applies_to_rule(rule): return effect
	var m := effect.duplicate(true)
	# 效率倍率
	if efficiency_multiplier != 1.0:
		var dm: float = float(m.get("damage_multiplier", 1.0))
		m["damage_multiplier"] = dm * efficiency_multiplier
	# 伤害倍率附加
	if damage_multiplier_bonus != 0.0:
		var dm: float = float(m.get("damage_multiplier", 1.0))
		m["damage_multiplier"] = dm + damage_multiplier_bonus
	return m

# ══════════════════════════════════════════════════════════
# 查询某个行动在本催化剂下活化能减少多少
# ══════════════════════════════════════════════════════════
func get_activation_reduction_for(action) -> float:
	if not is_active: return 0.0
	if action == null: return 0.0
	# 如果有元素限制，检查行动是否含有这些元素
	if not affects_elements.is_empty():
		var action_elems: Array = action.element_tags if "element_tags" in action else []
		var match_found := false
		for elem in affects_elements:
			if elem in action_elems:
				match_found = true
				break
		if not match_found: return 0.0
	return activation_reduction

# ══════════════════════════════════════════════════════════
# 工厂方法：常用催化剂预设
# ══════════════════════════════════════════════════════════

# 镍催化剂：降低加氢反应（还原类）活化能 -15，效率 ×1.3
static func make_nickel_catalyst(turns: int = 3) -> Catalyst:
	var c := Catalyst.new("ni_catalyst", "镍催化剂 Ni")
	c.description         = "降低加氢/还原反应的活化能门槛，加速反应进程"
	c.affects_rule_types  = ["endothermic", "redox"]
	c.efficiency_multiplier  = 1.30
	c.activation_reduction   = 15.0
	c.turns_remaining        = turns
	return c

# 浓H₂SO₄催化剂：加速酸碱和酯化反应，效率 ×1.25，活化能 -10
static func make_sulfuric_catalyst(turns: int = 2) -> Catalyst:
	var c := Catalyst.new("h2so4_catalyst", "浓H₂SO₄催化")
	c.description         = "加速酸碱中和与酯化反应，但会升高反应体系温度"
	c.affects_rule_types  = ["acid_base", "endothermic"]
	c.efficiency_multiplier  = 1.25
	c.activation_reduction   = 10.0
	c.turns_remaining        = turns
	return c

# 铁触媒：加速氧化还原，效率 ×1.4，活化能 -8
static func make_iron_catalyst(turns: int = 2) -> Catalyst:
	var c := Catalyst.new("fe_catalyst", "铁触媒")
	c.description         = "工业合成氨用铁触媒，提升氧化还原反应效率"
	c.affects_rule_types  = ["redox"]
	c.affects_elements    = ["N", "Fe"]
	c.efficiency_multiplier  = 1.40
	c.activation_reduction   = 8.0
	c.turns_remaining        = turns
	return c

func get_summary() -> String:
	var turns_str := "永久" if turns_remaining == -1 else "%d回合" % turns_remaining
	return "[%s] %s  效率×%.2f  AE-%.0f  剩余%s" % [
		catalyst_id, catalyst_name, efficiency_multiplier,
		activation_reduction, turns_str]
