# ReactionDatabase.gd
# 反应规则数据库：从 JSON 文件加载所有规则，提供特异性优先匹配
# 规则是数据不是代码：添加新反应只需编辑 reaction_rules.json
class_name ReactionDatabase
extends RefCounted

var rules: Array = []   # Array[ReactionRule]，按 priority 降序排列

# ── 加载 ─────────────────────────────────────────────────

func load_from_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ReactionDatabase：无法打开反应规则文件 " + path)
		return false

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("ReactionDatabase：JSON 解析失败 —— " + json.get_error_message())
		return false

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ReactionDatabase：JSON 根节点必须是 Object")
		return false

	rules.clear()
	for rule_data: Dictionary in data.get("rules", []):
		var rule := ReactionRule.new()
		rule.from_dict(rule_data)
		rules.append(rule)

	# 按优先级降序排列——特异性最高的规则最先匹配
	rules.sort_custom(func(a: ReactionRule, b: ReactionRule) -> bool:
		return a.priority > b.priority
	)

	print("ReactionDatabase：已加载 %d 条反应规则" % rules.size())
	return true

# ── 查询 ─────────────────────────────────────────────────

# 返回优先级最高的匹配规则；没有匹配则返回 null（惰性反应）
func find_most_specific_match(skill_a: Skill, skill_b: Skill) -> ReactionRule:
	for rule: ReactionRule in rules:
		if rule.matches(skill_a, skill_b):
			return rule
	return null

# 返回所有匹配规则（调试 / 规则列表 UI 用）
func find_all_matches(skill_a: Skill, skill_b: Skill) -> Array:
	var result: Array = []
	for rule: ReactionRule in rules:
		if rule.matches(skill_a, skill_b):
			result.append(rule)
	return result

func get_rule_count() -> int:
	return rules.size()

func print_all_rules() -> void:
	print("=== 反应规则库（共 %d 条）===" % rules.size())
	for rule: ReactionRule in rules:
		print("  " + rule.get_summary())
