# Agent 接入与生成选项

在论文对话栏的提供方菜单选择 Agent。连接设置可编辑程序绝对路径。各 Agent 使用自己的 CLI 登录配置，先在终端完成其安装与登录。模型和生成选项按提供方保存，下一次发送使用当前设置快照。

| 提供方 | 接入方式 | 模型与生成选项 |
| --- | --- | --- |
| Codex | 原有 App Server | `model/list` 返回模型及支持的思考强度。发送 `turn/start.effort`，快速模式发送 `thread/start.serviceTier = fast`。 |
| Claude Code | `claude --print --input-format stream-json --output-format stream-json` | 原生 `--model`、`--effort`，快速模式通过临时 `--settings` 的 `fastMode` 设置。模型菜单列出 CLI 别名 sonnet、opus、haiku，也可输入完整模型名。 |
| Qwen Code | `qwen --acp` | 读取 `session/new` 的模型及 `configOptions`，通过 `session/set_config_option` 应用。旧模型接口回退至 `session/set_model`。 |
| DeepSeek Harness | `dsh --profile acp` | 同一 ACP 配置流程。需要包含 ACP profile 的已安装版本。 |
| WorkBuddy | `codebuddy --acp` | 使用 CodeBuddy ACP 后端。该入口连接 CodeBuddy CLI 的 ACP 会话。需要可执行的 codebuddy CLI 及其登录配置。 |
| 云端 API / 本地 HTTP | OpenAI 兼容 Chat Completions | 可选 `reasoning_effort`。保持默认时省略参数。模型服务决定是否支持选中的强度。 |

ACP 的思考、推理和速度菜单来自 Agent 提供的 select 配置项。权限和审批模式排除在生成选项之外。切换 ACP 模型后重新读取对应选项。Codex 和 Claude Code 的快速模式仍由模型和账号权益决定，可能产生不同计费。

## 研究工具与文件边界

新 CLI 接口通过独立 stdio MCP helper 使用应用的研究工具。每轮创建权限为 0700 的临时邮箱目录，JSON 请求和响应原子写入，轮次结束后移除。工具名称必须匹配应用提供的列表，笔记修改继续产生待确认的差异预览。引用、下载和笔记写入复用现有 `AIController` 工具处理。

Claude Code 禁用内置工具，启用严格 MCP 配置和临时 hook 禁用设置。ACP 客户端拒绝文件读写和终端能力，审批仅允许明确命名的研究 MCP 工具。CLI 子进程通过 macOS sandbox-exec 限制写入临时目录与 Agent 自身的配置目录，并限制可执行程序为 Agent、Node、应用 MCP helper 及凭证辅助程序。工具下载通过宿主应用写入当前工作区。

每次请求包含应用保存的最近对话和当前论文上下文。应用管理对话恢复，新 Agent 子进程使用独立临时工作目录。取消生成关闭进程、取消研究工具并清理邮箱。原生 Agent 会话 ID 不在不同提供方间转移。

## 依赖与协议依据

本次采用已安装 CLI，无新增 Swift/npm 包依赖。Qwen Code 的公开代码采用 Apache-2.0，DeepSeek Harness 采用 MIT。Claude Code 和 CodeBuddy 的可执行程序由用户按各自发行条款安装，应用包不附带这些程序。

- [Claude Code CLI 官方参考](https://code.claude.com/docs/en/cli-reference)
- [Claude Code 快速模式说明](https://code.claude.com/docs/en/fast-mode)
- [Qwen Code 官方配置与 ACP 参数](https://github.com/QwenLM/qwen-code/blob/main/docs/users/configuration/settings.md)
- [DeepSeek Harness 官方 CLI 帮助](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/cli-help.md)
- [CodeBuddy 官方 ACP 文档](https://www.codebuddy.ai/docs/cli/acp)
- [ACP 会话与 MCP 配置](https://agentclientprotocol.com/protocol/v1/session-setup)
- [ACP 生成配置选项](https://agentclientprotocol.com/protocol/v1/session-config-options)
- [MCP stdio 传输规范](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)

## 本轮验收边界

遵照用户要求，未运行自动化功能测试、界面测试或真实 Agent 推理。本轮执行 Swift 编译、离线编辑器构建与应用打包检查。协议实现、沙盒与各 CLI 版本的真实互通仍待后续运行验证。
