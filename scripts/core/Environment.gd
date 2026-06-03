# Environment.gd
# 战场环境：承载 pH / 温度 / 熵 三个核心维度
# 注意：class_name 用 BattleEnvironment 避免与 Godot 内置 Environment 类冲突
class_name BattleEnvironment
extends RefCounted

# ── 当前值 ───────────────────────────────────────────────
var pH:          float = 7.0    # 酸碱度，0-14
var temperature: float = 25.0   # 温度（°C），-50 至 200
var entropy:     float = 30.0   # 熵，0-100

# ── 基准值 ───────────────────────────────────────────────
var baseline_pH:          float = 7.0
var baseline_temperature: float = 25.0
var baseline_entropy:     float = 30.0

# ── 数值边界 ─────────────────────────────────────────────
const PH_MIN:       float = 0.0
const PH_MAX:       float = 14.0
const TEMP_MIN:     float = -50.0
const TEMP_MAX:     float = 200.0
const ENTROPY_MIN:  float = 0.0
const ENTROPY_MAX:  float = 100.0

# ── 关键阈值 ─────────────────────────────────────────────
const ENTROPY_CHAOS_THRESHOLD: float = 70.0
const PH_EXTREME_DELTA:        float = 3.0
const TEMP_EXTREME_DELTA:      float = 30.0

# ── 更新 ─────────────────────────────────────────────────

func apply_delta(delta: Dictionary) -> Array:
	var changes: Array = []

	if delta.has("pH_delta"):
		var old_pH: float = pH
		pH = clamp(pH + float(delta["pH_delta"]), PH_MIN, PH_MAX)
		if abs(pH - old_pH) > 0.01:
			changes.append("pH %.1f → %.1f" % [old_pH, pH])

	if delta.has("temp_delta"):
		var old_t: float = temperature
		temperature = clamp(temperature + float(delta["temp_delta"]), TEMP_MIN, TEMP_MAX)
		if abs(temperature - old_t) > 0.01:
			changes.append("温度 %.0f°C → %.0f°C" % [old_t, temperature])

	if delta.has("entropy_delta"):
		var old_e: float = entropy
		entropy = clamp(entropy + float(delta["entropy_delta"]), ENTROPY_MIN, ENTROPY_MAX)
		if abs(entropy - old_e) > 0.01:
			changes.append("熵 %.0f → %.0f" % [old_e, entropy])

	return changes

# ── 状态查询 ─────────────────────────────────────────────

func is_chaos_state() -> bool:
	return entropy > ENTROPY_CHAOS_THRESHOLD

func is_extreme_pH() -> bool:
	return abs(pH - baseline_pH) > PH_EXTREME_DELTA

func is_extreme_temperature() -> bool:
	return abs(temperature - baseline_temperature) > TEMP_EXTREME_DELTA

func get_pH_zone() -> String:
	if pH < 4.0:   return "强酸性"
	if pH < 6.5:   return "弱酸性"
	if pH < 7.5:   return "中性"
	if pH < 9.5:   return "弱碱性"
	return "强碱性"

func get_temp_zone() -> String:
	if temperature < 0.0:    return "极寒"
	if temperature < 20.0:   return "低温"
	if temperature < 50.0:   return "常温"
	if temperature < 100.0:  return "高温"
	return "极高温"

func get_entropy_zone() -> String:
	if entropy < 30.0:  return "低熵"
	if entropy < 70.0:  return "正常"
	return "混乱态"

func get_summary() -> String:
	return "pH=%.1f(%s)  温度=%.0f°C(%s)  熵=%.0f(%s)" % [
		pH,          get_pH_zone(),
		temperature, get_temp_zone(),
		entropy,     get_entropy_zone(),
	]

func reset() -> void:
	pH          = baseline_pH
	temperature = baseline_temperature
	entropy     = baseline_entropy
