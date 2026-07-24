# dev-env-ansible

把一台 Linux 裝成完整開發環境的 Ansible role：baseline 套件、Podman（rootless）、Go、
Claude Code，以及可選的 toolchain（Node、uv、DB/cache clients）。

（git 身分與 SSH keys 不在這裡 —— 由 [`wsl-bootstrap`](../wsl-bootstrap) 在 bring-up 就備好，
因為 key 得先在才能 clone 私有 repo，屬「一台個人機」而非軟體層。）

**Host-agnostic** —— WSL2 專屬的 task 用 `is_wsl` fact gate 起來，所以同一個 role 也能跑在
純 Ubuntu VM、homelab 節點或 WSL distro。搭配 [`wsl-bootstrap`](../wsl-bootstrap)：它產出一台
已開 systemd、可連的 WSL distro，讓你在上面接手裝軟體。

## 檔案結構

```
dev-env-ansible/
├── ansible.cfg
├── site.yml                    # 頂層 playbook
├── inventory/hosts.yml         # 管理的 host
└── roles/dev_env/
    ├── defaults/main.yml       # 可調項（toolchain 開關、go 版本）
    └── tasks/
        ├── detect.yml          # 設定 is_wsl / go_arch / login_uid fact
        ├── base.yml            # baseline apt 套件
        ├── podman.yml          # podman + registries.conf；WSL 部分用 is_wsl gate
        ├── go.yml              # Go binary（冪等：目標版本已在就跳過）
        ├── claude.yml          # Claude Code（native installer）
        ├── node.yml            # nvm + Node        (when: install_node)
        ├── python.yml          # uv               (when: install_python)
        └── clients.yml         # psql, redis-cli, nats (when: install_clients)
```

## 首次設定

前提：distro 已由 [`wsl-bootstrap`](../wsl-bootstrap) 建好，baseline 只有 `git` + `make`
（**沒有 ansible** —— 這個 repo 的 Makefile 第一次跑會自己 `apt install ansible-core`），而且
**git 身分與 SSH keys 在 bring-up 就備好了**（那些不歸這個 role 管）。以下都在 distro 內
執行；`LOCAL` 預設 `1`（對本機跑），不用帶。

**1. 取得這個 repo。** bring-up 已生成 SSH key，貼到 GitHub 後就能直接 clone 私有 repo；最
省事則直接從本機 Windows 複本 clone（零認證）：

```bash
wsl -d dev
git clone /mnt/c/Users/MiskaWu/Projects/dev-env-ansible ~/projects/dev-env-ansible
cd ~/projects/dev-env-ansible
```

**2. 裝軟體。**

```bash
make init     # 補 ansible → 裝 podman/go/claude/toolchain → 印收尾清單
```

（只想預覽先 `make check`；只裝某一項 `make apply TAGS=node`。）

**3. 回 Windows 端 full shutdown。** 讓 rootless `podman.socket` 在乾淨 session 起來
（原因見下）：

```powershell
wsl --shutdown
```

**4. 收尾**（手動接上平台，刻意不自動化）。SSH keys 與 git 身分 bring-up 已備好，剩貼與認證：

```bash
wsl -d dev
cat ~/.ssh/id_ed25519_dev_github.pub    # 貼到 GitHub → Settings → SSH keys（若還沒貼）
cat ~/.ssh/id_ed25519_dev_gitlab.pub    # 貼到 GitLab
claude                                   # 首次 OAuth 認證
# key 貼好後，把本 repo 的 origin 指向 GitHub（之後就能 git pull 更新）：
git remote set-url origin git@github.com:MiskaWu/dev-env-ansible.git
```

驗一下 compose 真的能用：`podman run --rm docker.io/library/hello-world`，或起一個
redis compose 服務測 `redis-cli ping`。

## 之後更新（day-2，不砍重建）

改了 `roles/dev_env/defaults/main.yml`（或 `group_vars`）或 role 本身，就本機重新套用：

```bash
cd ~/projects/dev-env-ansible
git pull                 # 若遠端有更新
make check               # 預覽這次會動什麼（diff）；LOCAL 預設 1，在 distro 內不用帶
make apply               # 套用
make apply TAGS=node     # 或只裝某一項（先把 install_node 改成 true）
```

重跑會收斂（冪等）—— 對已裝好的 host `make check` 應該是 `changed=0`。

## 在 WSL 上：第一次 apply 後為什麼要 `wsl --shutdown`

rootless `podman.socket` 在 apply 時已 enable，但 WSL 的 systemd 有 executor 冷啟動 race
（`Failed to spawn executor: Device or resource busy`），user session 會 degraded、socket
起不來。**只有 full `wsl --shutdown`（不是 `--terminate`）清得掉** —— 重置整個 VM 後，乾淨
session 一來 socket 自動起、`docker-compose` 就能用。這不是安裝失敗，是平台 race。

## 設定

在 `inventory/hosts.yml`、`group_vars/` 或 `host_vars/` 覆蓋預設：

| 變數 | 預設 | 控制 |
|---|---|---|
| `container_runtime` | `podman` | runtime（只實作 `podman` 路徑） |
| `compose_shim` | `true` | `docker-compose` 二進位 + `DOCKER_HOST` |
| `go_version` | `latest` | `latest` 查 go.dev，或 pin 如 `1.26.5` |
| `install_node` / `node_version` | `false` / `lts` | nvm + Node |
| `install_python` | `true` | uv |
| `install_clients` | `true` | `psql`、`redis-cli`、`nats` |

（SSH keys / git 身分的設定在 `wsl-bootstrap` 的 `config.ps1`，不在這裡。）
