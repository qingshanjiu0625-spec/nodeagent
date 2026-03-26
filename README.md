# Docker OpenClaw 快速部署指南

> 基于 Docker 的 OpenClaw 快速部署文档，适用于希望在 **Mac / Linux 服务器 / 云服务器** 上快速完成安装、配置与 Telegram 配对的用户。

## 目录

- [项目简介](#项目简介)
- [支持的平台架构](#支持的平台架构)
- [部署前准备](#部署前准备)
- [获取 API Key](#获取-api-key)
- [服务器推荐](#服务器推荐)
- [快速开始](#快速开始)
- [机器人配对流程](#机器人配对流程)
- [常用命令](#常用命令)
- [常见问题](#常见问题)
- [安全提示](#安全提示)
- [反馈与支持](#反馈与支持)

---

## 项目简介

本指南用于帮助你通过 Docker 快速部署 OpenClaw，并完成以下基本配置：

- 配置 AI 模型服务
- 设置 Web 访问端口
- 绑定 Telegram Bot
- 完成 Telegram 机器人配对

适合以下使用场景：

- 在本地设备快速体验 OpenClaw
- 在云服务器上部署长期运行实例
- 为个人或团队搭建 Telegram 接入能力

---

## 支持的平台架构

当前支持以下芯片架构：

- `linux/amd64`
- `linux/arm64/v8`

请根据你的设备架构选择对应版本进行部署。

---

## 部署前准备

开始前，请先准备以下内容。

### 1. AI 模型 API Key

目前支持以下模型服务：

- NEXOS
- Anthropic Claude
- OpenAI
- Gemini
- Qwen（阿里百炼）
- Volcengine（火山引擎）

### 2. Telegram Bot Token

通过 Telegram 官方机器人 `@BotFather` 创建。

### 3. 一台用于部署的设备

例如：

- Mac mini
- MacBook
- Linux 服务器
- 云服务器

---

## 获取 API Key

你可以任选一种模型服务，并获取对应的 API Key。

### NEXOS

- 官网：`https://nexos.ai`
- 路径：`Dashboard -> API Keys -> Create Key`

示例：

```text
nexos-team-xxxxxxxxxxxx
```

### Anthropic Claude

- 官网：`https://console.anthropic.com/`
- 路径：`API Keys -> Create Key`

示例：

```text
sk-ant-api03-xxxxxxxxxxxx
```

### OpenAI

- 官网：`https://platform.openai.com/api-keys`
- 路径：`Create new secret key`

示例：

```text
sk-proj-xxxxxxxxxxxx
```

### Gemini

- 官网：`https://aistudio.google.com/`
- 路径：`Get API key -> Create API key`

示例：

```text
AIzaSyxxxxxxxxxxxx
```

### Qwen（阿里百炼）

- 官网：`https://bailian.console.aliyun.com/`
- 路径：`Get API key -> Create API key`

注意区分地域：

- 北京
- 新加坡
- 弗吉尼亚

示例：

```text
sk-xxxxxxxxxxxx
```

### Volcengine（火山引擎）

- 官网：`https://console.volcengine.com`
- 进入“大模型服务 / 豆包”
- 创建或查看 API Key

如需开通模型服务，可前往：

`https://console.volcengine.com/ark/`

并找到 **Doubao-Seed-1.8** 开通服务。

---

## 服务器推荐

推荐使用以下平台：

- `https://hpanel.hostinger.com/`
- `https://www.krypt.com/`
- `https://www.vultr.com/`

推荐地区：

- 日本
- 法国
- 德国
- 新加坡
- 马来西亚

> 建议避免选择香港地区，部分场景可能存在限制。

---

## 快速开始

### 第一步：打开终端

#### 如果你使用的是 Mac

1. 打开“启动台”
2. 进入“其他”文件夹
3. 点击“终端”
4. 打开后会看到一个黑色窗口，这就是终端

#### 如果你使用的是服务器

1. 使用 SSH 工具连接服务器，例如：
   - Xshell
   - FinalShell
   - Termius
2. 登录后，如果当前账号不是 `root`，执行：

```bash
sudo su
```

3. 按回车
4. 如果系统提示输入密码，请输入登录密码
5. 切换到 `root` 后继续执行后续安装步骤

---

### 第二步：执行安装命令

在终端中运行以下命令：

```bash
curl -fsSL https://raw.githubusercontent.com/qingshanjiu0625-spec/nodeagent/refs/heads/main/setup.sh | bash
```

---

### 第三步：按提示完成配置

安装过程中需要依次完成以下配置：

1. 设置 Web 访问端口  
   默认端口为 `62430`，可直接回车使用默认值

2. 选择 AI 模型并输入对应 API Key

3. 输入 Telegram Bot Token

4. 安装完成后，通过浏览器访问系统  
   如果部署在公网服务器，请将 `127.0.0.1` 替换为服务器公网 IP

---

## 机器人配对流程

完成部署后，按以下步骤完成 Telegram 机器人配对：

1. 搜索机器人：`@qingshxx_agent002_bot`
2. 发送命令：

```text
/start
```

3. 再发送：

```text
1
```

4. 获取配对 ID 后，进入容器：

```bash
nodeagent enter
```

5. 执行配对命令：

```bash
openclaw pairing approve telegram <配对ID>
```

6. 配对完成后退出容器：

```bash
exit
```

7. 如果出现 `access not configured`，请重启服务：

```bash
nodeagent restart
```

重启后返回 Telegram 机器人查看是否提示配对成功。

---

## 常用命令

首次使用快捷命令前，请先执行：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## 常见问题

### 1. 浏览器打不开页面怎么办？

请优先检查以下内容：

- Web 端口是否配置正确
- 服务器安全组是否已放行对应端口
- 本机或服务器防火墙是否拦截访问
- 是否将 `127.0.0.1` 正确替换为公网 IP

### 2. 出现 `access not configured` 怎么办？

通常可以尝试重启服务：

```bash
nodeagent restart
```

重启后重新返回 Telegram 机器人查看状态。

### 3. API Key 填写后仍无法调用模型怎么办？

建议检查：

- API Key 是否复制完整
- 模型服务是否已开通
- 所选区域是否正确
- 服务器网络是否可访问对应模型平台

### 4. 非 root 用户可以安装吗？

可以，但在安装阶段通常建议先切换为 `root`，以避免权限问题：

```bash
sudo su
```

---

## 安全提示

请务必注意以下事项：

- 不要将 API Key、Bot Token 等敏感信息提交到公开仓库
- 建议为公网服务器配置防火墙与最小权限访问策略
- 建议定期轮换密钥，降低泄露风险
- 在公开演示或截图时，注意打码敏感配置内容

---

## 反馈与支持

如在部署过程中遇到问题，欢迎反馈。

本文档将持续更新和优化。
