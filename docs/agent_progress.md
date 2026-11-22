# Agent 进度

最新记录在前。

| ID | 任务 | 状态 |
|---|---|---|
| T001 | 初始化项目 | ✅ 完成 |
| T002 | 内容包注册器 | ✅ 完成 |
| T003 | 游戏时间 | ✅ 完成 |
| T004 | 地区策略接口 | ✅ 完成 |
| T004b | 最小 WorldState / CommandProcessor / DomainEvent 骨架（D-004a，已批准） | ✅ 完成 |
| T005 | 城市与玩家 | ✅ 完成 |
| T006 | HUD | ✅ 完成 |
| T007 | 经济与商店 | ✅ 完成 |
| T008 | 需求与睡眠 | ✅ 完成 |
| T005b | 3/4 斜俯视表现层（D-019，产品负责人选定） | ✅ 完成 |
| T009 | 工作公告栏 | ✅ 完成 |
| T010 | 工作结算 | ✅ 完成 |
| T011 | 房租与账单 | ✅ 完成 |
| T012 | 通勤 | ✅ 完成 |
| T013 | NPC 日程 | ✅ 完成 |
| T014 | 关系与对话 | ✅ 完成 |
| T015 | 七日事件 + StoryValidator | ✅ 完成 |
| T016 | 教程与指引 | ✅ 完成 |
| T017 | 存读档 | ✅ 完成 |
| T018 | 平衡测试 | ✅ 完成 |
| T019 | 设置与适配 | ✅ 完成（1080p 下英文界面待复查截图，见下） |
| T020 | 发布构建 | ⚠️ 流程完成，等导出模板才能产出安装包（见下） |
| T021–T032 | 见 PRODUCT_SPEC §17（v0.2 起） | 待办 |

**M0–M4 已完成（2026-11-21/22）。T020 的最终安装包需要先安装 Godot 4.7.2 导出模板。**

---

## M4：T017 / T018 / T019 / T020 — 2026-11-22 — ✅（T020 待导出模板）

### T017 存读档
- `scripts/persistence/save_manager.gd`：存档信封 + `WorldState` 快照（字段见 D-026）。
  - 写入：临时文件 → 读回并按正式读档流程完整还原 → 旧档改为 `.bak` → 改名替换。
  - 读档：迁移 → 信封校验 → 检查内容包、城市、地区、货币 → 各组件校验 → 交叉引用检查。
  - 3 个存档位，列表显示第几天、时间、现金和保存时间。
- `save_migrations.gd`：显式、按版本顺序执行的迁移链。存档版本比游戏新、缺少某一步迁移、迁移失败，都会报出明确的错误。
- 入口：暂停菜单的“保存 / 读取”、出租屋门口的“存档”、标题画面的“读取存档”。覆盖存档和读档前都会确认。读档后玩家回到存档时站的格子；如果那个格子已经不能站人，就回到到达地点。
- 新增测试 `test_save_roundtrip`（11 个）、`test_save_ui`（6 个）。

### T018 平衡测试
- 脚本玩家 `tests/framework/week_bot.gd` 按 7 种策略完整玩一周，`tools/balance_report.gd` 打印对比表。
- 发现的问题：完全不工作也能交上首期房租。调整：初始现金从 ¥1,500 改为 ¥1,400，其余数值不变。数据和理由见 `docs/balance.md`、D-027。
- `test_balance`（6 个）把规范的验收写成断言：
  - 合理路线能交上房租；
  - 过度消费或不工作会欠租；
  - 欠租后上一个班就能补交；
  - 晚开工、身无分文到达也能交上房租；
  - 全程余额不为负。

### T019 设置与适配
- 设置项：主音量、音效、窗口（三档窗口 + 全屏）、界面语言，立即生效并保存在 `user://settings.cfg`。标题画面和暂停菜单共用同一个设置面板。
- 音效（点击、收入、新的一天）在运行时合成，项目里没有音频文件。
- 英文：common 包的 176 条文案全部有英文。剧情文字回退显示中文（占位）。切换语言时 HUD 立即重建。测试会检查中英文占位符一致。
- 截图检查（`tools/screenshot.gd`，现在共 19 个画面）：720p 和 1080p 下，标题、读档列表、设置、暂停、存档列表、英文公告栏都没有截断。**改完 HUD 英文刷新、标题自检信息和下拉框宽度之后，还没有重新截图复查**（那次截图会在桌面弹出窗口，被暂停了）。

### T020 发布构建
- `export_presets.cfg`：Linux 和 Windows，单文件，只打包游戏需要的内容。
- `tools/build_release.sh`：检查导出模板 → 跑 `check.sh` → 导出 → 在空目录里冒烟测试 Linux 可执行文件 → 附玩家说明 → 打 zip。
- `--smoke-test` 启动参数：自动开一局，再存档、读档、比对。`check.sh` 新增第 4 步，从导出的 `.pck` 在项目目录之外运行这个冒烟测试。
- **本机没有安装 Godot 4.7.2 导出模板**，所以还没有产出真正的 exe / x86_64 安装包。模板约 1 GB，需要联网下载，等产品负责人决定。已验证的部分：导出的 `.pck` 在项目目录之外、不打开编辑器也能启动，能完成新游戏、存档和读档。

### 测试命令与真实结果（Godot 4.7.2.stable，Linux，实际执行）
- `./tools/check.sh` → **228 passed, 0 failed, 0 broken files (23 files)**；无泄漏；启动画面、城市场景、资源包冒烟测试都无错误；`SMOKE OK`；`ALL CHECKS PASSED`。
- `godot --headless --path . --editor --quit` → 0 条 ERROR/WARNING。
- `tools/balance_report.gd` 跑 7 种策略耗时约 1 秒。
- 测试不会改动玩家的存档和设置：测试使用单独的目录和设置路径，跑完会清理。之前有一次测试误把 `settings.cfg` 写进了玩家目录，已经删除，并改为可以重定向设置路径。

### 风险 / 未完成
- 还没有真正的发布包（缺导出模板）。Windows 版也一直没有在 Windows 上跑过。
- 需求只有软性后果，压力到 100 也不影响任何结果（见 `docs/balance.md`）。
- 剧情没有英文翻译。没有背景音乐。
- 仍然没有真人试玩数据，也还没有 git 提交。

### 下一项
- 安装导出模板后运行 `tools/build_release.sh`，然后在 Windows 上跑一次冒烟测试。
- 真人试玩第一周。
- 之后进入 v0.2（T021 起）。

---

## T005b + M2（T009–T012）+ M3（T013–T016）— 2026-11-22 — ✅

按产品负责人指示，在无人值守的情况下连续完成，并对 M3 做了打磨。

### T005b 3/4 斜俯视（D-019）
- 新增 `StructureVisual`（建筑正面墙、窗、门、雨棚、屋顶、店招，玩家在后面时淡化）、`PropVisual`（树）、`PersonDrawer`（1×2 格高的人物，4 个朝向，走路摆腿）、`RoadMarkings`（路沿和中线）。
- 地面图块改为程序生成的纹理。实体按纵坐标排序；玩家碰撞框缩到脚下。
- 地图格式增加 `structures` 并做结构校验。

### M2
- **T009**：`jobs.json` 中 3 个岗位；招聘公告栏面板显示时薪、每班到手、地点、精力和压力消耗、通勤代价，可预约今天或明天的班次，并列出“我的班次”。
- **T010**：`work_shift` 命令处理早到、迟到和缺勤；需求按岗位速率变化；工资经地区规则计算后只入账一次。实现了 RegionPolicySwap（同一套工作流程，换用测试地区规则后到手工资改变）。
- **T011**：`housing.json`；签约付押金，第 7 天开始时自动收租，钱不够记为欠租（不会负数），每天重试，可手动补交，提前一天提醒。没有租约不能睡觉。
- **T012**：工业区地图（32×18）和 12 路往返线路；`LocationSystem` 以地图为粒度做在场检查（D-020）；乘车后切换地图，玩家出现在到达站。

### M3
- **T013**：`npcs.json` 中 3 名 NPC 和日程；`NpcScheduleSystem` 是纯函数；NPC 在地图上按日程出现和消失，头顶有名牌，可交互。
- **T014**：`RelationshipSystem`、`dialogues.json`（初次对话、闲聊、分支节点），`choose_dialogue` 命令，闲聊好感每天只加一次。
- **T015**：`events.json` 中 9 个事件（到达、第 2 天陈雨、遇到老周、第 3 天晚饭邀请、第 4 天仓库招工、第 6 天交租提醒、欠租催缴、第一周总结及其补发）；`StoryConditions` 和 `StoryEffects` 白名单解释器；`StoryValidator`；`EventSystem`；`DialogueSystem` 展示队列；`SummaryBuilder` 根据真实状态生成四组总结。
- **T016**：7 步教程任务；HUD 显示当前目标和提示；按 J 打开日志（任务、班次、住处、认识的人）。
- **打磨**：
  - 长面板可以滚动；
  - 工业区地图放大，并设置深色背景，避免露出灰边；
  - HUD 提示字号调大；
  - 剧情面板上按 Esc 不再造成“永远打不开暂停菜单”的陷阱；
  - 日志里没有认识的人时显示说明文字；
  - 用截图工具在 720p 和 1080p 下逐一检查了 12 个画面。

### 测试命令与真实结果（Godot 4.7.2.stable，Linux，实际执行）
- `./tools/check.sh` → **204 passed, 0 failed, 0 broken files (20 files)**；无泄漏；启动画面和城市场景无界面运行均无错误；`ALL CHECKS PASSED`。
- `godot --headless --path . --editor --quit` → 退出码 0，0 条 ERROR/WARNING。`scripts/` 中没有硬编码的地区 ID。
- 新增测试文件：`test_jobs`、`test_rent`、`test_transit`、`test_npc_schedule`、`test_dialogue`、`test_story_validation`、`test_events`、`test_quests`、`test_week_playthrough`。另外 `test_city_world` 增加了 3/4 遮挡、换图、公告栏预约后去店门口上班、签约后睡觉、NPC 对话、剧情弹窗、Esc 陷阱、日志等场景测试。
- 无界面完整一周通关（`test_week_playthrough`）：合理玩法能交上首期房租、完成 2 个以上班次、和一人关系达到 10 以上，教程全部完成，余额为正，需求在 0..100 内；过度消费的路线会欠租，余额不为负，房东会跟进。
- 开发中由测试发现并修复的问题：
  - 节点名不能包含 `.`，导致班次按钮查不到；
  - `StoryEffects` 对空上下文没有防护；
  - 7 天测试里的辅助函数吞掉了待验证的对话（测试本身的问题）；
  - 工作中的压力规则在每小时开始时判定，测试期望值写错了（测试本身的问题）。

### 验收对照
- T009：岗位和条件完全由 JSON 加载 ✅
- T010：同一 `shift_id` 只支付一次；工资由地区规则计算 ✅（§8.1 #4 PayIdempotency、#5 RegionPolicySwap ✅）
- T011：跨多天快进不漏账单、不重复扣款；读档后也不重复扣款 ✅（§8.1 #6 RentDue ✅）
- T012：余额不足不能乘车；乘车后时间和目的地正确 ✅（§8.1 #3 交通部分 ✅）
- T013：时间变化后 NPC 位置正确；换场景后回来仍然正确 ✅
- T014：同一段可重复对话不能无限刷好感 ✅
- T015：第 7 天总结根据真实状态至少有 3 种变体（测试中 4 种路线得到 4 种不同组合）；一次性事件不重复触发，读档后也成立 ✅（§8.1 #8 EventOnce ✅）；StoryValidator 拒绝未知后果、无效实体和越权修改 ✅
- T016：“新玩家不看外部说明也能完成首个班次”——HUD 每一步都有具体的操作提示。**但这一条本质上要靠真人试玩验证，目前尚未进行。**

### 风险 / 未完成
- **没有存读档（T017）**：退出游戏后进度丢失。
- 数值尚未系统调参（T018）。7 天里没有在线的真人体验数据。
- 签租约时不需要房东在场；后续可以改成必须当面找王阿姨签。
- 首版没有室内场景；NPC 不会走路，只会在地点锚点之间切换（符合 T013 要求）。
- `NarrativeDirector`、模板故事生成器、`ObservationService` 属于 v0.2 的 T023–T029，尚未实现。
- 尚未进行 git 提交。

### 下一项
M4：T017 存读档。

---

## M1：T005 / T006 / T007 / T008 — 2026-11-21 — ✅

中途网络断开过一次。恢复后核对现状：模拟层（T007/T008 的规则与测试）已经完成，界面层尚未开始，随后补完。

### T005 城市与玩家
- `CityMapBuilder`：从 `maps` 记录生成 TileMapLayer、占位图块和碰撞。
- `PlayerController`：4 向移动、碰撞、交互感应。
- `Interactable`：标识牌、商店门口、出租屋门口、公园长椅。
- `CityWorld`：组装地图、出生点、相机边界，并把交互转给界面。

### T006 HUD 与暂停
- `Hud`：日期和时间、现金、三项需求（彩色条加“数值/100”加含义提示）、交互提示。每个已提交事件后刷新。
- `GameUi`：Esc 打开或关闭暂停菜单（继续、返回标题、退出游戏）；打开任何面板时，场景树和游戏时钟都暂停。

### T007 经济与商店
- `EconomyService`（钱包和流水）、`InventorySystem`（背包）。
- 命令：`buy_item`、`use_item`。
- 商店界面和背包界面（I 键）。
- 内容：3 种消耗品，2 家店。

### T008 需求与睡眠
- `NeedsSystem`：按小时速率、模式上限和压力规则变化，数值钳制在 0–100。
- `TimeFlow`：命令内推进时间的统一入口。
- `perform_activity` 命令：出租屋门口睡觉 8 小时，长椅休息 1 小时。

### 配套
- 内容层：新增 `text`（本地化）、`game_rules`、`items`、`activities`、`shops`、`maps` 表；所有文本 key 都做存在性校验；地图做结构校验。
- `SimulationSession`：组装一局游戏。
- `GameSession` 和 `EventBus` 两个 autoload；`Localizer`；`MoneyFormat`。
- 启动画面加了“新游戏”和“退出”按钮。
- 测试执行器支持异步测试；`check.sh` 新增城市场景的启动检查。
- `tools/screenshot.gd` 截图工具。

### 测试命令与真实结果（Godot 4.7.2.stable，Linux，实际执行）
- `./tools/check.sh` → **138 passed, 0 failed, 0 broken files (11 files)**；无泄漏；启动画面和城市场景无界面运行均无错误；`ALL CHECKS PASSED`。
- `godot --headless --path . --editor --quit` → 退出码 0，0 条 ERROR/WARNING。
- 场景测试用真实物理帧验证了：
  - 出生在公交站，并且在标识牌范围内；
  - 撞到外墙和建筑会停下；
  - 4 向移动，不走斜线；
  - 按 E 打开标识牌、商店、睡觉确认；
  - HUD 在购买和时间推进后同步更新；
  - 暂停时不走时；
  - 商店购买到没钱为止，买不起的商品被禁用；
  - 背包使用物品；
  - 通过出租屋门口睡觉后精力为 90。
- 实际渲染（非无界面）：
  - `tools/screenshot.gd` 在 1280×720 和 1920×1080 下截取世界、商店、背包、暂停四个画面，人工查看没有控件被截断或重叠。
  - 脚本化演练“启动画面 → 点新游戏 → 进入 CityWorld”成功。
- `grep scripts/` 地区 ID：只在 `MoneyFormat` 的货币符号显示表中出现 `CNY`，属于界面显示，不是规则分支。

### 验收对照
- T005：玩家不能穿墙；能靠近并触发标识牌。✅（`test_city_world.gd`）
- T006：游戏状态变化实时同步到界面；可以暂停。✅
- T007：¥20 买 ¥18 的简餐后余额 ¥2；再买失败且余额不为负，界面上按钮也变为禁用。✅（`test_economy.gd`、`test_city_world.gd`）
- T008：需求钳制在 0–100；睡觉推进日期并触发跨日事件。✅（`test_needs.gd`）
- 规范 §8.1：#2 MoneyInteger ✅、#3 InsufficientFunds（购买部分 ✅，交通部分在 T012）、#7 NeedBounds ✅。

### 本轮发现并修复的问题
- 截图工具设置窗口尺寸时用错了对象，导致脚本卡住，桌面上留下一个灰色窗口约 90 秒。已修复，并加了看门狗。**这就是你看到的“界面是灰色的”。**
- 初版地面颜色偏灰，需求条是默认灰色。已改为暖色地面和彩色需求条，数值文字照常保留。
- `InventorySystem._set` 与 `Object._set` 重名，已改名。

### 风险 / 未完成
- **手动验收没有由真人执行**：§8.2 的 A、C 部分由自动场景测试和脚本演练覆盖，建议你亲自玩一遍（启动 → 新游戏 → 走动 → 便利店买东西 → I 打开背包使用 → 出租屋睡觉）。
- 睡觉目前不需要先租房（T011），买东西也不检查是否在店门口（T012），见 D-015、D-016。
- 命令幂等记录按 4096 条保存，探索约每 5 秒提交一次时间命令；存档体积要在 T017 评估。
- 尚未进行 git 提交。

### 下一项
M2：T009 工作公告栏。

---

## M0：T002 / T003 / T004 / T004b — 2026-11-21 — ✅

按产品负责人指示，一次完成 M0 剩余任务。

### T002 内容包注册器
- `SchemaValidator`：声明式校验，相当于 JSON Schema 的一个子集。支持 string/id/text_key/ref/int/bool/array/object/map/any；支持 required、nullable、pattern、enum、范围、unique；整值浮点规范化为 int；收集引用，供第二阶段解析。
- `ContentSchemas`：pack manifest 加 6 张表（needs、regions、region_policy_configs、cities、districts、locations）。
- `ContentRegistry`：
  - 递归发现 `pack.json`，校验依赖（缺失、循环），按确定的拓扑顺序加载。
  - 校验数据文件的路径（禁止 `..`、绝对路径、协议前缀）和 `schema_version`。
  - 检查字段、重复 ID（跨文件、跨包）、引用是否存在和可见、scope 是否一致、`match` 跨记录一致性。
  - 计算 `content_hash`，保留 `story_providers` 元数据。
  - 加载全有或全无，查询返回深拷贝。
- 真实内容：`common`（needs）、`region_cn`（region + policy_config）、`city_cn_linchuan`（city + 2 个片区 + 7 个地点，对应 §3.1）。
- 入口场景启动时自检内容包和默认城市的地区规则，失败时 `push_error`，所以 `check.sh` 的启动步骤也会失败。

### T003 游戏时间
- `GameClock`：整数分钟；在午夜切分推进并返回事件草稿；暂停原因集合；把真实时间累计成整数分钟；`to_dict`/`from_dict` 带校验；单次推进上限 30 天。

### T004 地区策略接口
- `RegionPolicy` 基类（接口与规范 §2.3 一致），`ChinaRegionPolicy`（游戏化参数全部来自 `policy_config.json`），`RegionPolicyRegistry`（实现 id → 脚本，城市 → 规则完全由数据选择）。

### T004b 权威内核骨架
- `WorldState`、`CommandProcessor`、`CommandHandler`、`CommandContext`、`ActionProposal`、`CommandResult`、`DomainEvent`、`CommandJournal`、`GameEventBus`，以及第一个真实命令 `advance_time`（`AdvanceTimeHandler`）。
- 不包含任何业务命令（钱包、工作等留给 T007 及以后）。

### 变更文件
- 新增：
  - `scripts/content/{schema_validator,content_schemas,content_registry}.gd`
  - `scripts/simulation/{game_clock,advance_time_handler}.gd`
  - `scripts/regions/{region_policy,china_region_policy,region_policy_registry}.gd`
  - `scripts/kernel/{world_state,command_processor,command_handler,command_context,action_proposal,command_result,domain_event,command_journal}.gd`
  - `scripts/app/game_event_bus.gd`
  - `content/common/{pack,needs}.json`、`content/regions/cn/{pack,region,policy_config}.json`、`content/regions/cn/cities/linchuan/{pack,city,districts,locations}.json`
  - `tests/test_{content_integrity,schema_validator,clock,region_policy,command_atomicity,domain_events}.gd`、`tests/framework/content_fixture.gd`、`tests/fixtures/flat_fee_region_policy.gd`
- 修改：`project.godot`（新增 `everyday_city/content/*` 设置）、`scripts/boot/boot.gd`、`scenes/boot/boot.tscn`、`tests/test_project_setup.gd`、`tools/check.sh`（增加泄漏检测）、`docs/*`、`README.md`。

### 测试命令与真实结果（Godot 4.7.2.stable，Linux，实际执行）
- `./tools/check.sh` → import 无错误；**85 passed, 0 failed, 0 broken files (7 files)**；无对象泄漏；主场景无头启动 30 帧无错误；`ALL CHECKS PASSED`。
- `godot --headless --path . --editor --quit` → 退出码 0，日志中 0 条 ERROR/WARNING。
- 反向验证：
  - 临时把 `city.json` 的 `default_spawn` 改为 `airport`，无头启动输出 `ERROR: content: res://content/regions/cn/cities/linchuan/city.json:/default_spawn [E_UNKNOWN_REF] locations 'airport' is not defined`。之后已恢复原文件。
  - 用 `grep` 检查 `scripts/` 中硬编码的 `"CN"`/`"CNY"`/`"CN_LINCHUAN"` 等地区 ID：无结果。
- 实际渲染 1280×720 截图：自检行显示“内容包 3 个 · 城市 CN_LINCHUAN · 地区规则 china（CNY）”。
- 开发过程中由测试发现并修复的问题：
  - 加载失败后错误列表被 `_reset()` 原地清空，导致报不出错误。
  - `ref` 类型缺少默认 ID 格式校验。
  - `any` 类型拒绝 JSON `null`，导致含 `error_code: null` 的存档无法读回。
  - 测试中的 lambda 形成循环引用，造成对象泄漏。

### 验收对照
- T002：缺少必填字段、重复 ID、无效引用都能定位到文件和 JSON 指针并失败；正确配置加载成功；`provider_id`/`schema_version` 元数据已保留。✅
- T003：23:50 快进 30 分钟得到下一天 00:20；跨 2 天得到恰好两次 `day_changed`（2、3），顺序正确。✅
- T004：通过 registry 按 city 选出中国规则；改用测试中的伪地区规则后，调用代码不变，净工资由 ¥83.60 变为 ¥78.00。✅（真实 WorkSystem 上的 RegionPolicySwap 测试在 T010 完成。）
- T004b：失败的事务不留下任何状态（时钟、修订号、事件序号、日志、通知都不变）；同一命令 ID 不会重复执行，读档后依然成立。✅

### 风险 / 未完成
- `text_key` 存在性校验要等本地化表建立（T014/T019）。
- 世界整体捕获和回滚的成本，在 T021 组件变多后需要复核（D-009）。
- `GameEventBus` 还未注册为 autoload，等 T005 创建 GameSession 时接入。
- 尚未进行 git 提交。

### 下一项
T005 城市与玩家（M1）。

---

## T001 初始化项目 — 2026-11-21 — ✅

**已完成**
- Godot 4.7.2 工程（`project.godot`）：入口场景、1920×1080 基准 / 1280×720 窗口、Compatibility 渲染器、像素过滤。
- 输入映射：`move_up/down/left/right`（WASD + 方向键）、`interact`(E)、`pause_menu`(Esc)、`open_inventory`(I)、`open_journal`(J)。
- 基础 UI 主题 `assets/ui/theme/default_theme.tres`：CJK 系统字体回退链、Panel / Button 样式（含键盘焦点框）。
- 入口场景 `scenes/boot/boot.tscn` + `scripts/boot/boot.gd`（只显示标题和版本）。
- 规范 §4 的目录骨架；`content/regions/us|eu` 只有 README。
- 零依赖无头测试执行器与 `tools/check.sh`。
- `.gitignore`、`.gitattributes`、`.editorconfig`、README、`docs/*`；规范已复制为 `docs/PRODUCT_SPEC.md`。

**变更文件**
`project.godot`, `.gitignore`, `.gitattributes`, `.editorconfig`, `README.md`,
`assets/ui/theme/default_theme.tres`, `scenes/boot/boot.tscn`, `scripts/boot/boot.gd`,
`tests/run_tests.gd`, `tests/framework/test_case.gd`, `tests/test_project_setup.gd`, `tools/check.sh`,
`content/regions/us/README.md`, `content/regions/eu/README.md`,
`docs/PRODUCT_SPEC.md`, `docs/decisions.md`, `docs/changelog.md`, `docs/agent_progress.md`，以及各空目录下的 `.gitkeep` 和 Godot 生成的 `*.uid`。

**测试命令与真实结果**（Godot 4.7.2.stable，Linux，实际执行）
- `./tools/check.sh` → import 无错误；`6 passed, 0 failed, 0 broken files`；主场景无头启动 30 帧无错误；`ALL CHECKS PASSED`，退出码 0。
- 反向验证：临时加入一个失败断言和一个编译错误的测试文件后，`check.sh` 报 FAIL/BROKEN，退出码为 1（之后已删除这两个文件）。
- `godot --headless --path . --editor --quit` → 退出码 0，日志中没有 ERROR/WARNING。
- 非无头渲染 `godot --path . --write-movie … --quit-after 5`：1280×720 截图中“临川市 · 开发构建（空工程）”中文正常显示。

**手动验收**：编辑器 GUI 未由人工打开（仅验证了无头编辑器启动和实际渲染帧）。

**风险 / 未完成**
- 中文字体依赖系统字体（D-003），发布前需打包 OFL 字体子集。
- 规范时序问题见 `decisions.md` D-004a–i；其中 D-004a 建议在 T007 前插入 T004b。
- 尚未进行首次 git 提交。

**下一项**：T002 内容包注册器。
