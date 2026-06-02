# ChemBattle · 化学策略战斗游戏

> 以化学为叙事语言的回合制策略战斗游戏。每个 Boss 不是"有故事的怪物"，
> 而是一个具体的人，碰巧与某种化学性质深刻绑定。

---

## 快速开始

### 环境要求
- [Godot 4.3+](https://godotengine.org/download)（Forward+ 渲染器）

### 运行原型

```bash
git clone https://github.com/<your-username>/chem_battle.git
```

1. 打开 Godot 4，选择 **Import** → 选中仓库根目录（含 `project.godot` 的那层）
2. 打开 `scenes/test/TestBattle.tscn`
3. 按 **F5** 运行，在**输出面板**查看战斗日志

---

## 项目结构

```
chem_battle/
├── project.godot              # Godot 项目配置
├── scenes/
│   └── test/
│       └── TestBattle.tscn   # 原型测试场景
├── scripts/
│   ├── core/                 # 核心数据类
│   │   ├── Character.gd
│   │   ├── Skill.gd
│   │   ├── ReactionRule.gd
│   │   ├── Environment.gd
│   │   └── ChemicalStructure.gd
│   ├── battle/               # 战斗逻辑
│   │   ├── BattleManager.gd  ← 五阶段回合循环 + 勒夏特列算法
│   │   └── ReactionDatabase.gd
│   └── test/
│       └── TestBattle.gd     # 测试入口
└── data/
    └── reactions/
        └── reaction_rules.json  ← 20 条反应规则（直接编辑可扩展）
```

---

## 战斗系统核心设计

- **双层属性系统**：元素标签（C/O/N/金属）+ 化学特性标签（酸/碱/氧化/还原/羟基）
- **反应碰撞系统**：双方技能两两配对，按特异性优先匹配规则数据库
- **勒夏特列环境反馈**：放热升温→压制放热反应；酸碱改变 pH→偏离失效；概率反应增熵→方差扩大
- **角色建模**：有机系用分子结构图，无机系用组分图（离子键 / 配位键 / 氢键）

---

## 开发进度

- [x] 核心数据结构（Character / Skill / ReactionRule / Environment）
- [x] 化学结构骨架（OrganicStructure / InorganicStructure）
- [x] 反应规则数据库（20 条，JSON 数据驱动）
- [x] 战斗管理器五阶段回合循环
- [x] 勒夏特列环境效率算法
- [ ] 对称伤害解算（双方互打）
- [ ] 最小战斗 UI
- [ ] 催化剂系统
- [ ] Boss 角色设计工具

---

## 设计哲学

> 机制即角色，规则即叙事。
> Boss 的每一条战斗规则都是这个角色人格的自然外化。
> 先有人，再有化学。

参考 Limbus Company 的"双方技能配对解算"战斗结构，
使用完整原创的化学反应系统重新设计玩法。
