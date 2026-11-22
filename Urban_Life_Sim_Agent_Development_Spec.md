# 都市普通人生活模拟游戏 — AI 原生架构与编程 Agent 开发规范

> **项目代号**：Everyday City（工作名，不作为正式发行名称）  
> **文档版本**：v0.2 · 2026-11-21（AI-native 架构修订）  
> **开发引擎**：Godot 4.x（GDScript，2D，PC 优先）  
> **首发地区**：中国，虚构城市「临川市」（城市名称可配置）  
> **后续扩展**：美国、欧洲（具体国家与城市分别作为内容包）  
> **读者**：独立开发者、编程 Agent、测试 Agent、美术/叙事 Agent  
> **文档性质**：可执行的产品需求 + AI-native 技术架构 + 任务拆解 + 验收规范  
> **战略定位**：AI-native by design, offline-first by implementation（设计上原生支持 AI，当前版本不调用 LLM）  
> **重要区分**：本文中的“编程 Agent”是用于开发游戏的 Codex / Claude Code；“运行时 AI”是未来游戏内的 NPC / 叙事生成系统，当前禁止引入运行时模型成本。

## 0. 项目指令（Agent 必读）

你正在开发一款以现代城市中的普通人谋生、生活与社会关系为主题的**单机、2D、俯视角、日程驱动生活模拟游戏**。游戏的系统化日常循环借鉴生活模拟品类，叙事基调偏现实主义，与《大多数》的社会生存体验相近，但**不得复制其具体地图、角色、剧情、文本、美术、数值或 UI**。

### 不可改变的核心约束

1. **先实现中国城市纵向切片**，再添加海外城市；不得为了未来扩展延迟当前可玩性。
2. **地区差异数据驱动**：工作、工资、生活成本、货币、税费、住房、交通、社会保障、节假日、文化事件及规则必须通过地区配置和系统接口加载，禁止把 `if country == "CN"` 散落在业务逻辑中。
3. **游戏规则优先于写实模拟**：数值应可解释、可调参、可测试；不要求精确还原真实法律、税务与城市经济。
4. **单机优先、离线可玩、无账号依赖**；首期不开发联网、联机、支付或程序化生成大世界，但架构必须容纳未来 AI 生成叙事和城市内容。
5. **不做无界复杂系统**。每一阶段必须保持可运行、可测试。任务完成后提交文件清单、测试结果和未完成项。
6. 以**原创虚构城市与 NPC**为基准；中国/美国/欧洲包可以参考真实城市社会特征，但不要声称游戏数值即真实统计。
7. 未来地区扩展遵循“同一游戏内核 + 多地区规则/内容包”，而不是三套互不兼容的游戏。

### Agent 执行规则

- 不确定需求时，选择本文给定默认值并在 `docs/decisions.md` 记录；除非遇到破坏性操作、安全风险或无法继续的硬阻塞，不以提问代替实现。
- 一次只实现一个下文标有 ID 的任务或一组紧密依赖任务；不要一次性重构全部模块。
- 每完成一项功能，补充或更新**自动化测试、手动验收步骤、变更日志**。
- 不将整个游戏世界写入单例；单例仅用于会话、地区服务入口、事件总线和存档协调。
- 不引入依赖付费素材、外部 SaaS、实验性插件；必须引入第三方依赖时明确许可证。
- 不依赖生成式 AI 实时驱动 NPC；NPC 行为与事件由确定性规则/配置驱动。

---

## 1. 游戏定位

### 1.1 一句话介绍

一个来自普通家庭的年轻人，带着有限存款来到现代城市，通过找工作、租房、通勤、学习、建立关系与应对意外事件，努力让自己在城市中生活下去。

### 1.2 设计支柱

1. **生活有重量**：时间、精力、房租、通勤、突发支出构成有意义的取舍。
2. **人是具体的人**：NPC 有独立日程、职业、关系与少量连续故事，不只是商店界面。
3. **选择有后果**：超时工作能增加现金，但可能损害健康、技能成长和关系。
4. **普通人的非线性人生**：没有唯一成功路径；稳定、自由、家庭、财富、移居都可以是目标。
5. **不同城市，不同规则**：基础生活系统可重用，但国家和城市的经济制度与生活体验明显不同。

### 1.3 目标体验与非目标

**目标**：沉浸的街区探索、现实主义但不压抑到不可玩、可累积的生活进展、可组合且因果自洽的叙事、高重玩价值。  
**当前不实现**：多人联机、赛车/战斗系统、完整房地产市场、真实股市投资、运行时大语言模型、完整全球地图、复杂法律模拟、真实金融服务接入。**长期愿景明确包含 AI 原生 NPC 与 AI 生成剧情**，而非永久排除。

### 1.4 玩家身份

- 支持自定义姓名、外观、代词/称谓（内容文本须支持本地化模板）；默认背景：刚来到城市、学历与初始经历可在后期开放选择。
- 首个切片统一初始条件，避免设计和测试组合爆炸。
- 玩家并非预设男性或女性；不要把剧情与职业机会无必要地绑定性别。

---

## 2. 跨地区基座设计

### 2.1 分层架构（目标架构，不代表首版必须全部实现）

```text
┌─────────────────────────────────────────────────────────────────┐
│ Godot Presentation  2D 世界 / UI / 玩家输入 / 音效 / 对话呈现     │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Commands / Queries / Views
┌──────────────────────────────▼──────────────────────────────────┐
│ Application Orchestrator  命令验证、事务、时间推进、调度、发布事件 │
├─────────────────────────────────────────────────────────────────┤
│ Authoritative Simulation Kernel  世界真相 + 行动后果 + 状态迁移  │
│ 人物/需求/经济/就业/住房/关系/社会图谱/事件账本/日程              │
├──────────────────────┬──────────────────────┬───────────────────┤
│ Region Policies      │ NPC Decision Policy  │ Narrative Runtime │
│ CN/US/DE/PL ...      │ 当前规则/效用决策     │ 故事提案/校验/执行 │
│                     │ 未来可选 LLM 实现     │ 未来可选 LLM 生成  │
├──────────────────────┴──────────────────────┴───────────────────┤
│ Content & World Packs 城市、职业、地点、NPC 模板、故事片段、文案 │
├─────────────────────────────────────────────────────────────────┤
│ Persistence / Replay / Schema / Seeded RNG / Localization       │
└─────────────────────────────────────────────────────────────────┘
```

**边界规则**：

- 唯一权威写入口为 `CommandProcessor.apply(command)`；所有游戏行为（包括未来 LLM 提案）必须经过验证和结算。
- UI、剧情运行时、NPC 决策器都**不能直接写**玩家钱包、NPC 雇佣关系、城市状态。
- 模拟内核暴露稳定的 **Queries / Observation** 只读视图，避免未来 AI 必须依赖 Godot 节点树。
- `RegionPolicy` 规定如何结算；`ContentPack` 规定有哪些地点、人物和任务；`NarrativePolicy` 决定提出哪些故事候选；`NPCDecisionPolicy` 决定 NPC 想执行什么行动。
- 当前的 NPC 与剧情 `Policy` 由规则/模板实现；将来模型实现相同的协议，运行时可以逐角色、逐任务切换而不破坏存档。
- Godot 负责展示和输入，不承担社会世界唯一真相；内核优先使用可 Headless 测试的 `RefCounted` / 纯数据结构。

**非目标**：首版不做分布式 ECS、微服务、向量数据库或联网 AI；这些技术不会自动提高游戏自由度。

### 2.2 地理层级

```text
World
 ├── Region: CN
 │    └── City: CN_LINCHUAN
 │          ├── District: OLD_TOWN
 │          └── District: INDUSTRIAL
 ├── Region: US (后续)
 │    └── City: US_SAMPLE_CITY (后续)
 └── Region: EU (仅作为地区组，不直接当国家)
      ├── Country: DE / FR / PL ... (后续分别建包)
      └── City: ...
```

> **注意**：“欧洲”不是单一法律/经济体。以后要使用 `country_id`（如 `DE`, `FR`, `PL`）与 `currency_code`（如 `EUR`, `PLN`），避免将欧洲统一视作欧元区。

### 2.3 地区规则接口（建议）

```gdscript
# scripts/regions/region_policy.gd
class_name RegionPolicy
extends RefCounted

func get_currency_code() -> String:
    return ""

func calculate_take_home_pay(gross_minor: int, context: Dictionary) -> int:
    return gross_minor

func calculate_recurring_cost(kind: String, base_minor: int, context: Dictionary) -> int:
    return base_minor

func validate_work_shift(job: Dictionary, shift_minutes: int, context: Dictionary) -> bool:
    return true

func get_calendar_modifiers(date_key: String) -> Dictionary:
    return {}
```

- 初期由 `ChinaRegionPolicy` 实现简单、**明确标注为游戏化**的工资扣减与日常开销。
- 美国与欧洲国家扩展时，各自实现规则或由配置装配规则策略；不得修改 `WorkSystem` 的基本接口。
- **货币采用最小单位整数**：如人民币分、美元分、欧元分；界面负责货币格式化。任何地区都不要使用浮点数直接累计金额。
- 所有时间结算使用游戏内时间；现实系统时间只用于日志/存档元信息。

### 2.4 内容包文件结构（建议）

```text
res://content/
  common/
    items.json
    needs.json
    localization/
      zh_CN.csv
      en_US.csv
  regions/
    cn/
      region.json
      policy_config.json
      cities/
        linchuan/
          city.json
          jobs.json
          housing.json
          shops.json
          npcs.json
          events.json
          dialogue.json
          maps/
    us/                  # 只保留 README，不加载占位内容
    eu/                  # 只保留 README，具体国家以后单独建包
```

`ContentRegistry` 需要完成 JSON Schema 等价的运行时字段校验、引用完整性校验、重复 ID 检测和错误定位。数据加载失败时给出带文件路径的错误，不静默跳过。

### 2.5 示例配置（字段用于第一个切片，实际数值可调）

```json
{
  "schema_version": 1,
  "id": "CN_LINCHUAN",
  "region_id": "CN",
  "country_id": "CN",
  "display_name_key": "city.cn_linchuan.name",
  "currency_code": "CNY",
  "language": "zh_CN",
  "starting_money_minor": 150000,
  "starting_day": 1,
  "starting_hour": 8,
  "default_spawn": "old_town_bus_stop",
  "district_ids": ["OLD_TOWN", "INDUSTRIAL"]
}
```

以上 `150000` 代表 ¥1,500.00；这是一项**游戏平衡参数**，不代表真实收入水平。

### 2.6 统一实体与跨文件 ID 规则

- ID 采用稳定的 `snake_case`，例如 `job_convenience_clerk`、`npc_chen_yu`、`home_shared_room_01`；存档使用 ID 而非数组下标引用。
- 配置的 `schema_version` 必填。破坏式变更需增加版本、增加迁移脚本和存档迁移测试。
- 地区专属内容引用必须显式声明 `city_id` 或 `region_id`；通用物品可放 `common`。
- 文案使用 `text_key`；游戏逻辑不得根据显示文本进行分支。

---

## 3. 首个可玩版本：MVP（中国城市）

### 3.1 地图范围

**只制作一张小型、连续可步行的城市街区地图**，包括以下地点：

| 地点 | 最低功能 |
|---|---|
| 公交站 | 玩家首次进入的出生点、教程标识 |
| 廉价出租屋 | 睡眠、恢复精力、查看账单、存档 |
| 便利店 | 购买食物、兼职岗位 |
| 快餐店 | 购买餐食、可选兼职岗位 |
| 招聘公告栏/求职站 | 查看岗位、申请、排班 |
| 公园 | 免费休息、触发基础 NPC 事件 |
| 公交站牌 | 前往“工业区”抽象工作地点，按时间和票价结算 |

首版不要开发真正的大地图流式加载或复杂交通寻路。工业区可以是**单独的小室内/工作场景**，通过公交交互转场。

### 3.2 首版核心系统与范围

| 系统 | MVP 内容 | 非 MVP |
|---|---|---|
| 时间 | 1 天 24 小时；地图内固定速率、活动按分钟快进 | 四季天气、完整农历 |
| 基础需求 | 饥饿、精力、压力（0–100） | 复杂疾病、情绪诊断 |
| 经济 | 钱包、消费、工资、房租、每日账单 | 贷款、金融投资 |
| 工作 | 3 类工作、定时排班、工资结算 | 自由创业、复杂升迁 |
| 住房 | 1 间可租住房、租金到期提示 | 买房、装修、合租 AI |
| 购物 | 3 种消耗品、库存与使用 | 供应链、品牌系统 |
| NPC | 3 个命名 NPC、地点日程、基础关系 | 大量程序化 NPC |
| 剧情 | 开场 + 3 个可验证的故事片段 + 1 个状态驱动总结 | 大模型运行时生成长篇剧情 |
| 存档 | 单槽或多槽，至少支持手动存读 | 云同步、跨设备 |
| UI | 时间、金钱、需求、任务、背包、对话、菜单 | 手柄完整适配 |

**工作类型建议**：便利店店员、餐饮服务员、仓储分拣员。它们在报酬、体力消耗、排班及通勤上形成简单取舍。

### 3.3 一轮游戏循环

```text
起床 → 查看预算/任务 → 吃饭或购物 → 通勤
     → 工作赚取收入 → 消耗精力/时间 → 返家
     → 社交/休息/学习（学习首版可做事件/占位交互）
     → 睡觉 → 进入下一天 → 房租及事件检查
```

**第一阶段游戏目标**：在 7 个游戏日内支付首次租金、完成至少 2 次工作班次，并与至少 1 名 NPC 建立初步关系。允许玩家失败、重新开始或继续游玩，不强制 Game Over。

### 3.4 初始调参表（仅游戏化数值，不是真实城市统计）

| 项目 | 初始参数 |
|---|---:|
| 初始现金 | ¥1,500 |
| 房租 | ¥600 / 7 游戏日 |
| 便利店工资 | ¥22 / 游戏小时 |
| 餐饮服务工资 | ¥25 / 游戏小时 |
| 仓储分拣工资 | ¥32 / 游戏小时 |
| 便利店班次 | 4 小时 |
| 餐饮班次 | 4 小时 |
| 仓储班次 | 5 小时 |
| 公交单程 | ¥3、30 游戏分钟 |
| 简餐 | ¥18，饥饿 -35 |
| 速食 | ¥8，饥饿 -15 |
| 饮料 | ¥5，压力 -3 |
| 睡眠 | 8 游戏小时，精力恢复至最多 90 |

**数值约定**：饥饿 100 = 极饿，精力 100 = 充沛，压力 100 = 压力极高。属性范围始终 `0..100`。初始值建议：饥饿 25、精力 80、压力 20。

### 3.5 时间推进语义

- `GameClock` 是唯一的权威游戏时间源，内部存储自游戏开始以来的**整数分钟**。
- 探索场景按可配置倍率推进；对话、暂停菜单与存档界面暂停时间。
- “工作 4 小时”“乘车 30 分钟”“睡眠 8 小时”通过统一的 `advance_minutes(n)` 快进。
- 统一触发 `time_advanced`、`day_changed`；跨多日快进时逐日进行账单及事件结算，不能跳过中间日期。
- 为避免离线/帧率差异，日结算只依赖游戏时间和显式行动，不依赖现实时间戳。

### 3.6 经济事务规则

- 所有金钱更改必须经过 `EconomyService.try_debit()` / `credit()`；不存在 UI 直接修改余额。
- 一次成功工资结算必须原子式记录交易，确保同班次不会重复支付。
- 负余额默认禁止；房租不足时记录欠租状态，延迟后触发剧情/提醒，**不自动扣出负数**。
- 每笔交易附带 `transaction_id`、`timestamp_game_minute`、`reason`、`amount_minor`、`currency_code`。

---

## 4. 核心代码结构

```text
res://
  project.godot
  scenes/
    boot/boot.tscn
    world/city_world.tscn
    world/player.tscn
    interiors/home.tscn
    interiors/convenience_store.tscn
    interiors/restaurant.tscn
    ui/hud.tscn
    ui/job_board.tscn
    ui/inventory.tscn
    ui/dialogue.tscn
    ui/pause_menu.tscn
  scripts/
    app/game_session.gd
    app/game_event_bus.gd
    content/content_registry.gd
    regions/region_policy.gd
    regions/china_region_policy.gd
    simulation/game_clock.gd
    simulation/needs_system.gd
    simulation/economy_service.gd
    simulation/work_system.gd
    simulation/housing_system.gd
    simulation/inventory_system.gd
    simulation/relationship_system.gd
    simulation/event_system.gd
    simulation/npc_schedule_system.gd
    kernel/world_state.gd
    kernel/command_processor.gd
    kernel/domain_event.gd
    kernel/observation_service.gd
    kernel/seeded_rng.gd
    kernel/simulation_tiers.gd
    intelligence/npc_decision_policy.gd
    intelligence/rule_based_npc_policy.gd
    narrative/story_proposal.gd
    narrative/story_validator.gd
    narrative/story_scheduler.gd
    narrative/story_runtime.gd
    narrative/template_story_provider.gd
    world/player_controller.gd
    world/interactable.gd
    persistence/save_manager.gd
    persistence/save_migrations.gd
    ui/... 
  content/...
  tests/
    test_clock.gd
    test_economy.gd
    test_job_pay.gd
    test_rent.gd
    test_save_roundtrip.gd
    test_content_integrity.gd
    test_command_atomicity.gd
    test_deterministic_replay.gd
    test_story_validation.gd
    test_story_no_direct_mutation.gd
  docs/
    decisions.md
    changelog.md
    agent_progress.md
```

### 4.1 系统所有权

| 系统 | 独占责任 | 不允许承担 |
|---|---|---|
| `GameClock` | 时间与天数事件 | 钱包/需求改值 |
| `NeedsSystem` | 需求值及随时间变化 | UI 绘制 |
| `EconomyService` | 收支/流水 | 判断 NPC 台词 |
| `WorkSystem` | 岗位申请、班次、工资请求 | 货币格式 |
| `HousingSystem` | 租约、租金到期、欠租 | 改变玩家坐标 |
| `RelationshipSystem` | 关系分数、互动冷却 | 剧情硬编码 |
| `EventSystem` | 条件检测、事件触发、后果 | 直接加载场景资源 |
| `ContentRegistry` | 数据加载、验证、查表 | 运行时经济结算 |
| `SaveManager` | 序列化、迁移、原子落盘 | 游戏经济规则 |
| `CommandProcessor` | 命令权限、前置条件、事务性结算、事件输出 | 生成剧情文本 |
| `ObservationService` | 针对人物/故事返回可见的事实快照 | 暴露所有角色的隐藏信息 |
| `NPCDecisionPolicy` | 按观察、目标与预算提出 NPC 行动 | 直接修改世界状态 |
| `StoryValidator` | 对剧情提案进行 Schema、因果、授权和可执行性检查 | 自动接受任意生成内容 |
| `NarrativeDirector` | 在有效候选中控制节奏、优先级和多样性 | 强制推翻玩家选择 |

### 4.2 信号与命令

建议使用稳定的信号/事件：

```text
time_advanced(old_minute, new_minute)
day_changed(day_index)
wallet_changed(balance_minor)
need_changed(need_id, new_value)
job_shift_completed(shift_id, gross_minor, net_minor)
rent_due(contract_id, due_minor)
relationship_changed(npc_id, value)
event_started(event_id)
event_completed(event_id)
save_completed(slot_id)
```

可交互对象发起**请求/命令**，由领域系统决定是否成功并返回结果。UI 根据结果展示反馈，不能成为游戏规则的唯一执行位置。

**关键：Signals 是通知通道，不是事实来源。** 需要持久化/回放的变更应形成具备 `event_id`、`game_minute`、`actor_id`、`cause_id` 和 `payload` 的 `DomainEvent`；Signals 可作为事件发生后 UI 的轻量订阅接口。

### 4.3 NPC 与事件格式

```json
{
  "id": "npc_chen_yu",
  "city_id": "CN_LINCHUAN",
  "name_key": "npc.chen_yu.name",
  "home_location_id": "old_town_apartment",
  "schedule": [
    {"start_minute_of_day": 480, "end_minute_of_day": 720, "location_id": "convenience_store"},
    {"start_minute_of_day": 720, "end_minute_of_day": 1080, "location_id": "park"}
  ],
  "initial_relationship": 0,
  "dialogue_tree_id": "dialogue_chen_yu_intro"
}
```

```json
{
  "id": "event_first_rent",
  "city_id": "CN_LINCHUAN",
  "priority": 10,
  "once": true,
  "conditions": [
    {"type": "day_at_least", "value": 6},
    {"type": "flag_equals", "key": "housing_contract_signed", "value": true}
  ],
  "effects": [
    {"type": "set_flag", "key": "rent_reminder_seen", "value": true}
  ],
  "dialogue_tree_id": "dialogue_rent_reminder"
}
```

**事件解释器白名单（兼容旧版简化事件）**：首版只支持 `day_at_least`、`wallet_at_least`、`need_above`、`relationship_at_least`、`flag_equals` 条件，及 `set_flag`、`credit_money`、`debit_money`、`change_need`、`change_relationship` 后果。未知类型必须报错，不执行配置字符串中的代码。

### 4.4 存档规范

- 使用 `user://saves/slot_XX.json`，采用**临时文件 + 验证 + 替换**方式写入，避免写一半损坏旧档。
- 存档必须保存：`save_schema_version`、`game_version`、`region_id`、`city_id`、`player`、`clock_minute`、`wallet`、`ledger`（可裁剪）、`needs`、`inventory`、`jobs`、`housing`、`relationships`、`flags`、`rng_seed/state`、`scene_id` 和 `spawn_id`。
- 存档加载后必须校验城市包存在、ID 可解析、属性上下界和货币代码一致。
- 不反序列化任意对象，不执行存档携带的脚本。
- 扩展地区不应导致中国旧存档失效；字段升级由 `SaveMigrations` 显式处理。

---

## 5. 剧情规格：偏社会现实主义

### 5.1 叙事基调

- 不将贫困当作笑料，也不把努力简化为必然成功。
- 展现工作不稳定、生活成本、代际差异、同事关系、选择与偶然性。
- 让 NPC 有自己的能动性；避免所有人物围绕玩家的成功展开。
- 倾向细节叙事（房租账单、夜班回家、同事的请求），而不是堆砌宏大说教。

### 5.2 首版七日故事（可脚本化测试）

| 游戏日 | 触发内容 | 玩家决策/后果 |
|---|---|---|
| Day 1 | 抵达城市；房东介绍住处；领取租房任务 | 租房后开启床与存档 |
| Day 2 | 便利店 NPC 介绍兼职；解锁求职 | 可申请第一个班次 |
| Day 3 | 同事邀请吃饭 | 花钱改善关系，或节省开销 |
| Day 4–5 | 仓储岗开放；更高收入但更耗精力且需通勤 | 选择收入/身体/时间 |
| Day 6 | 房租提醒 | 预算与压力的反馈 |
| Day 7 | 交租与生活阶段总结 | 根据余额、关系、工作、压力生成不同总结文本 |

**阶段总结不是胜负判定**：例：“交了房租但几乎没有存款”“收入不错但很少有时间休息”“认识了第一个可以说话的朋友”。将结局写成条件驱动内容，不在 UI 脚本里硬编码。

### 5.3 剧情扩展接口

每个内容包提供 `event_id`、`conditions`、`effects`、`dialogue_tree_id`、`localization_keys`。首版只做单层选择对话，后续能通过内容驱动扩展分支，不改变对话 UI 的核心 API。

---

## 6. UI / UX 最低要求

**屏幕目标**：1920×1080 设计参考，同时可缩放至 1280×720；Godot UI 使用 anchors/containers，避免硬编码位置导致较小分辨率溢出。

- HUD 左上：日期、游戏时间；右上：当前金钱。
- HUD 下部/侧边：饥饿、精力、压力简明条。
- 交互提示：靠近目标时出现 `[E] 交互`；`WASD` 移动，`Esc` 菜单，`I` 背包，`J` 任务。
- 对话：可显示角色名、文本、1–3 个选项，鼠标/键盘均可操作。
- 商店：物品名称、金额、持有现金、购买后变化；余额不足有可理解提示。
- 求职：工作时间、预估净收入、精力消耗、通勤代价、可申请状态。
- 设置：音量、分辨率/窗口模式、语言（简中首发；字符串架构支持英文）。
- 不得仅用颜色传达经济/需求状态；需同时显示图标或文字数值。

### 美术边界

- 优先使用**统一尺寸的占位像素图形**和基础色块完成玩法，不在首个工程阶段制作正式资源。
- 预设 16×16 或 32×32 tile 规格，统一像素对齐、相机缩放与碰撞体大小。
- 初期角色只要求 4 向移动、待机、交互；不要求丰富动画。
- 无版权保障的素材一律不直接合入项目。

---

## 7. 里程碑、开发顺序与 Agent 任务卡

**定义**：每个任务完成必须满足以下四项：
1. 功能可在 Godot 运行；2. 相应自动化测试通过；3. 无新增报错；4. 更新 `docs/agent_progress.md`。

### M0 — 空工程及可测试架构

- **T001 初始化项目**：创建 Godot 4.x 工程、文件目录、入口场景、输入映射、基础 UI 主题、`.gitignore`、README。  
  **验收**：项目可使用编辑器启动，空场景无红色错误。
- **T002 内容包注册器**：支持读取 city/region JSON、ID 查询和配置完整性验证，并保留故事提供者 `provider_id` / `schema_version` 元数据。  
  **验收**：缺少必需字段/重复 ID/无效引用均以可定位错误失败；正确配置加载成功。
- **T003 游戏时间**：实现权威分钟计数、日更、暂停与动作快进。  
  **验收**：23:50 快进 30 分钟得到下一天 00:20；跨 2 天不会漏 `day_changed`。
- **T004 地区策略接口**：注册中国规则实现；可通过 registry 选择 city 对应 policy。  
  **验收**：切换测试中的伪地区规则，不需修改 `WorkSystem`。

### M1 — 最小可游玩城市

- **T005 城市与玩家**：基础 tile 地图、玩家 4 向移动、Camera2D、碰撞、交互范围。  
  **验收**：玩家不能穿墙，能靠近并触发标识牌。
- **T006 HUD**：显示游戏时间、现金、三个需求指标；可暂停。  
  **验收**：游戏状态变化能实时同步到界面。
- **T007 经济与商店**：实现钱包、流水、支付失败反馈、三种商品、背包与消耗。  
  **验收**：¥20 购买 ¥18 简餐后余额 ¥2；再次购买失败且无负数。
- **T008 需求与睡眠**：推进时间时变化、吃饭降低饥饿、睡眠恢复精力。  
  **验收**：需求钳制到 0–100；睡眠推动日期并触发跨日事件。

### M2 — 谋生循环

- **T009 工作公告栏**：三种岗位数据配置、查看岗位与申请班次。  
  **验收**：岗位及条件完全由 JSON 加载。
- **T010 工作结算**：时间推进、需求消耗、工资入账、交易流水与重复支付保护。  
  **验收**：同一 `shift_id` 只支付一次；工资由 region policy 计算。
- **T011 房租与账单**：建立租约、到期提醒、扣款或欠租状态。  
  **验收**：跨多天快进不会漏账单；扣款不会重复。
- **T012 通勤**：公交转场、消耗票价与游戏时间，失败给出反馈。  
  **验收**：余额不足不能乘车；乘车后时间与目的地正确。

### M3 — 人物与故事

- **T013 NPC 日程**：三人根据游戏时段出现在指定地点；无寻路需求，采用地点锚点切换。  
  **验收**：时间变化后 NPC 所在地点正确；场景切换重新进入仍正确。
- **T014 关系与对话**：选择分支、关系增减、互动冷却、文案本地化键。  
  **验收**：相同可重复对话不会无限刷好感。
- **T015 七日事件**：实现剧情条件与后果解释器、优先级、仅一次触发机制；提供 `StoryValidator` 最小可用实现，拒绝未知后果、无效实体与越权状态修改。  
  **验收**：Day 7 总结根据真实游戏状态呈现至少 3 种变体；一次性事件不重复触发。
- **T016 教程与指引**：抵达城市→租房→找工→吃饭→交租的可追踪任务。  
  **验收**：新玩家不看外部说明也能完成首个工作班次。

### M4 — 稳定性与交付

- **T017 存读档**：存取当前地图/钱包/时间/NPC/工作/房租/事件状态，校验与迁移。  
  **验收**：存档前后状态一致；坏档可报错，不覆盖可用旧档。
- **T018 平衡测试**：脚本模拟七日经济与需求；根据输出调整参数，留下变更说明。  
  **验收**：至少一种合理路线可交房租，至少一种过度消费路线会触发经济压力；不存在必败局面。
- **T019 设置与适配**：音量、窗口尺寸、简中资源、英文接口占位。  
  **验收**：1280×720 和 1920×1080 下关键界面不截断。
- **T020 发布构建**：Windows + Linux 桌面发行包及 README。  
  **验收**：全新机器环境下启动不需要编辑器和外部在线服务。

> **每个任务均为独立完成单位**。不要在 T003 阶段预先实现 T010，也不要用空函数假装任务完成。测试框架可以选择 Godot 原生 headless test runner 或许可证允许且已固定版本的测试插件。

---

## 8. 自动化测试规范

测试以**核心规则不依赖场景树**为目标，UI 用可重复的手动验收覆盖。

### 8.1 必须实现的单元测试

1. `ClockRollOver`: 跨午夜与跨多日事件触发次数正确。
2. `MoneyInteger`: 金钱的最小单位整数运算无浮点误差。
3. `InsufficientFunds`: 余额不足的购买/交通失败不影响余额和背包。
4. `PayIdempotency`: 同一班次工资只结算一次。
5. `RegionPolicySwap`: 使用测试策略替代中国策略后，工资净额变化但工作流程不变。
6. `RentDue`: 租金按期结算，欠租不产生负余额，重复加载不重复扣款。
7. `NeedBounds`: 任意需求值更新都保持在 0–100。
8. `EventOnce`: `once` 事件不可重复触发，跨存档仍成立。
9. `SaveRoundTrip`: 对含工资/关系/房租状态的存档序列化并恢复，全字段一致。
10. `ContentValidation`: 未定义 NPC / 工作地点 / 对话 ID 的引用应立即报错。

### 8.2 手动端到端验收脚本

```text
A. 新建游戏 → 出现在公交站 → 可以移动与交互
B. 找到出租屋 → 签约/完成教程 → 睡觉可推进到下一天
C. 到便利店购买食物 → 钱包减少 → 背包增加 → 食用后饥饿下降
D. 在招聘栏领取班次 → 完成班次 → 工资入账且只入账一次
E. 和 NPC 交流 → 关系改变 → 对话反馈正确
F. 跨入 Day 6 → 房租提醒出现；Day 7 结算后得到阶段总结
G. 保存 → 退出游戏 → 重新启动并加载 → 状态与位置保持一致
H. 在 1280×720 分辨率复做关键 UI 操作，无控件不可点击
```

### 8.3 运行命令模板

```bash
# 以下为示意；Agent 应按项目实际 Godot 执行路径及测试框架补齐
 godot --headless --path . --editor --quit
 godot --headless --path . --quit-after 10
```

禁止只提交“理论上应该能运行”的结果；如果当前 Agent 环境没有 Godot 可执行文件，必须明确写下**未实际运行**，不得假报通过。

---

## 9. 后续国际城市扩展规范（不属于中国 MVP）

### 9.1 必须提前预留，暂不实现

| 维度 | 中国初始实现 | 美国扩展方向 | 欧洲扩展方向 |
|---|---|---|---|
| 货币 | CNY | USD | 按国家区分 EUR/PLN 等 |
| 工资税费 | 游戏化扣减策略 | 州/联邦等抽象策略 | 各国不同策略 |
| 医疗支出 | 简化随机事件 | 保险/自费抽象模型 | 各国社会医疗政策模型 |
| 住房 | 租金/押金基础模型 | 信用、租约条款可扩展 | 不同国家押金/租赁机制 |
| 交通 | 公交/步行 | 私家车/公共交通后续可选 | 地铁/公交/铁路后续可选 |
| 就业 | 兼职/合同工抽象 | 工作资格、福利等事件 | 各国劳动和福利规则 |
| 文化 | 中文、城市邻里关系 | 英文、各地生活事件 | 按国家语言与文化内容独立扩展 |

这张表仅用于**软件架构预留**，不作为实际政策陈述；任何正式内容包须单独研究其时代、国家/州/城市的具体设定。

### 9.2 扩展一个新城市的验收门槛

1. 创建独立内容包与 `RegionPolicy` 配置/实现。
2. 最少添加一个新地图、三份职业数据、至少两名本地 NPC 与一个地区特有事件。
3. 旧中国存档无需迁移核心游戏规则即可读取。
4. 所有核心规则测试在中国与新增地区均通过。
5. 核心系统源代码无需因为新增城市而出现新城市 ID 的硬编码分支。

### 9.3 长期机制（仅设计方向）

- 职业成长/学习及资格认证；社会阶层变动与风险。
- 多人群叙事与社交网络，租房升级、搬迁和地区转移。
- 国家间迁居（需独立设计签证/工作资格规则，避免一键跨国）。
- 公共服务与制度差异、城市景气波动、重复游玩事件池。
- 这些机制均不得先于 MVP 稳定性完成。

---

## 10. 交付物清单

- 可通过 Godot 4.x 打开的项目源码。
- `README.md`：运行方式、操作说明、架构总览、版本与许可证。
- `docs/decisions.md`：重要架构决策、替代方案与原因。
- `docs/agent_progress.md`：每个任务状态、变更文件、测试命令、结果、下一项。
- `docs/changelog.md`：玩家可感知的变更记录。
- `content/`：中国地图、岗位、NPC、事件、地区规则配置。
- `tests/`：核心规则自动测试与手动验收清单。
- Windows/Linux 可执行构建（最后一个里程碑）。

### 定义可交付（Definition of Done）

- 玩家能够从 Day 1 连续游玩到 Day 7，没有阻断流程的 bug。
- 找工作、赚工资、购物、租房、需求管理、NPC 关系、阶段总结全部形成闭环。
- 所有配置引用通过验证；所有核心测试通过；关键 UI 有手动验收记录。
- 至少一次完整的存档退出再加载恢复测试通过。
- 不依赖互联网，不使用未授权版权素材。
- 中国地区内容与核心模拟模块已清晰分离，并通过地区规则替换测试。

---

## 11. 直接交给编程 Agent 的启动提示词

> 将下面整段作为 Codex / Claude Code / 其他编程 Agent 的第一条任务说明，并将本文放入仓库 `docs/PRODUCT_SPEC.md`。

```text
你是该 Godot 4.x 独立游戏项目的主程。请先完整阅读 docs/PRODUCT_SPEC.md。

目标：实现一款以中国现代虚构城市为首发场景、未来可扩展美国及欧洲各国城市的现实主义 2D 单机生活模拟游戏。

请严格按文档 M0→M4 的 T001–T020 顺序实施。当前只执行 T001，然后停止并报告。

要求：
1. 对照本规范实现，不自行扩展无关功能。
2. 中文沟通；类名/方法/文件名使用清晰英文。
3. 使用 Godot 4.x + GDScript，先做占位图形，无需最终美术。
4. 必须保留地区规则、内容包、核心模拟、UI 和存档的分层边界。
5. 新增代码尽可能可测试，完成任务时实际运行可用的测试或启动验证。
6. 每次报告：已完成、变更文件、运行/测试命令和真实结果、风险、下一任务。
7. 将完成状态写入 docs/agent_progress.md，重要选择写入 docs/decisions.md。
8. 如本机无法执行 Godot，明确说明且不要声称验证通过。
9. 未经要求不接入联网/付费 SDK，不复制其他商业游戏素材。

现在执行 T001：项目初始化与可启动空场景；完成后结束本次任务。
```

---

## 12. 技术北极星与不可妥协的架构原则（v0.2 新增）

### 12.1 北极星：AI 原生社会叙事模拟（不是 AI 聊天 NPC）

玩家进入一个独立运转的现代城市。NPC 有自己的职业、资源、日程、关系和目标；失业、晋升、冲突、租房、迁居可以先于剧情产生。**叙事层发现这些事实，提出可执行的故事；未来的生成式模型可以替换故事提案者和 NPC 决策者。**

- **现在（无 LLM）**：原创手写 Storylets + 条件组合器 + 规则 NPC 策略 + 事件驱动的动态叙事调度器。无网络和推理成本。
- **将来（AI 原生）**：LLM 可参与 NPC 长期目标制定、故事大纲构思、对白创作、支线生成、城市内容制作，前提是通过安全、稳定的接口；离线规则模式始终可运行。
- **不是目标**：让每个 NPC 每帧发起一次模型请求、让大模型直接维护世界真相、将任意自然语言即时解释为可执行代码、生成无限制永久生效的内容。

**SOTA 是研究方向和产品目标，而非已经取得的性能保证。** 当前版本优先构筑有竞争力的结构：可验证、可扩展、可复现、用户自由度高、性能可控。

### 12.2 核心架构原则（ADR 候选）

| 原则 | 强制规则 | 反例（禁止） |
|---|---|---|
| 权威世界状态 | 只有 CommandProcessor 能提交事实变更 | 剧情直接执行 `wallet += 1000` |
| 事实与认知分离 | NPC 只读取可感知的观察和私人记忆 | 每个 NPC 都知道玩家所有隐藏数值 |
| 决策与执行分离 | NPC/LLM 提交 `ActionProposal`，规则校验后执行 | LLM 直接移动 NPC 或发钱 |
| 故事与世界分离 | 叙事是对世界事实的解释、选择和合法变化 | 文案声称角色死亡而世界状态仍存活 |
| 可复现与可测试 | 固定 RNG 种子、稳定调度顺序、命令日志 | 任何脚本直接调用全局随机函数影响结算 |
| 分层模拟 | 少数关键人物精算、其余居民低频抽象 | 全城 10 万 NPC 每帧路径规划 |
| 地区扩展 | RegionPolicy + 城市数据包 + 本地化 | 到处硬编码 `if country == ...` |
| 模型可更换 | 模型只实现 Provider/Policy 协议 | 引擎依赖某厂商固定 JSON 响应 |
| 离线保障 | 任何模型故障自动回退规则方案 | 无网络时游戏世界停止 |
| 安全与来源 | 所有生成内容通过结构和事实验证 | 执行 AI 生成的脚本或任意资源路径 |

---

## 13. 权威社会模拟内核（AI 接入前必须稳定）

### 13.1 WorldState / Commands / Events / Observations

```text
Player / NPC / Simulation Schedule / Narrative Director
                        |
                 ActionProposal
                        |
                 CommandProcessor
           validate → apply → emit
                /               \
         WorldState          DomainEvent Log
                \               /
          Save / Replay / Projections
                        |
           ObservationService / Views
```

**`WorldState`**：持久性事实，包括角色、位置、金钱、合同、工作、物品、技能、关系、企业状态、房屋状态、游戏时间、已发生事件 ID、故事进度。`WorldState` 不包含已经渲染好的台词或 Godot 场景节点。

**`ActionProposal`**：由玩家输入、NPC 规则、未来 AI 或故事系统提交的意图；例如 `apply_job`、`work_shift`、`request_loan`、`terminate_contract`、`tell_secret`。意图**不保证成功**。

**`CommandProcessor`**：执行前检查实体存在、权限、时间/资源、地域规则、费用、冲突与幂等 ID；成功时原子式提交状态变更并发布 `DomainEvent`；失败返回稳定的错误码。一个命令不能处于半完成状态。

**`ObservationService`**：对玩家、NPC 和叙事系统暴露分层只读世界快照。一个 NPC 看不见其未观察/未获告知的秘密；叙事导演可获取高权限的元数据，但不得直接更改它。

建议的最小数据契约（示意；实际 JSON Schema 必须单独固化）：

```json
{
  "schema_version": 1,
  "proposal_id": "proposal_npc_chen_00018",
  "actor_id": "npc_chen_yu",
  "action": "apply_for_job",
  "target_id": "job_store_evening",
  "arguments": {},
  "expected_world_revision": 156,
  "issued_at_game_minute": 2940
}
```

命令响应必须有 `ok`、`error_code`（成功为 `null`）、`world_revision`、`emitted_event_ids`。`expected_world_revision` 发生冲突时应重新获取观察再提交，不得静默覆盖。

**实现约束**：初版不需要全量事件溯源（event sourcing）和复杂 CQRS；采用**权威快照 + 有界领域事件日志 + 幂等命令**足够。事件日志在重放测试中可用，但正式存档恢复应以快照为主。不要将信号总线当成可靠事务日志。

### 13.2 事实、认知与记忆

必须区分三类信息：

1. `WorldFact`：经游戏规则确认的真实事实（例如 `npc_chen_yu` 已失业）。
2. `Belief`：某角色相信的事实，可以错误、过期或来自传闻（例如“小陈以为玩家很有钱”）。
3. `MemoryRecord`：某角色亲眼见到或听别人说过的事件，有时间、来源、显著性及可见性；它可能改变 Belief，但不直接改变 WorldFact。

建议的字段：`subject_id`、`predicate`、`object/value`、`observed_at`、`source_actor_id`、`confidence`（0–1）、`visibility`、`expires_at`、`evidence_event_id`。MVP 只需支持少量事实与 1–2 种记忆来源；不要为首版引入向量数据库。

这一层决定了未来是否能自然出现误会、传言、欺骗、私人关系和信息不对称。未来 LLM 的上下文应从 `ObservationService` 导出，而不是把整个存档无差别发送给模型。

### 13.3 自由度来自行为系统，而非对话选项数量

正式系统要允许玩家和 NPC 发起广义社会行动：询问岗位、申请工作、换班、请假、辞职、介绍朋友、借钱、还钱、搬家、拒绝邀请、求助、承诺、违约、传递信息等。

实现顺序：第一阶段只做**工作/租房/交易/休息/社交**五组命令；以后增量扩展。每种命令必须定义前置条件、后果、可见事件、潜在失败原因和地区策略钩子。剧情系统应监听这些行为发生的事实，避免玩家只能通过固定剧情菜单改变命运。

### 13.4 分层城市模拟：优先做得“活”，不要做得“大”

| 层级 | 实例 | 更新策略 | 最低实现 |
|---|---|---|---|
| L0 — 活跃 | 玩家和当前场景少数重要 NPC | 高频/地点内行为 + 交互 | MVP |
| L1 — 相关 | 关键角色、同事、房东、邻居 | 游戏分钟/关键事件驱动的排程 | MVP 简化 |
| L2 — 背景 | 其他居民、企业群体 | 逐日批处理、统计状态和群组事件 | 中国切片后 |
| L3 — 宏观 | 就业景气、租金趋势、城市政策 | 每周/月变化 | 后续 |

- 层级变化不得凭空改变资产或关系；L2 升 L1 时需能从持久性摘要恢复。
- 离屏 NPC 不要求真实路径寻路；只有进入玩家附近才生成视觉化人物和移动路线。
- 玩家离开场景时，NPC 仍会在抽象层继续上班、消费或产生关键事件。
- 单个时间推进要有最大批次数及事件预算，防止睡眠 8 小时造成事件风暴。

### 13.5 决策接口：当前规则，未来 AI

```text
NPCDecisionPolicy.decide(observation, goals, budget) -> ActionProposal[]
  ├─ RuleBasedPolicy      [NOW] 日程 + 优先级 + 效用评分/状态机
  ├─ Utility/GOAPPolicy   [LATER] 复杂目标规划（仅关键 NPC）
  └─ LLMPolicy            [FUTURE] 语义推理与长期规划
```

所有策略接收相同的 `Observation`，输出相同命令提案格式。当前 `RuleBasedPolicy` 通过饥饿、现金、上班时间、关系和风险偏好决定行为；未来 LLM 可以提出新方案，但是否可执行依旧由 `CommandProcessor` 判定。**本轮版本不需要实现 LLMPolicy，只需要稳定的接口和 mock 适配器测试。**

---

## 14. AI 原生叙事架构：从 Storylets 到生成剧情

### 14.1 叙事不是直接写台词，而是生成结构化故事计划

故事分成三个层次：

1. **Story Seed（故事种子）**：某种矛盾或机会，如“低收入 + 租金上涨 + 房东想出售房屋”。
2. **Story Arc Proposal（故事提案）**：候选人物、冲突目标、需要满足的事实、可选情节节点、失败/放弃路径、预期世界事件。
3. **Story Presentation（叙事呈现）**：经批准的对白、消息、UI、演出、日志与总结文本，可有多个风格版本。

**可以不发生故事**。如果条件不足、NPC 不可达、角色死亡/迁走、状态变化导致冲突失效，故事应延迟、终止或寻找合法替代，而不是强行推进。

### 14.2 统一 StoryProposal 协议

推荐目录：`res://content/narrative/schemas/story_proposal.v1.schema.json`，先用 JSON Schema（或 Godot 等价校验 + 仓库内离线 JSON 校验工具）限制字段及可选值。以下仅是可读示意，不是最终 Schema：

```json
{
  "schema_version": 1,
  "proposal_id": "story_rent_0007",
  "provider_id": "template_story_provider",
  "scope": {"city_id": "CN_LINCHUAN", "actor_ids": ["player", "npc_landlord_01"]},
  "seed": "housing_insecurity",
  "required_facts": [
    {"fact": "housing.contract.status", "entity_id": "player", "op": "eq", "value": "overdue"}
  ],
  "beats": [
    {
      "id": "warning",
      "type": "dialogue",
      "speaker_id": "npc_landlord_01",
      "text_key": "story.rent.warning",
      "choices": [
        {
          "id": "ask_extension",
          "text_key": "story.rent.ask_extension",
          "proposed_action": {"action": "request_rent_extension", "target_id": "housing_player_contract", "arguments": {"days": 7}}
        },
        {
          "id": "decline",
          "text_key": "story.rent.decline",
          "proposed_action": {"action": "close_dialogue", "target_id": "story_rent_0007", "arguments": {}}
        }
      ]
    }
  ],
  "expiration_game_minute": 20160,
  "max_activations": 1
}
```

含义：选项只提交 `proposed_action`，而不是在剧情文件里直接加钱、强制改关系或任意执行脚本。玩家要求延长租期时，房东可能拒绝，具体取决于规则、关系和状态。校验时验证 `speaker_id`、`target_id`、时间、资格、事件冲突及所有引用的文本键存在。

### 14.3 完整生成管线（现在和未来共用）

```text
World Events + Canonical Facts + NPC Beliefs
                 ↓
          Narrative Opportunity Finder
                 ↓
          StoryProvider.generate_proposals()
           ├── Templates/Rules  (NOW)
           ├── Offline AI authoring (FUTURE)
           └── Runtime LLM       (FUTURE/OPTIONAL)
                 ↓
         JSON Schema / Type Validation
                 ↓
         Canonical Fact + Causality Check
                 ↓
         Action / Region / Safety Constraints
                 ↓
         Narrative Director (novelty, pacing, priority)
                 ↓
         Story Runtime (commands, consequences, lifecycle)
                 ↓
         Persistent Event History + NPC Memory
```

- `StoryProvider` **只是生成候选**；不能获取任意文件路径、执行 Godot GDScript、调用场景脚本或直接修改状态。
- `StoryValidator` 需要识别：不存在的角色、时间矛盾、房租未到期却触发欠租、结果与经济规则冲突、无法完成的要求、无来源/不应泄漏的私密信息。
- `NarrativeDirector` 的职责是避免连续几天全是房租危机、避免多个剧情争用同一 NPC/地点、控制节奏，并优先反映玩家真正做过的事。
- **世界事件可打断剧情**：玩家在故事途中辞职、搬家、NPC 换工作，未执行的节点必须重新校验；不能保证生成的故事一定完成。
- **文字与事实分离**：LLM 写出的“你拿到了 ¥2,000 奖金”只有在 `credit_money` 命令获批且成功后才能作为已发生事实呈现。

### 14.4 自由度与叙事一致性

每条主要故事线至少提供：

- 一条玩家**不参与**也会继续发展的世界路径。
- 至少一种**非对话介入方式**（换工作、付款、借钱、投诉、介绍、搬家等）。
- 失败、拒绝、延期及中止后的合理后果；不能把拒绝选项伪装成必须接受。
- 明确世界事实依赖和有效期；过期情节不可凭空出现。

首版中国 7 日故事只需要验证其中一两条；**不应为追求无限分支牺牲可玩性**。

### 14.5 现在不用 LLM，仍要支持“故事生成”

当前可落地方案：

- `TemplateStoryProvider`：故事片段池（Storylets）+ 前置事实过滤 + 角色槽位填充 + 权重/冷却 + 逻辑互斥分组。
- `NarrativeDirector`：基于现金、压力、关系、岗位和近期事件选择合适的故事候选。
- `DialogueVariants`：为同一合法事件提供不同语气/关系程度的手写台词，避免机械重复。
- `MemorySummary`：依据真实事件自动生成简短人生记录，例如“你在第三天因为通勤迟到，被扣了工资”，确保总结来自事件而非编造。

这些都是**无模型、离线、可单元测试的生成式组合系统**。待成本降低后再接入语言模型负责提出更复杂的冲突、完整人物弧线和对话。

---

## 15. 未来 AI 接入契约（只定义边界，不实施付费推理）

### 15.1 两种生成模式必须兼容

| 模式 | 作用 | 当前实现 |
|---|---|---|
| 开发时/离线生成（AI Content Studio） | 创作角色、职业、支线大纲、对白、城市内容；人或验证器批准后打包发行 | 暂不接入模型，只支持导入/验证标准内容 |
| 游戏运行时生成（Runtime Narrative AI） | 根据真实世界事件动态提出新故事线、谈话、目标和人物变化 | 暂不接入模型，仅预留 Provider 和缓存接口 |

早期优先**离线生产内容，随游戏免费分发**；运行时推理等成本、延迟、隐私与内容质量可控后再逐步开启。玩家可在无模型、无网络环境下继续游戏。

### 15.2 Provider 接口与最小能力

```text
StoryProvider.generate_proposals(narrative_context, constraints, budget)
    -> StoryProposal[]
DialogueProvider.generate_lines(approved_story_beat, speaker_view, style)
    -> DialogueDraft[]
NPCDecisionPolicy.decide(observation, goals, budget)
    -> ActionProposal[]
```

`narrative_context` 只包含必要且已过滤的事实、角色关系、故事历史摘要、可用世界机制、地区设置和风格边界。使用 `schema_version`、`provider_version`、`model_id`（若适用）、`content_hash` 标识来源。Provider 可实现 `static`、`templates`、`local_llm`、`remote_llm`，但当前仅实现 `templates` 和测试用 `mock`。

**模型是非确定性输入**：将通过校验的提案与相关世界版本固化进存档/事件日志，重放时使用已批准的提案，而不是重新请求模型；这样即使模型、提示词或服务商变化，已发生故事也不会变。

### 15.3 运行时保障（未来必须遵守）

- **成本**：按游戏日、角色和场景设置调用预算与 token 上限，优先后台离线缓存/批处理。没有预算就用模板继续。
- **延迟**：世界推进与玩家操作不能阻塞等待模型；超时自动回退。
- **隐私**：默认不上传真实玩家身份、系统用户名或非必要信息；未来联网模式必须明确选择与数据告知。
- **可控性**：提示词/模型输出均不可信；严禁执行模型生成的 GDScript、shell、SQL 或任意可执行代码。
- **内容与一致性**：生成的故事、人物和对话须经过结构校验、世界事实校验及必要的内容策略过滤；避免无意义重复和失实归因。
- **可替代性**：游戏既可以完全手写、完全模板化，也可以逐渐混合 AI；不会因为没有模型而无法存档或开展剧情。
- **可追溯性**：保存被采纳的结构化提案、版本、哈希、关联事件，不要求永久保存每个模型的原始推理过程。

---

## 16. 关键技术决策、性能与存档演化

### 16.1 为什么暂时不做“万名 LLM NPC”

真正需要优先解决的是**NPC 自主性 × 世界因果一致性 × 长期记忆 × 玩家自由行动 × 内容生产成本**。数万名同时调用 LLM 的 NPC 会产生明显的成本、延迟、稳定性问题，而不一定带来更好的游戏。

选择：少数关键角色精细模拟、背景人口抽象计算、NPC 决策器可替换、剧情可生成且经过验证。复杂程度按玩家可感知的价值增加。

### 16.2 初步性能目标（工程目标，不是已验证实测）

- 普通中端 PC 的 2D 游戏目标 60 FPS，必须在实际硬件上验证，不把此指标作为当前结果。
- 中国首个街区先实现 3 名可互动 NPC；后续逐步增加至 10–30 名重点人物，背景人口通过低频聚合模拟。
- 30 天加速无头测试必须在有限时间内完成，不出现事件无穷循环、指数级关系传播或无界内存增长。
- 对话、储存和跨城市切换不依赖实时网络；存档大小及加载时间建立性能回归基准。
- 对内容包做静态引用检查、事件上限、最大递归深度和故事触发冷却，防止生成内容造成无限重试。

### 16.3 内容包与存档演化

内容包需有 `pack_id`、`pack_version`、`schema_version`、`dependencies`、`region/country/city`、`content_hash`。存档记录已启用内容包版本、世界状态版本、RNG 状态、已批准故事提案和未完成故事节点。

- 加载旧存档需经过显式迁移，缺失的已移除内容包必须给出可理解错误，不能静默替换为其他角色。
- 剧情存档使用稳定 `proposal_id` 与 `beat_id`，不能靠 UI 数组位置或节点路径定位。
- 以后加入生成式 AI 后，旧档依然通过无 AI 规则模式加载；生成的故事快照可被离线读取和呈现。
- 未来玩家模组可考虑增加第三方内容包，但需要白名单动作和禁用任意代码；首版不承诺完整 MOD API。

---

## 17. v0.2 的工程任务增量（T021–T032）

> **执行次序**：T001–T020 的中国 7 日可玩循环仍为最早交付目标，但关键底座接口应从 T002/T003 起预留。本节除必要的最小接口外，在垂直切片稳定后逐步实现；不要要求一个编程 Agent 一次开发全部功能。

| ID | 任务 | 验收条件 |
|---|---|---|
| T021 | 权威 `WorldState` + `CommandProcessor` | 钱包、工作、关系不允许绕过命令直接更改；失败事务不留部分状态 |
| T022 | `DomainEvent` / 事件日志与命令幂等 | 同一命令 ID 重放不会重复支付；事件具有稳定引用链 |
| T023 | `ObservationService` | NPC 观察中不出现不可见的玩家隐藏信息；叙事可查询元数据 |
| T024 | 状态摘要与记忆最小模型 | NPC 能区分事实/传闻、记录来源和发生时间 |
| T025 | NPC 决策策略接口 | 同一个规则/Mock Policy 能返回统一 `ActionProposal` |
| T026 | 分层 NPC 模拟 | 场景外重要 NPC 能按时间更新活动；进入地图后状态一致 |
| T027 | StoryProposal v1 + Schema | 错误字段、未知动作和不存在的角色引用被拒绝 |
| T028 | StoryValidator / NarrativeDirector | 情节必须匹配真实世界条件；互斥剧情不会冲突触发 |
| T029 | 模板化故事生成器 | 同一世界状态能按种子生成合法、可选择的不同故事候选 |
| T030 | 故事生命周期、打断和存档 | 玩家搬家/辞职后原有失效剧情被中止；重读档不会重复后果 |
| T031 | 30 天无头压力/回归测试 | 世界独立运转 30 天、经济守恒/边界约束成立、无事件风暴 |
| T032 | 未来 AI Mock 接口与导入测试 | 用**预置 JSON Fixture** 模拟未来模型输出，验证/拒绝/执行；没有 HTTP 与模型 SDK 依赖 |

**强制验收情景（T028–T032）**：

```text
初始：玩家交不上房租；房东与玩家有租赁合同；同事 A 有稳定工作。
世界：玩家完成一次夜班，收入不足；房租到期产生欠租事件。
生成：模板 StoryProvider 提议“房东催租”剧情。
验证：StoryValidator 检查欠租事实、房东身份、租约仍有效。
玩家：不点击求情，而是通过系统向同事 A 借钱并支付房租。
结果：欠租状态消失；未执行的“房东催租”剧情重新校验后取消。
存档：保存并加载；世界事实、已发生事件、NPC 记忆及取消状态一致。
未来 AI：同样的故事由 Mock LLM 的 JSON 提案表达，不改核心模拟代码。
```

此情景验证的不是“AI 说话逼真”，而是**真实世界行动可以改变甚至取消故事**。这是本项目高自由度的关键验收标准。

---

## 18. 给编程 Agent 的 v0.2 增补指令（优先级高于旧版模糊描述）

- 本文确立的产品方向是：**未来 NPC 与故事剧情都可 AI 生成**；目前不接入运行时 LLM，仅使用规则与模板实现同样的 Provider 接口。
- 不要把生成式 AI 当成单独聊天界面。其将来输出必须转为 `ActionProposal`、`StoryProposal` 或 `DialogueDraft` 等有限结构。
- 第一阶段先保证 7 天的谋生游戏循环可玩。不要为了搭建高度抽象的 AI 框架推迟游戏原型。
- 改动权威内核时须先更新/增加测试，保留可重放的事件与可迁移的存档字段。
- 实现规则 NPC 时不得偷偷读全局隐藏世界事实；一律通过 `ObservationService` 获取授权观察。
- 设计 Storylets 时，不要在 JSON 中允许可执行脚本；只使用预定义的类型、条件和合法命令。
- 现在的任何关于“AI 生成剧情”的测试都要通过静态数据 Fixture，不需要网络、模型服务、付费 API、账户或密钥。
- 按 `docs/decisions.md` 记录架构权衡；如后续需要修改核心协议，先提出兼容/迁移方案，再改动实现。

---

## 19. 产品方向待定项（不阻止首版开发）

- 正式游戏中文/英文名称及商标检索。
- 玩家是否有固定背景或可选初始社会经济背景。
- 角色与城市的最终美术规格（俯视角像素画 vs HD-2D）。
- 游戏中中国城市的实际地域风格（南方/北方/综合架空）。
- 叙事现实程度：略带希望、冷峻写实、黑色幽默之间的比例。
- 长期是否加入跨国移民、升学、恋爱结婚、创业与可玩结局。

**当前默认决定（v0.2）**：采用虚构中国综合型城市、轻度现实主义、单人离线像素风、7 日可玩纵向切片；但长期明确以 **AI-native NPC + AI-generated narrative** 为方向。当前不接 LLM，优先实现权威社会模拟、可验证 Story DSL 和可替换 Provider。所有未决策不得阻碍 T001–T004 的推进。
