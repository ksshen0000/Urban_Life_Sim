# 剧情添加指南（给 AI agent 读）

目标：开发者用一句话描述想要的剧情（例如“第 5 天晚上在公园碰到一个吹萨克斯的大叔，请他吃饭可以加好感”），agent 照本文 **只改 JSON 内容文件**，跑完检查后提交并推送。

> 加剧情不需要写代码。剧情使用白名单 DSL：只有本文列出的条件和效果。需要新的条件或效果类型才动代码，见 §9。

---

## 0. 速查：一次完整流程

```bash
git pull --rebase                       # 1. 先同步
# 2. 按 §2–§5 编辑 JSON（NPC / 对话 / 事件 / 文本）
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . --quit-after 5 2>&1 | grep "content:"   # 3. 没有输出 = 内容校验通过
# 4. 按 §7 写一个小测试（推荐）
./tools/check.sh                        # 5. 必须看到 ALL CHECKS PASSED
git add -A && git commit -m "Story: <一句话>" && git push   # 6. 提交推送（见 §8）
```

**不要在检查没通过时提交。不要声称“测试通过”而实际没跑。**

---

## 1. 文件在哪

城市内容包：`content/regions/cn/cities/linchuan/`

| 文件 | 作用 |
|---|---|
| `npcs.json` | 人物：名字、外貌、日程（在哪、几点、哪几天） |
| `dialogues.json` | 对话树：节点、选项、选项的效果 |
| `events.json` | 事件：什么条件下触发哪棵对话树 |
| `text.json` | 所有显示文字（中英文），用 key 引用 |
| `quests.json` | 任务步骤（日志里的“目标”），可选 |
| `locations.json` | 地点 id（只读参考，一般不用改） |
| `maps/*.json` | 地图；路人 `pedestrians` 在这里（§6） |

通用内容：`content/common/`（`needs.json`、`items.json`、`text.json`）。

所有 JSON 都是 `{"schema_version": 1, "records": [...]}`，每条记录都要有 `"city_id": "CN_LINCHUAN"`（common 包除外）。

---

## 2. 基本单位和约定

- **时间**：`minute_of_day = 小时 * 60 + 分钟`（例如 19:30 → 1170）。游戏日从 **第 1 天** 开始，一共 7 天。
- **钱**：整数“分”。`2000` = ¥20。剧情加钱或扣钱，单次上限 `20000`（¥200）。
- **需求**：`hunger`（越高越饿）、`energy`（越高越有精神）、`stress`（越高越紧绷），范围 0–100。单次变化不超过 ±50。
- **关系**：单次 `delta` 不超过 ±20。可重复对话里的正向关系变化，每个 NPC 每天只生效一次。
- **剧情标记**：key 必须以 `story.` 开头，例如 `story.met_sax_man`。没设置过的标记，用 `flag_equals ... false` 判断时为真（现有内容都这样用）。
- **id 命名**：小写加下划线。NPC 用 `npc_`，对话用 `dialogue_`，事件用 `event_`，文本 key 用 `npc.<名>.name`、`dlg.<树>.<节点或选项>`。
- **不要改已有 id**，存档会引用它们。新增可以，旧的不要改名或删除。

### 现有可引用的 id

- 地点 `location_id`：`old_town_bus_stop`、`old_town_apartment`、`park`、`arcade`、`billiard_hall`、`convenience_store_front`、`fast_food_front`、`old_town_east_end`、`job_board`（以上在老街地图）；`convenience_store`、`fast_food_restaurant`（店内）；`xinhe_west_entry`、`barber_shop`、`construction_site`（新河里）；`downtown_bus_stop`、`luxury_boutique`、`downtown_cafe`、`dessert_shop`、`mall`、`watch_store`（市中心）；`industrial_warehouse`、`industrial_bus_stop`（工业区）。
- 地图 `map_id`：`map_old_town`、`map_xinhe`、`map_downtown`、`map_industrial`、`map_convenience_interior`、`map_fast_food_interior`。
- NPC：`npc_chen_yu`（陈雨，便利店）、`npc_landlord_wang`（王阿姨，房东）、`npc_lao_zhou`（老周，工业区）、`npc_xiao_wu`、`npc_doudou`、`npc_granny_liu`。
- 物品 `item_id`：`item_simple_meal`、`item_instant_food`、`item_drink`、`item_latte`、`item_cake`、`item_silk_scarf`、`item_perfume`、`item_luxury_bag`、`item_luxury_watch`。

不确定时，直接查对应 JSON 文件，以文件为准。

---

## 3. 加一个 NPC（`npcs.json`）

```json
{
  "id": "npc_sax_man",
  "city_id": "CN_LINCHUAN",
  "name_key": "npc.sax_man.name",
  "role_key": "npc.sax_man.role",
  "home_location_id": "park",
  "schedule": [
    {"start_minute_of_day": 1140, "end_minute_of_day": 1290, "location_id": "park", "day_from": 5, "day_to": 7}
  ],
  "initial_relationship": 0,
  "dialogue_tree_id": "dialogue_sax_man_intro",
  "chat_tree_id": "dialogue_sax_man_chat",
  "appearance": {"shirt": "#3a3550", "hair": "#4a3a34", "hair_style": "short", "figure": "m", "bottom": "#2e2a28", "shoes": "#2e2a28"}
}
```

- `schedule`：不在任何时段里的时间，人就在家，看不见。`day_from` / `day_to` 可选，不写表示每天都在。只出现一天的“陌生人”写成同一天，例如 `5` 和 `5`。
- NPC 会站在该地点出生点旁边的空地上。必须用 §2 里已有的地点；新地点要改地图，属于大改动。
- `appearance`：
  - `hair_style` 可选值：`short`、`spiky`、`buzz`、`bald`、`long`、`bob`、`ponytail`、`bun`、`perm`；
  - `outfit` 可选值：`pants`、`skirt`、`dress`；
  - `figure` 可选值：`m`、`f`；
  - 颜色用 `#rrggbb`；`skin`、`bottom`、`shoes`、`vest` 可选。
- `dialogue_tree_id` 是初次见面的对话，`chat_tree_id` 是平时按 E 的闲聊（应设为 `"repeatable": true`）。两棵树都必须存在。

---

## 4. 写对话树（`dialogues.json`）

```json
{
  "id": "dialogue_sax_man_intro",
  "city_id": "CN_LINCHUAN",
  "channel": "in_person",
  "speaker_id": "npc_sax_man",
  "repeatable": false,
  "nodes": [
    {"id": "start", "text_key": "dlg.sax_intro.start", "choices": [
      {"id": "listen", "text_key": "dlg.sax_intro.listen", "next": "treat", "effects": []},
      {"id": "leave",  "text_key": "dlg.sax_intro.leave",  "effects": [
        {"type": "set_flag", "key": "story.met_sax_man", "value": true}
      ]}
    ]},
    {"id": "treat", "text_key": "dlg.sax_intro.treat", "choices": [
      {"id": "pay", "text_key": "dlg.sax_intro.pay", "effects": [
        {"type": "debit_money", "amount": 2500},
        {"type": "change_relationship", "npc_id": "npc_sax_man", "delta": 10},
        {"type": "change_need", "need_id": "stress", "delta": -6},
        {"type": "set_flag", "key": "story.met_sax_man", "value": true}
      ]},
      {"id": "no", "text_key": "dlg.sax_intro.no", "effects": [
        {"type": "set_flag", "key": "story.met_sax_man", "value": true}
      ]}
    ]}
  ]
}
```

规则（违反会在加载时报错）：
- 第一个节点的 id 必须是 `start`。每个节点有 1–3 个选项。
- **带 `next` 的选项（分支）的 `effects` 必须是空数组 `[]`**，效果只能写在终点选项（没有 `next` 的选项）上。
- **每个终点选项都要设置“见过了”的标记**（如 `story.met_sax_man`），否则对应事件会反复判断。
- `channel` 的含义：
  - `in_person`：说话人必须和玩家在同一张地图上，需要 `speaker_id`；
  - `phone`：打电话，在哪都能接，也需要 `speaker_id`；
  - `narration`：旁白，不需要说话人。
- 闲聊树：只有一个 `start` 节点，一个选项，效果通常是 `change_relationship` +2，并设为 `"repeatable": true`。

### 效果白名单（`effects`）

| type | 字段 | 限制 |
|---|---|---|
| `set_flag` | `key`, `value` | key 以 `story.` 开头；value 为 bool、int 或 string |
| `credit_money` | `amount` | 1–20000 分 |
| `debit_money` | `amount` | 1–20000 分；玩家钱不够时这个选项会失败，不会扣成负数 |
| `change_need` | `need_id`, `delta` | ±50 |
| `change_relationship` | `npc_id`, `delta` | ±20 |
| `give_item` | `item_id`, `count` | 1–3 个，物品必须存在 |
| `show_summary` | — | 只能写在事件里（周总结用），对话里不能用 |

同一个选项里的效果是一起生效的：其中任何一个失败，整个选项都不生效。

---

## 5. 让它发生：事件（`events.json`）

```json
{
  "id": "event_sax_man",
  "city_id": "CN_LINCHUAN",
  "priority": 40,
  "once": true,
  "conditions": [
    {"type": "day_at_least", "value": 5},
    {"type": "npc_nearby", "npc_id": "npc_sax_man"},
    {"type": "flag_equals", "key": "story.met_sax_man", "value": false}
  ],
  "effects": [],
  "dialogue_tree_id": "dialogue_sax_man_intro"
}
```

- `once` 必须为 `true`。
- 同时满足条件的事件，`priority` 高的先触发。日常小故事建议 30–50；到达、欠租这类系统事件是 60–100。
- **`npc_nearby` 是当面剧情的标准写法**：玩家进入 NPC 视野（16 格）后，NPC 头顶冒“！”，玩家被定住，NPC 走过来，然后打开对话。只要写上这个条件，过场自动发生，不用写代码。
- 不需要人物在场的剧情（电话、旁白）：去掉 `npc_nearby`，改用时间条件，对话树的 `channel` 用 `phone` 或 `narration`。

### 条件白名单（`conditions`，全部满足才触发）

| type | 字段 | 含义 |
|---|---|---|
| `day_at_least` | `value` | 第几天及以后 |
| `minute_of_day_at_least` / `minute_of_day_before` | `value` | 时段（分钟） |
| `wallet_at_least` / `wallet_below` | `value` | 现金（分） |
| `need_above` / `need_below` | `need_id`, `value` | 需求值 |
| `relationship_at_least` | `npc_id`, `value` | 和某人的关系 |
| `any_relationship_at_least` | `value` | 和任何人的关系 |
| `flag_equals` | `key`, `value` | 剧情标记 |
| `lease_active` / `rent_overdue` | `value`（bool） | 租房状态 |
| `rent_periods_paid_at_least` | `value` | 已交几期房租 |
| `shifts_booked_at_least` / `shifts_completed_at_least` / `shifts_completed_below` | `value` | 打工次数 |
| `stat_at_least` | `key`, `value` | 统计值 |
| `on_map` | `map_id` | 玩家在哪张地图 |
| `npc_present` | `npc_id` | NPC 在玩家当前地图上 |
| `npc_nearby` | `npc_id` | NPC 就在玩家身边（触发走过来的过场） |
| `event_fired` | `event_id` | 另一个事件已发生（用来串剧情） |

做连续剧情：第二段事件写上 `event_fired` 指向第一段，或者 `flag_equals` 某个第一段设置的标记，再加上 `day_at_least`。

---

## 6. 文本（`text.json`）和路人

每个 `*_key` 都要在 `text.json` 里有一条记录。`zh_CN` 必填，`en` 可选但建议写（不写时英文界面显示中文）：

```json
{"id": "npc.sax_man.name", "zh_CN": "萨克斯大叔", "en": "Sax Man"},
{"id": "dlg.sax_intro.start", "zh_CN": "长椅边，一位大叔吹着一首老歌……", "en": "By the bench, a man is playing an old tune on the sax…"}
```

- 选项文字写成玩家说的话或做的动作，例如 `“请您吃碗面吧。”（花 ¥25）`。会花钱的选项要在文字里写明金额。
- 风格：日常、克制、口语化。不写暴力、色情、政治内容，也不出现真实品牌或真人。

**路人**（只有一句话的背景人物，不进剧情）：在 `maps/<地图>.json` 的 `pedestrians` 数组里加一条，字段参考同一文件里已有的路人。注意：
- `path` 每一段必须横平竖直，经过的每一格都必须是可走的地面，否则报 `E_MAP_PATH` / `E_MAP_BLOCKED`；
- `lines` 里的 key 同样要写进 `text.json`。

---

## 7. 验证

1. **内容校验**（几秒）：
   ```bash
   godot --headless --path . --import >/dev/null 2>&1
   godot --headless --path . --quit-after 5 2>&1 | grep "content:"
   ```
   没有输出就是通过。有输出时，每行都会给出文件、JSON 路径和错误码，例如 `E_UNKNOWN_REF`（引用了不存在的 id）、`E_REQUIRED`（缺字段）、`E_STORY_EFFECT_ON_BRANCH`（分支选项上写了效果）、`E_STORY_AUTHORITY`（超出数值上限）。

2. **推荐：加一个测试**，放在 `tests/test_story_<名字>.gd`，照抄 `tests/test_street_life.gd` 的写法：
   ```gdscript
   extends "res://tests/framework/test_case.gd"
   const Sessions := preload("res://tests/framework/session_factory.gd")
   const P := SimulationSession.PLAYER_ID

   func test_sax_man_treat() -> void:
       var s := Sessions.create({"story_enabled": true})
       s.submit("advance_time", {"minutes": GameClock.minute_from_day_time(5, 19, 30) - s.world.clock.get_minute()}, "system")
       assert_true(s.submit("approach_npc", {"npc_id": "npc_sax_man"}).ok)
       assert_true(s.events.has_fired("event_sax_man"))
       var cash := s.economy.get_balance(P)
       s.submit("choose_dialogue", {"tree_id": "dialogue_sax_man_intro", "node_id": "start", "choice_id": "listen"})
       assert_true(s.submit("choose_dialogue", {"tree_id": "dialogue_sax_man_intro", "node_id": "treat", "choice_id": "pay"}).ok)
       assert_eq(cash - s.economy.get_balance(P), 2500)
   ```
   - GDScript 用 **tab 缩进**（上面示例为了排版用了空格，复制时要换成 tab）。
   - 测试会话默认 `story_enabled=false`，测剧情要传 `{"story_enabled": true}`。
   - 默认也关闭了需求后果（`need_effects=false`）。
   - 快进时间用 `advance_time`；要去别的地图用 `Sessions.go(s, "<location_id>")`。
   - 只跑这一个文件：`godot --headless --path . -s res://tests/run_tests.gd -- --filter=test_story_<名字>`。

3. **完整检查**：`./tools/check.sh`，必须看到 `ALL CHECKS PASSED`。它依次做导入、全部测试、启动、世界、导出包冒烟，还会拦截布局警告和资源泄漏。

---

## 8. 提交和推送

```bash
git pull --rebase            # 有冲突时，JSON 数组两边的新增都保留，不要删掉别人的记录
./tools/check.sh             # 合并后再跑一次
git add -A
git commit -m "Story: <一句话描述>" -m "<新增了哪些 NPC / 事件 / 对话，主要选择和后果>"
git push
```

- 直接在 `main` 上提交推送，这是本仓库的现行做法。
- 提交前用 `git status` 看一眼：不要提交 `override.cfg`、录像、临时脚本（例如 `tools/_*.gd`）。
- 写一行玩家可感知的变更到 `docs/changelog.md` 最上面的版本下。如果最上面的版本已经发布，就新开一个小版本号，同时改 `project.godot` 里的 `config/version`。
- 汇报时如实写出 `check.sh` 的结果（测试通过数）。

---

## 9. 什么时候不能只改 JSON

下面这些需要改代码，属于功能开发，先在 `docs/decisions.md` 记一条 D-xxx，并补测试：
- 新的条件或效果类型：改 `scripts/content/content_schemas.gd`（`CONDITION_TYPES` / `EFFECT_TYPES` / `EFFECT`）、`scripts/narrative/story_validator.gd`（字段和上限）、`story_conditions.gd` 或 `story_effects.gd`（实现）。效果必须通过对应的系统写入，在 CommandProcessor 的命令里执行。
- 新地点或新地图：改 `locations.json` 和 `maps/`，涉及地图校验。
- 新小游戏：见 D-038，`scripts/minigames/` 加脚本，在 `minigame_registry.gd` 登记一行。

项目硬性规则（不要违反）：
- 运行时不接大模型，不接网络或付费 SDK；
- 钱用整数“分”；
- 只能通过 CommandProcessor 修改世界状态；
- 代码里不写 `if country == "CN"` 这类地区判断，地区差异放进内容包；
- 不使用有版权的素材，不复刻具体的现有游戏。

---

## 10. 动手前自查

- [ ] 新 NPC 有 `dialogue_tree_id` 和 `chat_tree_id`，两棵树都存在
- [ ] 第一个节点叫 `start`；分支选项的 `effects` 为 `[]`
- [ ] 每个终点选项都设置了“见过了”的 `story.` 标记，事件条件里用 `flag_equals ... false` 检查它
- [ ] 事件写了 `"once": true`
- [ ] 所有 key 都在 `text.json` 里（`zh_CN` 必填，`en` 建议写）
- [ ] 钱、需求、关系、物品数量都在上限内
- [ ] 内容校验无输出，`./tools/check.sh` 显示 ALL CHECKS PASSED
- [ ] changelog 已更新，已提交并推送
