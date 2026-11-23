# Agent 须知（Everyday City / 临川市七日生活）

Godot 4.7 的 2D 像素风城市生活模拟。产品规格见 `docs/PRODUCT_SPEC.md`，已做的设计决定见 `docs/decisions.md`（D-xxx）。

- **加剧情、NPC、对话、事件、路人**：先读 `docs/STORY_AUTHORING.md`，按里面的流程只改 JSON，验证后提交推送。
- **验证**：`./tools/check.sh` 必须输出 `ALL CHECKS PASSED`；如实报告结果，没跑过就不要说通过。
- **硬性规则**：
  - 运行时不接大模型，不接网络或付费 SDK；
  - 钱用整数“分”；
  - 只能通过 CommandProcessor 修改世界状态；
  - 代码里不写地区判断（如 `if country == "CN"`），地区差异放进内容包；
  - 不使用有版权的素材，不复刻现有游戏。
- **默认决定**：无关紧要的选择自己定，并在 `docs/decisions.md` 记一条 D-xxx，不必停下来问。
- **玩家可感知的改动**：写进 `docs/changelog.md`。
