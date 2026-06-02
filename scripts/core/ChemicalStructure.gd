# ChemicalStructure.gd
# 化学结构抽象基类：角色建模系统的核心
# Demo 阶段为骨架实现，后续 OrganicStructure / InorganicStructure 分别扩展
class_name ChemicalStructure
extends RefCounted

# 结构节点（原子、官能团、离子基团）
var nodes: Array  # Array of {"id": String, "label": String, "stability": float, "damaged": bool}
# 结构边（共价键、离子键、配位键、氢键）
var bonds: Array  # Array of {"from": String, "to": String, "type": String, "bond_energy": float, "broken": bool}

var structure_type: String  # "organic" 或 "inorganic"

func _init(p_type: String) -> void:
	structure_type = p_type
	nodes = []
	bonds = []

# ── 结构完整性 ───────────────────────────────────────────

# 计算当前结构完整性（0.0 全损 ~ 1.0 完好）
func calculate_integrity() -> float:
	if nodes.is_empty():
		return 1.0
	var total_stability    := 0.0
	var remaining_stability := 0.0
	for node: Dictionary in nodes:
		var s: float = node.get("stability", 1.0)
		total_stability += s
		if not node.get("damaged", false):
			remaining_stability += s
	if total_stability == 0.0:
		return 1.0
	return remaining_stability / total_stability

# ── 部位攻击 ─────────────────────────────────────────────

# 攻击特定节点（官能团或原子）
func attack_node(node_id: String, damage: float) -> Dictionary:
	for node: Dictionary in nodes:
		if node["id"] == node_id:
			node["stability"] = max(0.0, node.get("stability", 1.0) - damage)
			if node["stability"] <= 0.0:
				node["damaged"] = true
			return {
				"hit":       true,
				"node_id":   node_id,
				"label":     node.get("label", node_id),
				"remaining": node["stability"],
				"destroyed": node.get("damaged", false),
			}
	return {"hit": false, "node_id": node_id}

# 攻击特定键
func break_bond(from_id: String, to_id: String, damage: float) -> Dictionary:
	for bond: Dictionary in bonds:
		if (bond["from"] == from_id and bond["to"] == to_id) or \
		   (bond["from"] == to_id   and bond["to"] == from_id):
			bond["bond_energy"] = max(0.0, bond.get("bond_energy", 1.0) - damage)
			if bond["bond_energy"] <= 0.0:
				bond["broken"] = true
			return {
				"hit":     true,
				"from":    from_id,
				"to":      to_id,
				"type":    bond.get("type", "covalent"),
				"broken":  bond.get("broken", false),
			}
	return {"hit": false}

# ── 辅助查询 ─────────────────────────────────────────────

func get_damaged_nodes() -> Array:
	var result: Array = []
	for node: Dictionary in nodes:
		if node.get("damaged", false):
			result.append(node["id"])
	return result

func get_broken_bonds() -> Array:
	var result: Array = []
	for bond: Dictionary in bonds:
		if bond.get("broken", false):
			result.append("%s—%s" % [bond["from"], bond["to"]])
	return result

func get_integrity_summary() -> String:
	var integrity := calculate_integrity()
	var damaged   := get_damaged_nodes()
	var broken    := get_broken_bonds()
	return "完整性 %.0f%%  损伤节点:[%s]  断裂键:[%s]" % [
		integrity * 100.0,
		",".join(damaged) if not damaged.is_empty() else "无",
		",".join(broken)  if not broken.is_empty()  else "无",
	]

# ──────────────────────────────────────────────────────────
# OrganicStructure：有机系角色（分子结构图）
# 节点 = 原子 / 官能团；边 = 共价键
# ──────────────────────────────────────────────────────────
class OrganicStructure extends ChemicalStructure:
	func _init() -> void:
		super._init("organic")

	# 快速添加一个原子节点
	func add_atom(atom_id: String, label: String, stability: float = 1.0) -> void:
		nodes.append({
			"id":       atom_id,
			"label":    label,
			"stability": stability,
			"damaged":  false,
			"type":     "atom",
		})

	# 快速添加一个官能团节点
	func add_functional_group(fg_id: String, label: String, stability: float = 0.8) -> void:
		nodes.append({
			"id":       fg_id,
			"label":    label,
			"stability": stability,
			"damaged":  false,
			"type":     "functional_group",
		})

	# 添加共价键
	func add_covalent_bond(from_id: String, to_id: String, bond_energy: float = 1.0) -> void:
		bonds.append({
			"from":       from_id,
			"to":         to_id,
			"type":       "covalent",
			"bond_energy": bond_energy,
			"broken":     false,
		})

# ──────────────────────────────────────────────────────────
# InorganicStructure：无机系角色（组分图）
# 节点 = 阳离子 / 阴离子基团；边 = 离子键 / 配位键 / 氢键
# 能优雅处理铜绿（碱式碳酸铜）、配合物等复杂情况
# ──────────────────────────────────────────────────────────
class InorganicStructure extends ChemicalStructure:
	func _init() -> void:
		super._init("inorganic")

	func add_cation(ion_id: String, label: String, stability: float = 1.0) -> void:
		nodes.append({
			"id":       ion_id,
			"label":    label,
			"stability": stability,
			"damaged":  false,
			"type":     "cation",
		})

	func add_anion(ion_id: String, label: String, stability: float = 0.9) -> void:
		nodes.append({
			"id":       ion_id,
			"label":    label,
			"stability": stability,
			"damaged":  false,
			"type":     "anion",
		})

	func add_ligand(ligand_id: String, label: String, stability: float = 0.7) -> void:
		nodes.append({
			"id":       ligand_id,
			"label":    label,
			"stability": stability,
			"damaged":  false,
			"type":     "ligand",
		})

	func add_ionic_bond(from_id: String, to_id: String, bond_energy: float = 0.8) -> void:
		bonds.append({"from": from_id, "to": to_id, "type": "ionic",
			"bond_energy": bond_energy, "broken": false})

	func add_coordinate_bond(from_id: String, to_id: String, bond_energy: float = 0.6) -> void:
		bonds.append({"from": from_id, "to": to_id, "type": "coordinate",
			"bond_energy": bond_energy, "broken": false})
