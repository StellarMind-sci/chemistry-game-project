# Skill.gd
# 技能数据类：携带化学标签、能量消耗、攻击路径
# 技能是战斗中最小的"化学行为单元"
class_name Skill
extends RefCounted

var skill_name: String           # 技能名称
var element_tags: Array          # 元素标签：["H", "Cl"] / ["Cu", "O", "C"]
var chem_tags: Array             # 化学特性标签：["acidic", "oxidizing", "hydroxyl"] 等
var energy_cost: Dictionary      # 能量消耗：{"activation_energy": 20}
var base_damage: float           # 基础伤害
var attack_path: String          # 攻击路径："chemical"（精度高）或 "physical"（能耗高）
var target_site: String          # 目标部位（空字符串 = 不指定）
var description: String          # 文本描述

# ── 合法的化学特性标签常量（方便引用，防止拼写错误）──────
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

func _init(p_name: String) -> void:
	skill_name   = p_name
	element_tags = []
	chem_tags    = []
	energy_cost  = {Character.ENERGY_ACTIVATION: 10.0}
	base_damage  = 10.0
	attack_path  = "chemical"
	target_site  = ""
	description  = ""

# ── 标签查询 ─────────────────────────────────────────────

func has_element(element: String) -> bool:
	return element in element_tags

func has_chem_tag(tag: String) -> bool:
	return tag in chem_tags

func has_any_element(elements: Array) -> bool:
	for e: String in elements:
		if has_element(e):
			return true
	return false

func has_any_tag(tags: Array) -> bool:
	for t: String in tags:
		if has_chem_tag(t):
			return true
	return false

# ── 快捷判断 ─────────────────────────────────────────────

func is_acidic()    -> bool: return has_chem_tag(TAG_ACIDIC)
func is_alkaline()  -> bool: return has_chem_tag(TAG_ALKALINE)
func is_oxidizing() -> bool: return has_chem_tag(TAG_OXIDIZING)
func is_reducing()  -> bool: return has_chem_tag(TAG_REDUCING)

# ── 辅助工厂方法：快速构造常用技能 ───────────────────────

static func make_hcl_attack() -> Skill:
	var s = Skill.new("盐酸冲击")
	s.element_tags = ["H", "Cl"]
	s.chem_tags    = [TAG_ACIDIC]
	s.energy_cost  = {Character.ENERGY_ACTIVATION: 15.0}
	s.base_damage  = 25.0
	s.description  = "强酸攻击，对碱性目标效果加成"
	return s

static func make_oxidizer() -> Skill:
	var s = Skill.new("高锰酸钾氧化")
	s.element_tags = ["K", "Mn", "O"]
	s.chem_tags    = [TAG_OXIDIZING]
	s.energy_cost  = {Character.ENERGY_ACTIVATION: 25.0, Character.ENERGY_ELECTRON: 2.0}
	s.base_damage  = 35.0
	s.description  = "强氧化剂，夺取对方电子"
	return s

static func make_sodium_attack() -> Skill:
	var s = Skill.new("钠焰爆燃")
	s.element_tags = ["Na"]
	s.chem_tags    = [TAG_REDUCING, TAG_EXOTHERMIC]
	s.energy_cost  = {Character.ENERGY_ACTIVATION: 30.0}
	s.base_damage  = 50.0
	s.description  = "极强还原性，遇氧化剂爆发反应，放热升温"
	return s

func get_tag_summary() -> String:
	return "元素[%s] 特性[%s]" % [
		",".join(element_tags),
		",".join(chem_tags)
	]
