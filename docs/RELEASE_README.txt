Everyday City · 临川市七日生活
==============================

一个关于普通人在城市里过日子的小游戏：找住处、上班、吃饭、交房租、认识邻居。
所有城市、人物和数值都是虚构的游戏化设定，不代表真实的工资、税费或法规。

启动
----
- Windows：双击 EverydayCity.exe
- Linux：  双击 EverydayCity.x86_64，或在终端运行 ./EverydayCity.x86_64
不需要安装，不需要联网，不需要 Godot 编辑器。
需要支持 OpenGL 3.3 的显卡（近十年的集成显卡基本都可以）。

操作
----
  W A S D / 方向键   走路
  E                   互动（门、招牌、公告栏、和人说话）
  I                   背包
  J                   日志（当前目标、认识的人、房租）
  Esc                 暂停菜单（保存、读取、设置、返回标题）

左上角始终显示当前目标和具体做法。第一周的目标：交上第一次房租、上两个以上的班、
认识至少一个人。没有“游戏结束”，交不上房租也可以继续想办法。

存档与设置
----------
暂停菜单或出租屋里可以存档，共 3 个位置；标题画面可以读取。
存档只保存在这台电脑上：
  Windows：%APPDATA%\Godot\app_userdata\Everyday City\saves\
  Linux：  ~/.local/share/godot/app_userdata/Everyday City/saves/
保存时先写临时文件并校验，失败不会覆盖原来的存档；上一次的存档会留一份 .bak。
设置（音量、窗口大小、语言）保存在同一目录的 settings.cfg。
英文目前只覆盖界面，剧情文字仍为中文。

自检
----
在终端运行 `./EverydayCity.x86_64 --headless -- --smoke-test`（Windows 为 `EverydayCity.exe --headless -- --smoke-test`），
会自动开一局、存档、读档并比对，输出 SMOKE OK 表示安装完整。不会动你的存档。

----------------------------------------------------------------
Everyday City — a small slice-of-life game set in a fictional Chinese city.
Run EverydayCity.exe (Windows) or ./EverydayCity.x86_64 (Linux). No install, no network.
Move: WASD/arrows · Interact: E · Bag: I · Journal: J · Menu: Esc.
Settings → Language → English switches the interface; story text is Chinese for now.
