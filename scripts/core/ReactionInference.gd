# ReactionInference.gd
# 化学反应推演引擎
# 职责：给定两种物质ID + 当前战场条件，推演反应结果并输出方程式
# 设计原则：设计阶段验证化学准确性，运行阶段快速查表输出结果
class_name ReactionInference
extends RefCounted

# ── 数据库引用 ───────────────────────────────────────────
var _substance_db: Dictionary = {}   # id → substance dict
var _rule_db:      Array      = []   # Array[ReactionRule]（已按优先级排序）
var _loaded:       bool       = false

# ── 推演结果数据结构 ─────────────────────────────────────
class InferenceResult:
	var matched:       bool   = false   # 是否找到匹配规则
	var rule_id:       String = ""
	var rule_name:     String = ""
	var equation:      String = ""      # 完整方程式字符串（含条件）
	var condition:     String = ""      # 反应条件（催化剂、温度等）
	var reversible:    bool   = false   # 是否可逆反应
	var product_ids:   Array  = []      # 产物物质ID列表
	var heat_type:     String = ""      # exothermic / endothermic / none
	var game_effects:  Dictionary = {}  # 直接传给战斗系统的效果字典
	var chemistry_note: String = ""     # 知识点说明

# ── 初始化 ───────────────────────────────────────────────

func load_databases(substance_path: String, rules_path: String) -> bool:
	var ok_s := _load_substances(substance_path)
	var ok_r := _load_rules(rules_path)
	_loaded = ok_s and ok_r
	if _loaded:
		print("ReactionInference：物质档案 %d 种，反应规则 %d 条" % [
			_substance_db.size(), _rule_db.size()])
	return _loaded

func _load_substances(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ReactionInference：无法打开物质档案库 " + path)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("ReactionInference：物质档案 JSON 解析失败")
		return false
	file.close()
	var data: Dictionary = json.get_data()
	for s: Dictionary in data.get("substances", []):
		_substance_db[s["id"]] = s
	return true

func _load_rules(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ReactionInference：无法打开反应规则库 " + path)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("ReactionInference：反应规则 JSON 解析失败")
		return false
	file.close()
	var data: Dictionary = json.get_data()
	_rule_db = data.get("rules", [])
	_rule_db.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)
	return true

# ── 核心推演接口 ─────────────────────────────────────────

# 主接口：给定两种物质ID，返回完整推演结果
# conditions 格式：{"temperature": 25.0, "pH": 7.0, "catalyst": ""}
func infer(substance_id_a: String, substance_id_b: String,
		conditions: Dictionary = {}) -> InferenceResult:

	var result := InferenceResult.new()

	if not _loaded:
		push_error("ReactionInference：数据库未加载")
		return result

	var sub_a: Dictionary = _substance_db.get(substance_id_a, {})
	var sub_b: Dictionary = _substance_db.get(substance_id_b, {})

	if sub_a.is_empty() or sub_b.is_empty():
		push_warning("ReactionInference：找不到物质 %s 或 %s" % [substance_id_a, substance_id_b])
		return result

	# 按优先级查找第一个匹配的规则
	var matched_rule: Dictionary = {}
	for rule: Dictionary in _rule_db:
		if _rule_matches(rule, sub_a, sub_b):
			matched_rule = rule
			break

	if matched_rule.is_empty():
		# 惰性反应兜底
		result.matched      = false
		result.equation     = "（%s 与 %s 无明显化学反应）" % [
			sub_a.get("display_name","?"), sub_b.get("display_name","?")]
		result.game_effects = {"damage_multiplier": 0.8, "status_effects": [],
							   "env_delta": {"entropy_delta": 1.0}}
		return result

	# 填充结果
	result.matched    = true
	result.rule_id    = matched_rule.get("id", "")
	result.rule_name  = matched_rule.get("name", "")
	result.game_effects = matched_rule.get("base_effect", {})

	var eq: Dictionary = matched_rule.get("equation", {})
	result.reversible  = bool(eq.get("reversible", false))
	result.condition   = str(eq.get("condition", ""))
	result.product_ids = eq.get("product_ids", [])

	# 组装完整方程式展示字符串
	var display: String = str(eq.get("display", ""))
	if result.condition != "":
		result.equation = "%s  [条件：%s]" % [display, result.condition]
	else:
		result.equation = display

	# 热效应类型
	var rtype: String = matched_rule.get("reaction_type", "generic")
	if rtype == "exothermic":
		result.heat_type = "exothermic"
	elif rtype == "endothermic":
		result.heat_type = "endothermic"
	else:
		result.heat_type = "none"

	# 知识点说明：来自规则名称 + 产物
	result.chemistry_note = _build_note(matched_rule, sub_a, sub_b)

	return result

# ── 规则匹配（支持双向） ─────────────────────────────────

func _rule_matches(rule: Dictionary, sub_a: Dictionary, sub_b: Dictionary) -> bool:
	var cond: Dictionary = rule.get("conditions", {})
	var req_a: Dictionary = cond.get("a_requires", {})
	var req_b: Dictionary = cond.get("b_requires", {})

	# 正向：a满足a_req，b满足b_req
	if _substance_satisfies(sub_a, req_a) and _substance_satisfies(sub_b, req_b):
		return true
	# 反向：b满足a_req，a满足b_req（对称规则）
	if bool(cond.get("symmetric", true)):
		if _substance_satisfies(sub_b, req_a) and _substance_satisfies(sub_a, req_b):
			return true
	return false

func _substance_satisfies(sub: Dictionary, req: Dictionary) -> bool:
	# 检查元素标签（AND）
	var elem_tags: Array = sub.get("element_tags", [])
	for elem: String in req.get("elements", []):
		if elem not in elem_tags:
			return false
	# 检查化学特性标签（AND）
	var chem_tags: Array = sub.get("chem_tags", [])
	for tag: String in req.get("chem_tags", []):
		if tag not in chem_tags:
			return false
	return true

# ── 辅助接口 ─────────────────────────────────────────────

# 查询物质档案
func get_substance(substance_id: String) -> Dictionary:
	return _substance_db.get(substance_id, {})

# 查询物质的结构节点（用于战斗的部位攻击系统）
func get_structure_nodes(substance_id: String) -> Array:
	var sub: Dictionary = _substance_db.get(substance_id, {})
	return sub.get("structure_nodes", [])

# 查询物质的化学特性标签（用于战斗的 ReactionAction 标签填充）
func get_chem_tags(substance_id: String) -> Array:
	var sub: Dictionary = _substance_db.get(substance_id, {})
	return sub.get("chem_tags", [])

func get_element_tags(substance_id: String) -> Array:
	var sub: Dictionary = _substance_db.get(substance_id, {})
	return sub.get("element_tags", [])

# 批量查找所有与某物质能发生反应的物质
func find_reactive_partners(substance_id: String) -> Array:
	var partners: Array = []
	var sub_a: Dictionary = _substance_db.get(substance_id, {})
	if sub_a.is_empty(): return partners
	for other_id: String in _substance_db:
		if other_id == substance_id: continue
		var sub_b: Dictionary = _substance_db[other_id]
		for rule: Dictionary in _rule_db:
			if rule.get("id") == "inert_fallback": continue
			if _rule_matches(rule, sub_a, sub_b):
				partners.append({
					"substance_id": other_id,
					"display_name": sub_b.get("display_name",""),
					"rule_name":    rule.get("name",""),
					"priority":     rule.get("priority", 0),
				})
				break
	partners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) > int(b["priority"]))
	return partners

# ── 从 ReactionAction 标签推演（战斗中调用） ────────────

# 战斗中不一定知道确切物质ID，可以直接用标签集合推演
# skill_tags_a / skill_tags_b 格式：{"element_tags": [...], "chem_tags": [...]}
func infer_from_tags(skill_tags_a: Dictionary, skill_tags_b: Dictionary) -> InferenceResult:
	var result := InferenceResult.new()
	if not _loaded:
		return result

	# 构造临时物质 dict 用于规则匹配
	var pseudo_a := {"element_tags": skill_tags_a.get("element_tags", []),
					 "chem_tags":    skill_tags_a.get("chem_tags",    [])}
	var pseudo_b := {"element_tags": skill_tags_b.get("element_tags", []),
					 "chem_tags":    skill_tags_b.get("chem_tags",    [])}

	for rule: Dictionary in _rule_db:
		if _rule_matches(rule, pseudo_a, pseudo_b):
			result.matched    = true
			result.rule_id    = rule.get("id", "")
			result.rule_name  = rule.get("name", "")
			result.game_effects = rule.get("base_effect", {})
			var eq: Dictionary = rule.get("equation", {})
			result.equation    = str(eq.get("display", ""))
			result.condition   = str(eq.get("condition", ""))
			result.reversible  = bool(eq.get("reversible", false))
			result.product_ids = eq.get("product_ids", [])
			var rtype: String  = rule.get("reaction_type", "generic")
			result.heat_type   = "exothermic" if rtype == "exothermic" \
								 else ("endothermic" if rtype == "endothermic" else "none")
			return result

	# 惰性兜底
	result.equation    = "（无明显化学反应）"
	result.game_effects = {"damage_multiplier": 0.8, "status_effects": [],
						   "env_delta": {"entropy_delta": 1.0}}
	return result

# ── 私有辅助 ─────────────────────────────────────────────

func _build_note(rule: Dictionary, sub_a: Dictionary, sub_b: Dictionary) -> String:
	var note: String = "【%s】%s 与 %s 发生反应" % [
		rule.get("name",""),
		sub_a.get("display_name","?"),
		sub_b.get("display_name","?"),
	]
	var eq: Dictionary = rule.get("equation", {})
	var cond: String = str(eq.get("condition",""))
	if cond != "":
		note += "（条件：%s）" % cond
	return note

func is_loaded() -> bool:
	return _loaded

func get_substance_count() -> int:
	return _substance_db.size()

func get_rule_count() -> int:
	return _rule_db.size()
