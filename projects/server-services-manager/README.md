# server-services-manager

通过浏览器界面管理、启动、监控其他服务的 Web 服务管理器镜像。

## 原始项目

[server-services-manager](https://github.com/samosa-ai-com/server-services-manager) 是实现上述功能的开源项目本体——Python（Flask + Flask-SocketIO）编写的 Web 服务管理器：在浏览器中管理（启动、停止、监控）宿主机上的其他服务，支持查看进程运行状态与终端输出。

- 上游仓库：<https://github.com/samosa-ai-com/server-services-manager>
- 上游技术栈：Python（Flask + Flask-SocketIO）
- 上游未发布官方 Docker 镜像，本镜像由 image-hub 提供并持续构建

## 镜像信息

- 镜像：`ghcr.io/bookandmusic/server-services-manager`
- 架构：`linux/amd64`、`linux/arm64`
- 端口：`8881`（HTTP 管理界面）
- 健康检查：每 30s 请求 `GET /health`，连续失败 3 次标记 unhealthy

## 运行

```bash
docker run -d --name ssm \
  -p 8881:8881 \
  -v /宿主机数据目录:/root \
  -e PASSWORD=你的密码 \
  ghcr.io/bookandmusic/server-services-manager:latest
```

启动后浏览器访问 `http://localhost:8881`，使用 `PASSWORD` 登录。

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PASSWORD` | `admin` | 登录密码 |
| `SECRET_KEY` | `change-me` | session 密钥，生产环境务必用随机串覆盖 |
| `CORS_ORIGIN` | `*` | 允许的跨域来源 |

## 数据持久化

`/root` 整个家目录已声明为 VOLUME，建议用 `-v /宿主机数据目录:/root` 挂载：

- npx / npm -g / uv / uvx 的缓存与全局安装目录（`~/.npm`、`~/.npm-global`、`~/.cache/uv`、`~/.local`）
- 服务自身状态（`~/.server-services-manager/state.json`）
- 未来新增工具或服务写在 `/root` 下的数据

容器重建后数据不丢。uv/uvx 二进制位于 `/usr/local/bin`（镜像层），不受该挂载影响。

## 内置工具

- **Python 3.14 虚拟环境** `/opt/venv`：应用自身依赖全部隔离于此，不污染系统 Python（被管理服务可自由使用系统 Python）
- **Node.js 24 LTS**（`/opt/node`）：`npm install -g` / `npx` 全局安装到 `/root/.npm-global`
- **uv / uvx**（`/usr/local/bin`）：Python 包与工具管理，缓存与工具数据在 `/root` 下
