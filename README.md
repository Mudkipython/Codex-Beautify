# Codex Beautify

为 macOS 上的 ChatGPT / Codex 桌面应用添加龙娘启动动画与半身角色图标。

基于 [yushua0808-cpu/dragon-codex-boot](https://github.com/yushua0808-cpu/dragon-codex-boot) 二次开发，感谢原作者及贡献者提供启动器、龙娘演示动画、跨平台实现和测试基础。上游说明保留在 [docs/UPSTREAM-README.md](docs/UPSTREAM-README.md)。本项目为独立社区项目，与 OpenAI 无隶属关系。

![图标原画](assets/dragon-chibi.png)

## 默认体验

- 手动打开龙娘启动器，播放约 14 秒的本地动画，同时启动新版统一 ChatGPT 桌面应用。
- 默认请求进入 **Codex**，支持 Esc、Command+. 和按钮跳过。
- 冷启动等待主窗口；窗口消失时尝试重新激活；媒体卡顿和应用等待有超时保护。
- 默认不安装后台监视器、不设置登录自启，动画结束后启动器退出。
- 半身角色图标直接裁切原始透明立绘，保留人物配色，搭配靛蓝渐变圆角底板。

## 构建与安装（Apple Silicon）

需要 macOS 13+、Xcode Command Line Tools，以及已安装的新版 ChatGPT / Codex（应用标识 `com.openai.codex`）。

```bash
git clone https://github.com/Mudkipython/Codex-Beautify.git
cd Codex-Beautify
./scripts/test-macos-standalone.sh
mkdir -p "$HOME/Applications"
ditto "build/macos/Dragon Codex Boot.app" "$HOME/Applications/Dragon Codex Boot.app"
open "$HOME/Applications/Dragon Codex Boot.app"
```

构建和运行不需要 API Key 或第三方运行时。应用使用本机 ad-hoc 签名，未作 Developer ID 公证。输出路径和内部名称沿用上游，避免影响已有安装。

打包：`./scripts/package-macos-standalone.sh`，ZIP 和 SHA-256 位于 `dist/`。生成的程序包默认不提交 Git；自行构建即可获得完整可运行 App。

普通 Chat 与 Codex 共用一个新版客户端。此版本使用本机应用支持的 `codex://new?mode=codex` 进入 Codex 新对话；这是客户端实现中的链接行为，未来更新可能变化。启动器不会改写官方应用包。

## 可选：点击官方图标时自动播放

默认不开启。若希望监视客户端冷启动：

```bash
./scripts/install-chatgpt-watcher.sh
```

这会增加当前用户的 LaunchAgent，登录后常驻监听应用启动事件。已运行应用再次激活时不重播；它是外部覆盖动画，不替换官方内部加载页面。停用：

```bash
./scripts/uninstall-chatgpt-watcher.sh
```

卸载手动版只需删除 `~/Applications/Dragon Codex Boot.app`；若启用了监视器，请先停用它。

## 验证与已知边界

本地已通过构建、arm64 架构、签名、媒体一致性、ZIP 往返和播放看门狗检查。已验证完整播放、立即跳过、进入 Codex，以及隔离应用中首次启动退出、延迟窗口、重新激活才出现窗口等场景。

真实宿主应用完全退出后的冷启动仍需用户复测。窗口就绪检测是启发式判断，不代表后台任务全部加载；多屏、全屏、最小化及所有快捷键组合未完成全面实机验收。诊断日志位于系统临时目录的 `local.dragoncodexboot.macos/last-run.log`。

## 上游实现与致谢

完整保留上游 Windows WPF/DWM 实现、另一套 macOS 可配置实现、工具脚本与测试。这里的主要定制集中在 `src/macos/` 的独立启动器；Windows 实现未在本机运行验证。上游完整 macOS 实现见 [docs/MACOS.md](docs/MACOS.md)，与本项目默认独立版本是不同构建入口。

- 原项目：[Dragon Codex Boot](https://github.com/yushua0808-cpu/dragon-codex-boot)。启动器代码、默认演示视频与原音轨来源于该项目。
- 本项目改动：半身图标、Codex 模式跳转、启动／窗口恢复与跳过修复，以及可选轻量启动监视器。
- 代码保留 [MIT LICENSE](LICENSE) 及上游版权声明。
- 媒体许可独立于代码许可，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 [media/MEDIA_NOTICE.md](media/MEDIA_NOTICE.md)。
