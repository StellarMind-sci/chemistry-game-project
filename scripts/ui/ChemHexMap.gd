# ChemHexMap.gd
# 化学拓扑地图渲染器（Node2D）
# 负责绘制蜂窝六边形的化学领域地图，带脉冲动画
class_name ChemHexMap
extends Node2D

# ── 领域数据 ─────────────────────────────────────────────
const DOMAINS := [
	{"name": "基础化学",  "formula": "Σ",   "color": Color(0.40, 0.70, 0.95), "active": true},
	{"name": "酸碱平衡",  "formula": "pH",  "color": Color(0.30, 0.85, 0.50), "active": true},
	{"name": "氧化还原",  "formula": "e⁻",  "color": Color(0.95, 0.50, 0.20), "active": false},
	{"name": "电化学",    "formula": "⚡",  "color": Color(0.60, 0.60, 1.00), "active": false},
	{"name": "金属配位",  "formula": "M⁺",  "color": Color(0.75, 0.45, 0.90), "active": false},
	{"name": "高分子域",  "formula": "—ₙ",  "color": Color(0.40, 0.75, 0.60), "active": false},
	{"name": "芳香有机",  "formula": "⬡",   "color": Color(0.90, 0.75, 0.25), "active": false},
]

# 蜂窝六边形偏移（尖顶朝上，以 HEX_R 为单位）
const HEX_OFFSETS := [
	Vector2( 0.000,  0.000),  # 0 中心
	Vector2( 1.732,  0.000),  # 1 右
	Vector2( 0.866,  1.500),  # 2 右下
	Vector2(-0.866,  1.500),  # 3 左下
	Vector2(-1.732,  0.000),  # 4 左
	Vector2(-0.866, -1.500),  # 5 左上
	Vector2( 0.866, -1.500),  # 6 右上
]

# 连接关系（与化学领域真实相邻关系对应）
const CONNECTIONS := [[0,1],[0,2],[0,3],[0,4],[0,5],[0,6],[1,2],[2,3],[3,4],[4,5],[5,6],[6,1]]

const HEX_R := 82.0   # 外接圆半径
var _t: float = 0.0   # 动画时间
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	# 先画连接线
	for conn in CONNECTIONS:
		var a: int = conn[0]
		var b: int = conn[1]
		var pa: Vector2 = HEX_OFFSETS[a] * HEX_R * 1.10
		var pb: Vector2 = HEX_OFFSETS[b] * HEX_R * 1.10
		var col_a: Color = ((DOMAINS[a] as Dictionary)["color"] as Color).lerp(Color.WHITE, 0.3)
		var col_b: Color = ((DOMAINS[b] as Dictionary)["color"] as Color).lerp(Color.WHITE, 0.3)
		var is_active: bool = bool((DOMAINS[a] as Dictionary)["active"]) and bool((DOMAINS[b] as Dictionary)["active"])
		var line_col: Color = col_a.lerp(col_b, 0.5)
		line_col.a = 0.55 if is_active else 0.18
		draw_line(pa, pb, line_col, 1.5)

	# 画六边形
	for i in range(7):
		_draw_hex(HEX_OFFSETS[i] * HEX_R * 1.10, i)

func _draw_hex(center: Vector2, idx: int) -> void:
	var domain: Dictionary = DOMAINS[idx] as Dictionary
	var active:  bool  = domain["active"]
	var base_col: Color = domain["color"]

	# 动画脉冲（仅活跃域）
	var pulse: float = 1.0
	if active:
		pulse = 0.90 + sin(_t * 1.6 + idx * 1.1) * 0.10

	var inner_r: float = HEX_R * 0.80 * pulse
	var fill:    Color = base_col * (0.30 if not active else 0.22 + 0.12 * pulse)
	fill.a = 1.0
	var border:  Color = base_col * (0.45 if not active else 0.85 + 0.15 * pulse)
	var txt_col: Color = Color(0.40, 0.40, 0.45) if not active else Color(0.92, 0.92, 0.96)

	# 构建六边形顶点（尖顶：起始角 90°）
	var pts := PackedVector2Array()
	for k in range(6):
		var angle: float = deg_to_rad(60.0 * k + 90.0)
		pts.append(center + Vector2(cos(angle), sin(angle)) * inner_r)

	# 填充
	draw_colored_polygon(pts, fill)

	# 边框
	var bpts := pts.duplicate()
	bpts.append(bpts[0])
	draw_polyline(bpts, border, 2.2 if active else 1.6)

	# 内圈装饰（仅活跃）
	if active:
		var ipts := PackedVector2Array()
		for k in range(6):
			var angle: float = deg_to_rad(60.0 * k + 90.0)
			ipts.append(center + Vector2(cos(angle), sin(angle)) * inner_r * 0.55)
		ipts.append(ipts[0])
		draw_polyline(ipts, border * Color(0.6, 0.6, 0.6, 0.5), 1.0)

	# 化学符号
	var fs: int = 21 if active else 17
	draw_string(_font, center + Vector2(-13, 8),
		domain["formula"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		border if active else Color(0.35, 0.35, 0.40))

	# 域名
	draw_string(_font, center + Vector2(-30, 30),
		domain["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, txt_col)

	# 锁标记（未解锁）
	if not active:
		draw_string(_font, center + Vector2(-7, -22),
			"🔒", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.40, 0.40, 0.45))
