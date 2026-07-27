# dev-env-ansible

把一台 Linux 裝成完整開發環境的 Ansible role：baseline 套件、Podman（rootless）、Go、
Claude Code，以及可選的 toolchain（uv、DB/cache clients）。

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
    ├── defaults/main.yml       # 可調項（toolchain 開關、Go 版本）
    ├── templates/              # containers 設定 drop-in、systemd unit
    └── tasks/
        ├── detect.yml          # 設定 is_wsl / dev_env_arch fact
        ├── base.yml            # baseline apt 套件
        ├── podman.yml          # podman + .d drop-in；WSL 部分用 is_wsl gate
        ├── go.yml              # Go binary（冪等：目標版本已在就跳過）
        ├── claude.yml          # Claude Code（native installer）
        ├── python.yml          # uv              (when: install_python)
        ├── clients.yml         # psql, redis-cli (when: install_clients)
        └── profile.yml         # ~/.profile 的單一 managed block（PATH / 環境變數）
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

（只想預覽先 `make check`；只裝某一項 `make apply TAGS=python`。可用的 tag：`base`、
`podman`、`go`、`claude`、`python`、`clients`、`profile`。**注意 ansible 對不存在的 tag
不會報錯，只會什麼都不做** —— 打錯字會靜默無事發生。）

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

驗一下 podman 真的能用：`podman run --rm docker.io/library/hello-world`；要連帶驗
rootless 網路與 DNS，起一個容器測 `redis-cli ping`。

## 之後更新（day-2，不砍重建）

改了 `roles/dev_env/defaults/main.yml`（或 `group_vars`）或 role 本身，就本機重新套用：

```bash
cd ~/projects/dev-env-ansible
git pull                 # 若遠端有更新
make check               # 預覽這次會動什麼（diff）；LOCAL 預設 1，在 distro 內不用帶
make apply               # 套用
make apply TAGS=python   # 或只跑某一段
```

重跑會收斂（冪等）—— 對已裝好的 host `make check` 應該是 `changed=0`。

## 在 WSL 上：第一次 apply 後為什麼要 `wsl --shutdown`

rootless `podman.socket` 在 apply 時已 enable，但 WSL 的 systemd 有 executor 冷啟動 race
（`Failed to spawn executor: Device or resource busy`），user session 會 degraded、socket
起不來。**只有 full `wsl --shutdown`（不是 `--terminate`）清得掉** —— 重置整個 VM 後，乾淨
session 一來 socket 自動起、`DOCKER_HOST` 指得到的東西就活了。這不是安裝失敗，是平台 race。

## 版本管理：為什麼沒有 mise / nvm / pyenv

開發環境需要「每個專案用不同的語言版本」，但這個 role **刻意不裝通用版本管理器**——
因為現在裝的兩個語言都已經自己解決了：

| | 怎麼切版本 | 這個 role 做什麼 |
|---|---|---|
| **Go** | 語言內建。Go 1.21+ 預設 `GOTOOLCHAIN=auto`，`go.mod` 要求更新的版本時 `go` 指令自動下載並改用對應 toolchain | 只裝一個 bootstrap Go |
| **Python** | `uv` 自己管：`uv python install`、讀 `.python-version`、`uv run` 會自動抓缺的版本（預編譯 standalone build，不用現場編譯） | 裝 uv |

**Node 目前完全不裝**（用不到）。將來要用時，它是唯一需要外部工具才能多版本的：屆時
`mise` 是最合適的選項（`volta` 已宣告 unmaintained 並自己指向 mise，`fnm` 必須靠 shell
hook、非互動 shell 拿不到）。**不要用 nvm** —— 它是 shell function 且只寫 `~/.bashrc`，
`wsl -d dev -e node` 這種非互動情境永遠拿不到；apt 那條路也不通，Ubuntu 的 `nodejs` 套件
不含 npm，而 apt 的 `npm` 停在 9.2.0 還會拖進約 70 個 `node-*` 套件。最省事的做法是照
`go.yml` 的形狀裝 nodejs.org 官方 tarball 到 `/usr/local/node`（真實路徑，附帶版本相符
的 npm 與 corepack）。

## 設定

在 `inventory/hosts.yml`、`group_vars/` 或 `host_vars/` 覆蓋預設：

| 變數 | 預設 | 控制 |
|---|---|---|
| `container_runtime` | `podman` | runtime（只實作 `podman` 路徑） |
| `podman_firewall_driver` | WSL 上 `iptables`，否則空 | netavark firewall driver；空字串 = 用 netavark 預設 |
| `go_version` | `latest` | `latest` **每次 apply 都查 go.dev**（會跟著上游走版），或 pin 如 `1.26.5` |
| `install_python` | `true` | uv |
| `install_clients` | `true` | `psql`、`redis-cli` |

（SSH keys / git 身分的設定在 `wsl-bootstrap` 的 `config.ps1`，不在這裡。）
