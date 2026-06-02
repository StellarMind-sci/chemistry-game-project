# ReactionRule.gd
# 反应规则数据类：从 JSON 文件加载后在内存中使用
# 核心设计：规则是数据不是代码，添加新反应无需修改 GDScript
class_name ReactionRule
extends RefCounted

var rule_id:   String     # 规则唯一 ID
var rule_name: String     # 反应名称（如"强酸强碱中和"）
var priority:  int        # 特异性优先级：数值越高越先匹配

# 触发条件：双方技能必须分别满足 a_requires 和 b_requires
# 格式：{"a_requires": {"elements": [...], "chem_tags": [...]}, "b_requires": {...}}
var conditions: Dictionary

var reaction_type: String   # "acid_base" / "redox" / "exothermic" / "endothermic" / "stochastic" / "generic"
var base_effect:  Dictionary  # 基础效果

# 物理化学参数
var optimal_pH:              float   # 最适 pH（酸碱反应用）
var temperature_sensitivity: float   # 温度敏感度（放热/吸热用）

# 反应类型标志（从 reaction_type 字段派生，避免字符串比较热路径）
var _is_exothermic: bool
var _is_endothermic: bool
var _is_acid_base:  bool
var _is_stochastic: bool
var _is_redox:      bool

func _init() -> void:
	priority                = 0
	optimal_pH              = 7.0
	temperature_sensitivity = 0.3
	conditions              = {}
	base_effect             = {
		"damage_multiplier": 1.0,
		"status_effects":    [],
		"env_delta":         {},
	}

# ── 从 Dictionary 初始化（JSON 解析后调用）─────────────────

func from_dict(data: Dictionary) -> void:
	rule_id                 = data.get("id",                    "")
	rule_name               = data.get("name",                  "未命名反应")
	priority                = data.get("priority",              0)
	conditions              = data.get("conditions",            {})
	reaction_type           = data.get("reaction_type",         "generic")
	base_effect             = data.get("base_effect",           {"damage_multiplier": 1.0, "status_effects": [], "env_delta": {}})
	optimal_pH              = float(data.get("optimal_pH",      7.0))
	temperature_sensitivity = float(data.get("temperature_sensitivity", 0.3))

	# 派生布尔标志
	_is_exothermic  = (reaction_type == "exothermic")
	_is_endothermic = (reaction_type == "endothermic")
	_is_acid_base   = (reaction_type == "acid_base")
	_is_stochastic  = (reaction_type == "stochastic")
	_is_redox       = (reaction_type == "redox")

# ── 类型查询 ─────────────────────────────────────────────

func is_exothermic()  -> bool: return _is_exothermic
func is_endothermic() -> bool: return _is_endothermic
func is_acid_base()   -> bool: return _is_acid_base
func is_stochastic()  -> bool: return _is_stochastic
func is_redox()       -> bool: return _is_redox

# ── 条件匹配 ─────────────────────────────────────────────

# 检查双方技能是否满足这条规则的触发条件
# 同时尝试 (a→a_req, b→b_req) 和 (a→b_req, b→a_req) 两个方向（可交换）
func matches(skill_a: Skill, skill_b: Skill) -> bool:
	var a_req: Dictionary = conditions.get("a_requires", {})
	var b_req: Dictionary = conditions.get("b_requires", {})
	# 正向匹配
	if _check_single(skill_a, a_req) and _check_single(skill_b, b_req):
		return true
	# 反向匹配（双方角色可互换，但要求不对称时可在 JSON 里设 symmetric: false 禁用）
	if conditions.get("symmetric", true):
		if _check_single(skill_b, a_req) and _check_single(skill_a, b_req):
			return true
	return false

func _check_single(skill: Skill, req: Dictionary) -> bool:
	# 元素标签：技能必须包含要求的所有元素（AND 逻辑）
	for elem: String in req.get("elements", []):
		if not skill.has_element(elem):
			return false
	# 化学特性标签：技能必须包含要求的所有特性（AND 逻辑）
	for tag: String in req.get("chem_tags", []):
		if not skill.has_chem_tag(tag):
			return false
	return true

func get_summary() -> String:
	return "[%d] %s (%s)" % [priority, rule_name, reaction_type]
