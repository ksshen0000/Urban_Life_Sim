# Everyday City（工作名）

都市普通人生活模拟：单机、2D、俯视角、日程驱动。首发场景为虚构中国城市「临川市」，架构为后续美国 / 欧洲各国城市内容包预留。

> 当前状态：**M4 完成**（T001–T020）。7 天谋生循环可以完整玩通：租房、找工作、通勤上班、购物吃饭、和 NPC 来往、第 7 天的阶段总结，并有新手指引。另外已有 3 个存档位、设置（音量、窗口、中英文界面）和发布流程。正式安装包需要先安装 Godot 导出模板，见下方“发布构建”。进度见 [`docs/agent_progress.md`](docs/agent_progress.md)，数值调整见 [`docs/balance.md`](docs/balance.md)。

## 运行

需要 **Godot 4.7.2 stable**（标准版，非 .NET）。

```bash
# 编辑器打开
godot --path . --editor

# 直接运行
godot --path .

# 全部检查：导入 → 无头测试 → 主场景启动 → 导出资源包并在项目外跑冒烟测试；任何引擎/脚本错误都会失败
./tools/check.sh
# 只跑部分测试
./tools/check.sh --filter=input

# 截图检查界面（需要显示器，会短暂弹出一个窗口）
godot --path . -s res://tools/screenshot.gd -- --out=/tmp/shots --size=1280x720

# 平衡报告：7 种玩法各玩一周，打印钱 / 班次 / 需求对比表
godot --headless --path . -s res://tools/balance_report.gd
```

首次在新检出的仓库上跑测试前，`check.sh` 会先执行 `godot --headless --import` 生成 `.godot/` 缓存（`class_name` 全局类依赖它）。

## 操作

| 按键 | 动作 |
|---|---|
| `W A S D` / 方向键 | 移动 |
| `E` | 交互 |
| `Esc` | 暂停菜单（保存、读取、设置、返回标题） |
| `I` | 背包 |
| `J` | 日志（任务、班次、住处、认识的人） |

## 目录

```text
assets/        占位美术、UI 主题
content/       数据驱动内容包（common/ 通用规则与文案，regions/cn/ 中国，cities/linchuan/ 地图·岗位·房源·线路·NPC·对话·事件·任务）
scenes/        Godot 场景（boot/ world/ interiors/ ui/）
scripts/       app/ kernel/ simulation/ narrative/ regions/ content/ persistence/ world/ ui/（intelligence/ 待 v0.2）
tests/         无头测试（framework/ 为零依赖断言基类，run_tests.gd 为执行器）
tools/         check.sh、balance_report.gd、screenshot.gd（需要显示器）、sprite_sheet.gd（无界面导出人物总览图）、build_release.sh
docs/          PRODUCT_SPEC.md、decisions.md、agent_progress.md、changelog.md、balance.md、RELEASE_README.txt（随安装包附带的玩家说明）
```

## 存档与设置

- 存档：`user://saves/slot_01..03.json`，纯 JSON。写入时先写临时文件并完整校验，再替换旧档，上一份旧档保留为 `.bak`。读档时会校验内容包、城市、货币、数值范围和所有 ID，失败不会影响正在进行的游戏。格式与迁移规则见 D-026。
- 设置：`user://settings.cfg`（D-028）。
- `user://` 的实际位置：Linux 为 `~/.local/share/godot/app_userdata/Everyday City/`，Windows 为 `%APPDATA%\Godot\app_userdata\Everyday City\`。

## 发布构建

```bash
tools/build_release.sh   # → build/EverydayCity-<版本>-linux-x86_64.zip、…-windows-x86_64.zip
```

需要先安装与引擎版本一致的官方导出模板（Godot 4.7.2.stable）：在编辑器里打开 *Editor → Manage Export Templates* 下载，或把 `Godot_v4.7.2-stable_export_templates.tpz` 解压到 `~/.local/share/godot/export_templates/4.7.2.stable/`。脚本会先跑 `check.sh`，导出后在空目录里对 Linux 版跑冒烟测试，最后把 `docs/RELEASE_README.txt` 一起打进 zip。安装包是单文件，不需要编辑器，也不联网。在任何机器上都可以用 `EverydayCity --headless -- --smoke-test` 自检。

## 内容包

每个内容包是 `content/` 下含 `pack.json` 的目录，声明 `pack_id`、版本、`scope`（地区/国家/城市）、依赖、数据文件（文件 → 表）和故事提供者元数据。表结构定义在 `scripts/content/content_schemas.gd`。加载时一次性报告全部错误（文件 + JSON 指针 + 错误码），任何错误都会导致整体加载失败。新增城市只需添加内容包与地区规则配置，详见 `docs/decisions.md` D-008、D-010。

## 架构总览

```text
UI / 场景 ──ActionProposal──▶ CommandProcessor ──▶ WorldState（clock, …） + DomainEvent
                                  │ authorize → validate → apply（失败整体回滚）
                                  └─ committed ──▶ GameEventBus 信号（仅通知，非事实来源）
ContentRegistry（数据） ──▶ RegionPolicyRegistry ──▶ RegionPolicy（如何结算）
```

分层见 `docs/PRODUCT_SPEC.md` §2.1 与 §13：Godot 只负责展示与输入；权威世界状态只经由 `CommandProcessor` 写入；地区差异由 `RegionPolicy` + 内容包提供；NPC 决策与剧情通过可替换的 Policy / Provider 接口（当前为规则与模板实现，不调用任何 LLM）。重要取舍记录在 `docs/decisions.md`。

## 许可证

尚未选定（见 `docs/decisions.md` D-006）。在选定前，默认保留所有权利。项目不包含第三方素材；中文字体使用玩家系统字体（D-003）。
