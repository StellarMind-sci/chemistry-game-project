# ReactionAction.gd
# 反应行动：角色发起的化学行为（从 Skill 演进而来）
# 双类型设计：
#   攻势型 —— 主动冲突，进入碰撞解算
#   调控型 —— 改变战场或对手化学状态（场地型/定向型）
class_name ReactionAction
extends RefCounted

# ══════════════════════════════════════════════════════════
# 类型常量
# ══════════════════════════════════════════════════════════
const TYPE_STRIKE       = "攻势"       # 主动冲突
const TYPE_INTERVENTION = "调控"       # 改变状态/环境

const SUBTYPE_FIELD     = "场地型"     # 调控-场地型（影响环境变量）
const SUBTYPE_DIRECTED  = "定向型"     # 调控-定向型（改变特定节点状态）

# 化学特性标签
const TAG_ACIDIC     = "acidic"
const TAG_ALKALINE   = "alkaline"
const TAG_OXIDIZING  = "oxidizing"
const TAG_REDUCING   = "reducing"
const TAG_HYDROXYL   = "hydroxyl"
const TAG_BENZENE    = "benzene_ring"
const TAG_CARBONYL   = "carbonyl"
const TAG_AMINO      = "amino"
const TAG_HALOGEN    = "halogen"
const TAG_ELECTRO    = "electrophilic"
const TAG_EXOTHERMIC = "exothermic"
const TAG_ENDOTHERM  = "endothermic"
const TAG_ALDEHYDE   = "aldehyde"

# 能量类型（与 Character 一致）
const ENERGY_ACTIVATION = "activation_energy"
const ENERGY_ELECTRON   = "electron_count"
const ENERGY_FREE       = "free_energy"

# ══════════════════════════════════════════════════════════
# 字段定义
# ══════════════════════════════════════════════════════════

# ── 标识 ─────────────────────────────────────────────────
var action_name:  String = ""        # 显示名称
var substance_id: String = ""        # 关联物质ID（指向 substance_registry）

# ── 类型 ─────────────────────────────────────────────────
var action_type: String = TYPE_STRIKE
var subtype:     String = ""         # 调控型才有：场地型/定向型

# ── 化学标签 ─────────────────────────────────────────────
var element_tags: Array = []         # 元素：["H", "Cl"]
var chem_tags:    Array = []         # 特性：["acidic", "halogen"]

# ── 代价 ─────────────────────────────────────────────────
var energy_cost:    Dictionary = {ENERGY_ACTIVATION: 10.0}
var base_intensity: float = 10.0     # 反应基础强度（原 base_damage）

# ── 目标 ─────────────────────────────────────────────────
var target_node:         String = ""  # 攻势型：攻击的结构节点ID
var target_state_change: String = ""  # 调控-定向型：要改变的状态

# ── 持续性（调控型用）────────────────────────────────────
var is_persistent:      bool = false
var persist_turns:      int  = 0
var environment_change: Dictionary = {}  # 调控-场地型：环境扰动

# ── 卡牌属性 ─────────────────────────────────────────────
var is_default:      bool = true        # 是否默认行动（不可改）
var is_modifiable:   bool = true        # 是否可被改造
var consumes_on_use: bool = true        # 使用后是否进沉淀区

# ── 高级属性 ─────────────────────────────────────────────
var prerequisite: String = ""           # 前置条件描述（"" = 无前置）
var keywords:     Array  = []           # 解算顺序关键字（"先手"/"后手"等）
var description:  String = ""

# ══════════════════════════════════════════════════════════
# 初始化
# ══════════════════════════════════════════════════════════

func _init(p_name: String = "") -> void:
	action_name = p_name

# ══════════════════════════════════════════════════════════
# 工厂方法：从物质档案自动填充
# 用法：ReactionAction.from_substance(inference, "HCl", TYPE_STRIKE)
# ══════════════════════════════════════════════════════════

static func from_substance(inference, sub_id: String,
		p_type: String = TYPE_STRIKE) -> ReactionAction:
	var ra := ReactionAction.new()
	ra.substance_id = sub_id
	ra.action_type  = p_type

	var sub: Dictionary = inference.get_substance(sub_id)
	if sub.is_empty():
		push_warning("ReactionAction.from_substance：物质 %s 不存在" % sub_id)
		return ra

	ra.action_name   = sub.get("display_name", sub_id)
	ra.element_tags  = (sub.get("element_tags", []) as Array).duplicate()
	ra.chem_tags     = (sub.get("chem_tags", [])    as Array).duplicate()

	# 基础强度从物质的 reaction_activity 推导：活性 × 40
	var activity: float = float(sub.get("reaction_activity", 0.5))
	ra.base_intensity = activity * 40.0
	return ra

# 构造调控-场地型行动（直接影响环境）
static func make_field_intervention(p_name: String, env_delta: Dictionary,
		turns: int = 2) -> ReactionAction:
	var ra := ReactionAction.new(p_name)
	ra.action_type        = TYPE_INTERVENTION
	ra.subtype            = SUBTYPE_FIELD
	ra.environment_change = env_delta
	ra.is_persistent      = (turns > 1)
	ra.persist_turns      = turns
	ra.base_intensity     = 0.0   # 调控-场地型不造成直接伤害
	return ra

# 构造调控-定向型行动（改变特定节点状态）
static func make_directed_intervention(p_name: String, target_node_id: String,
		state_change: String) -> ReactionAction:
	var ra := ReactionAction.new(p_name)
	ra.action_type         = TYPE_INTERVENTION
	ra.subtype             = SUBTYPE_DIRECTED
	ra.target_node         = target_node_id
	ra.target_state_change = state_change
	ra.base_intensity      = 0.0
	return ra

# ══════════════════════════════════════════════════════════
# 类型判断
# ══════════════════════════════════════════════════════════

func is_strike() -> bool:
	return action_type == TYPE_STRIKE

func is_intervention() -> bool:
	return action_type == TYPE_INTERVENTION

func is_field_intervention() -> bool:
	return is_intervention() and subtype == SUBTYPE_FIELD

func is_directed_intervention() -> bool:
	return is_intervention() and subtype == SUBTYPE_DIRECTED

# 调控型不占用攻击箭头（玩家一回合可同时出调控+攻势）
func uses_attack_arrow() -> bool:
	return is_strike()

# ══════════════════════════════════════════════════════════
# 标签查询
# ══════════════════════════════════════════════════════════

func has_element(elem: String) -> bool:
	return elem in element_tags

func has_chem_tag(tag: String) -> bool:
	return tag in chem_tags

func has_any_element(elems: Array) -> bool:
	for e: String in elems:
		if has_element(e):
			return true
	return false

func has_any_tag(tags: Array) -> bool:
	for t: String in tags:
		if has_chem_tag(t):
			return true
	return false

func is_acidic()    -> bool: return has_chem_tag(TAG_ACIDIC)
func is_alkaline()  -> bool: return has_chem_tag(TAG_ALKALINE)
func is_oxidizing() -> bool: return has_chem_tag(TAG_OXIDIZING)
func is_reducing()  -> bool: return has_chem_tag(TAG_REDUCING)

# ══════════════════════════════════════════════════════════
# 解算顺序辅助（对应五级优先 P2/P3）
# ══════════════════════════════════════════════════════════

func has_keyword(kw: String) -> bool:
	return kw in keywords

# P2：关键字优先
func is_priority_first() -> bool:
	return has_keyword("先手") or has_keyword("first_strike")

func is_priority_last() -> bool:
	return has_keyword("后手") or has_keyword("last_strike")

# P3：活化能消耗值（越低越先解算）
func get_activation_cost() -> float:
	return float(energy_cost.get(ENERGY_ACTIVATION, 0.0))

# ══════════════════════════════════════════════════════════
# 描述与摘要
# ══════════════════════════════════════════════════════════

func get_type_label() -> String:
	if action_type == TYPE_INTERVENTION and subtype != "":
		return "%s·%s" % [action_type, subtype]
	return action_type

func get_summary() -> String:
	return "[%s] %s | 元素%s 特性%s | 强度%.0f | 活化能%.0f" % [
		get_type_label(), action_name,
		str(element_tags), str(chem_tags),
		base_intensity, get_activation_cost()
	]

func get_tag_summary() -> String:
	return "元素[%s] 特性[%s]" % [",".join(element_tags), ",".join(chem_tags)]

# ══════════════════════════════════════════════════════════
# 兼容性接口：保留 base_damage 别名以平滑迁移
# 旧代码访问 .base_damage 仍然返回 base_intensity
# ══════════════════════════════════════════════════════════

func get_base_damage() -> float:
	return base_intensity
