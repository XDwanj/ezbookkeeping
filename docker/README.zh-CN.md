# Docker / GHCR 部署（fork 仓库）

项目已有 Dockerfile，默认以 `1000:1000` 运行。此配置在仓库根目录提供
Docker Compose 部署，并为 fork 增加独立的 GHCR 发布流程；无需配置上游的
Docker Hub 账号，也不修改原有 Docker Hub 工作流。

## 1. 发布自己的 GHCR 镜像

将本次改动推送到自己的 GitHub 仓库后，在 Actions 中确认工作流已启用。
`Build and Publish GHCR Image` 在以下场景构建镜像：

| 触发方式 | 镜像标签 |
| --- | --- |
| 推送到 `main`（默认分支） | `latest-snapshot`、`main`、`sha-<短提交号>` |
| 推送正式版本标签，如 `v1.2.3` | `1.2.3`、`1.2`、`latest`、`sha-<短提交号>` |
| Actions → Run workflow | 所选分支或版本对应的标签；非默认分支不覆盖 `latest-snapshot` |

预发布版本只生成对应预发布版本标签及提交标签，不覆盖 `latest`。
镜像仓库名称自动取当前仓库的小写形式：本 fork 为
`ghcr.io/xdwanj/ezbookkeeping`。构建复用现有 Dockerfile 和 Bake 配置，当前
GHCR 发布仅支持 `linux/amd64`（x86-64），使用 x86 runner 原生编译，不使用
QEMU，也不构建 ARM 镜像。上游原有的多架构 Bake 目标保持不变。

认证使用 GitHub 自动提供的 `GITHUB_TOKEN`，工作流声明 `packages: write`，
不需要手工添加 Docker Hub 密码或发布 PAT。若仓库/组织策略禁止写入 Packages，
需要在 GitHub 设置中开放对应权限。

首次发布后，GHCR package 可能为 private。若需要匿名拉取，在 GitHub 的
Packages 页面将该 package 的可见性设为 public；若保留 private，部署机器需先
通过 `docker login ghcr.io` 登录（使用具有 `read:packages` 权限的 personal access
token classic）。公开 GitHub 仓库不等于镜像自动公开。

以上认证方式见 [GitHub 官方镜像发布文档](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images)。

## 2. 从仓库根目录部署

在云服务器上安装 Docker Engine 和 Docker Compose。只需将仓库中的
`compose.yaml` 和 `.env.example` 放到同一个部署目录，无需安装 Go、Node.js
或在云服务器编译源码。先等待上述工作流成功发布镜像，然后在部署目录执行：

```sh
cp .env.example .env
openssl rand -hex 32
```

编辑 `.env`：

- 将生成的随机字符串填入 `EBK_SECURITY_SECRET_KEY`，后续升级保持不变。
- 将 `EBK_SERVER_ROOT_URL` 改为实际访问地址，例如 `http://192.168.1.10:8080/`
  或反向代理的 `https://book.example.com/`。
- 如果修改 `EBK_PORT`，同步调整访问地址中的端口。
- 如果部署其他 fork，将 `EBK_IMAGE` 改成自己的 GHCR 镜像地址（全小写）。
- 如需容器内以 root 运行，将 `EBK_CONTAINER_USER` 改成 `0:0`。

```sh
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose logs -f --tail=100
```

默认访问 `http://localhost:8080/`。`.env` 已被 Git 和 Docker 构建上下文忽略。
Compose 不挂载整个 `conf` 目录，避免空挂载覆盖镜像内置配置；当前部署参数通过
应用现有的 `EBK_*` 环境变量传入，无 HTTP API 入参或出参变更。

### root 运行选项

```diff
-EBK_CONTAINER_USER=1000:1000
+EBK_CONTAINER_USER=0:0
```

修改后运行 `docker compose up -d` 重建容器即可，不需要单独的 root 镜像，
也不需要 `privileged: true`。宿主机使用 root 执行 Docker 命令，并不代表
容器内进程就是 root。

默认使用三个 Docker 命名卷保存数据库、日志和附件，新卷继承镜像内的目录权限。
如果先以 root 写入数据，再切回 `1000:1000`，应先停止服务，并将卷内文件所有者
调整为 `1000:1000`，否则可能出现写入权限错误。挂载已有宿主机目录时，也需确保
所选容器用户有读写权限。

## 3. 更新与持久化

```sh
docker compose pull
docker compose up -d
```

更新不会删除命名卷。`docker compose down` 保留数据；
`docker compose down -v` 会删除数据卷，不要用它进行普通升级。
正式部署可将 `EBK_IMAGE` 固定到版本标签或提交标签。升级前应备份数据库和附件。

```mermaid
flowchart LR
    A[自己的 GitHub fork] --> B[GitHub Actions 构建]
    B --> C[自己的 GHCR AMD64 镜像]
    C --> D[根目录 Docker Compose]
    D --> E[应用进程：UID 1000 或 root]
    E --> F[命名卷：数据库 / 日志 / 附件]
```

## 4. 本地构建（无需发布 GHCR）

```sh
docker build -t ezbookkeeping:local .
EBK_IMAGE=ezbookkeeping:local docker compose up -d --pull never
```

本地构建仍需访问 Docker 基础镜像、Go 模块及 npm 依赖服务。
如使用 Docker Bake，请显式指定构建文件：
`docker buildx bake -f docker-bake.hcl image-local`。否则 Bake 会同时读取
根目录 Compose 文件，并要求提供部署用的 `EBK_SECURITY_SECRET_KEY`。
