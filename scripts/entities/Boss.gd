# Boss.gd
# Boss 角色类：在 Character 基础上添加多形态阶段系统
# 这是纯机制类——不含任何具体 Boss 的叙事/设计内容
# 具体 Boss 的创建由后续角色设计阶段完成
class_name Boss
extends Character

# ══════════════════════════════════════════════════════════
# 形态数据结构
# ══════════════════════════════════════════════════════════
class BossPhase:
	var phase_name:    String      # 形态名称（显示用）
	var hp_threshold:  float       # 低于此 HP 比例触发切换（1.01 = 初始形态）
	var actions:       Array       # 该形态的行为谱
	var phase_color:   Color       # HP 条颜色
	var entry_message: String      # 进入时战斗日志文字（留空则不显示）
	var env_on_enter:  Dictionary  # 进入时环境扰动（留空则无）

# ══════════════════════════════════════════════════════════
# 字段
# ══════════════════════════════════════════════════════════
var phases:            Array = []
var current_phase_idx: int   = 0

# 特殊胜利条件（可选）：Callable 返回 true 时触发
var special_win_condition: Callable = Callable()
var special_win_message:   String   = ""

# 记录本回合被命中的最后一个规则（供特殊胜利条件使用）
var last_hit_rule: String = ""

# ══════════════════════════════════════════════════════════
# 初始化
# ══════════════════════════════════════════════════════════
func _init(p_name: String, p_faction: String, p_max_hp: float) -> void:
	super(p_name, p_faction, p_max_hp)

# ══════════════════════════════════════════════════════════
# 形态切换（每回合伤害结算后由 BattleScene 调用）
# 返回新 BossPhase（已切换）或 null（未触发）
# ══════════════════════════════════════════════════════════
func check_and_advance_phase():
	if current_phase_idx >= phases.size() - 1:
		return null
	var next: BossPhase = phases[current_phase_idx + 1]
	if get_hp_ratio() <= next.hp_threshold:
		_enter_phase(current_phase_idx + 1)
		return next
	return null

func _enter_phase(idx: int) -> void:
	current_phase_idx = idx
	var p: BossPhase = phases[idx]
	behavior_spectrum.clear()
	standby.clear()
	sediment.clear()
	for action in p.actions:
		behavior_spectrum.append(action)
	_shuffle_array(behavior_spectrum)

func get_current_phase() -> BossPhase:
	if current_phase_idx < phases.size():
		return phases[current_phase_idx]
	return null

func get_phase_color() -> Color:
	var p := get_current_phase()
	return p.phase_color if p != null else Color(1.0, 0.5, 0.25)

# ══════════════════════════════════════════════════════════
# 工具：初始化第一个形态到行为谱（构建完 phases 后调用）
# ══════════════════════════════════════════════════════════
func init_first_phase() -> void:
	if phases.is_empty(): return
	var p: BossPhase = phases[0]
	behavior_spectrum.clear()
	for action in p.actions:
		behavior_spectrum.append(action)
	_shuffle_array(behavior_spectrum)
