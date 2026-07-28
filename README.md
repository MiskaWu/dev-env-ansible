# dev-env-ansible

把一台 Linux 裝成開發環境的 Ansible role。定位很窄：**協助把 Claude Code 的開發環境
準備起來**，其他工具都是選用的。

- **core（`make install` 就這些）** —— Claude Code，以及它與這個 repo 本身的最低相依
  （`ca-certificates`、`curl`、`git`、`jq`）。這層沒得選，因為關掉就沒有這個 repo 了。
  （`jq` 在 2026-07-27 從選裝升上來 —— Claude Code 的官方 installer 解 manifest checksum
  的首選路徑就是它，少了它會退回脆弱的 bash regex；理由與實測數字在 `core.yml` 的註解。）
- **其餘一律自己點名** —— 語言 toolchain（Go、uv）、容器 runtime（rootless Podman）、
  順手的 CLI 工具（lazygit、unzip）。**用到時再裝**：`make install-go`、
  `make install-python`、`make install-lazygit`；懶得挑就 `make install-all`。

**相依會自動帶進來。** `make install-python` 會順便裝 `build-essential`（uv 遇到沒有
預編譯 wheel 時要現場編 C extension），`make install-go` 也一樣（cgo）；任何會影響 PATH
的項目都會順手更新 `~/.profile`。你不必知道誰需要誰。

（git 身分與 SSH keys 不在這裡 —— 由 [`wsl-bootstrap`](../wsl-bootstrap) 在 bring-up 就備好，
因為 key 得先在才能 clone 私有 repo，屬「一台個人機」而非軟體層。）

**Host-agnostic** —— WSL2 專屬的 task 用 `is_wsl` fact gate 起來，所以同一個 role 也能跑在
純 Ubuntu VM、homelab 節點或 WSL distro。搭配 [`wsl-bootstrap`](../wsl-bootstrap)：它產出一台
已開 systemd、可連的 WSL distro，讓你在上面接手裝軟體。

## 怎麼選要裝什麼：tag，不是開關

2026-07-28 之前這個 repo 有一整組布林開關（`install_go`、`install_python`、
`container_runtime`…），寫在 `group_vars` 裡宣告「這台機器該有什麼」，再由 `make apply`
收斂過去。**那層整組移除了** —— 既然定位是「Claude 環境 + 用到時再裝的東西」，宣告式
那套就是多餘的第二種選擇機制。現在 tag 本身就是選擇：

```bash
make install              # core：Claude Code + 它的相依 + ~/.profile
make install-go           # Go（自動帶 build-essential，自動更新 PATH）
make install-python       # uv（同上）
make install-podman       # rootless Podman + DOCKER_HOST
make install-lazygit      # 單一小工具
make install-tools        # 所有 CLI 小工具
make install-all          # 暴力：全部
```

一起消失的三個坑：相依關係不必再寫成布林運算式；`-e install_go=false` 傳字串 `"false"`
進 Jinja 被當 truthy 那類 `| bool` 陷阱沒有了；「單跑一個 tag 不會帶到 `profile`」也不再
需要記 —— `profile` 掛在每個會影響環境變數的 tag 底下。

**代價講清楚**：沒有「一句話把這台機器收斂回我要的組合」了。以前讀 `group_vars` 就知道
這台該有什麼，現在得自己記得裝過哪些 —— 所以 `make list` 改成**偵測機器上實際有什麼**，
補上這個缺口。

## 檔案結構

```
dev-env-ansible/
├── ansible.cfg
├── site.yml                    # 頂層 playbook
├── inventory/hosts.yml         # 管理的 host
└── roles/dev_env/
    ├── defaults/main.yml       # 只剩「怎麼裝」的參數（go_version、firewall driver）
    ├── templates/              # containers 設定 drop-in、systemd unit
    └── tasks/
        ├── detect.yml          # 設定 is_wsl / dev_env_arch fact      (tags: always)
        ├── list.yml            # `make list` 的輸出                   (tags: [list, never])
        ├── core.yml            # core 套件                            (tags: core)
        ├── claude.yml          # Claude Code（native installer）      (tags: [core, claude])
        ├── tools.yml           # CLI 小工具，每個 task 自帶 tag       (tags: tools + 各自)
        ├── build-tools.yml     # build-essential      (tags: [build-tools, go, python])
        ├── go.yml              # Go binary（目標版本已在就跳過）      (tags: go)
        ├── python.yml          # uv                                   (tags: python)
        ├── podman.yml          # podman + .d drop-in                  (tags: podman)
        └── profile.yml         # ~/.profile 單一 managed block
                                #        (tags: [profile, core, go, python, podman])
```

**相依關係就寫在 `main.yml` 的 tag 上。** `build-tools.yml` 掛 `[build-tools, go, python]`，
所以 `--tags python` 會自動把編譯工具鏈帶進來 —— 將來多一個需要編譯器的東西，只要在它的
import 多掛一個 tag。

**要多裝一個 apt 小工具，在 `tools.yml` 加一個帶自己 tag 的 task**，不要開新的 task 檔 ——
獨立檔案是留給「需要查版本 / 抓 tarball / 跑官方 installer」的東西（`go.yml`、`python.yml`
那種）。`build-essential` 也不進 `tools.yml`：它不是你會敲的工具，是別人的前置。

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

**2. 先看有什麼可裝。**

```bash
make list     # 每一項怎麼叫、這台機器已經有哪些、可用的 tag
```

輸出長這樣 —— **✓／· 是當場 stat 出來的**，不是寫死的文件（所以這段只是示意，以你自己
跑出來的為準）：

```
  ✓ make install             core：Claude Code + 它的 4 個 apt 相依 + ~/.profile
  · make install-go          Go latest（自動帶 build-essential）
  · make install-python      uv（自動帶 build-essential）
  ✓ make install-podman      rootless Podman + DOCKER_HOST（firewall driver: iptables）
  · make install-build-tools build-essential —— go / python 會自動帶
  · make install-lazygit     lazygit（git 的 TUI）
  · make install-unzip       unzip

可用的 tag（直接跟 playbook 要的，不是手抄）：
    always build-tools claude core go lazygit list podman profile python tools unzip
```

**3. 裝。**

```bash
make init                 # 補 ansible → 裝 core（Claude）→ 印收尾清單
make install-python       # 之後用到什麼再裝什麼
make install-all          # 或一次全裝
```

只想先看不動手：`make check-python`（單項乾跑）或 `make check`（全部）。tag 打錯字
**ansible 自己不會報錯、只會什麼都不做**，所以 Makefile 在動作前先比對一次真實的 tag
清單，不存在就直接失敗（`make install-pythn` → exit 2）。

**4. 裝了 podman 的話，回 Windows 端 full shutdown。** 讓 rootless `podman.socket` 在乾淨
session 起來（原因見下）：

```powershell
wsl --shutdown
```

**5. 收尾**（手動接上平台，刻意不自動化）。SSH keys 與 git 身分 bring-up 已備好，剩貼與認證：

```bash
wsl -d dev
cat ~/.ssh/id_ed25519_dev_github.pub    # 貼到 GitHub → Settings → SSH keys（若還沒貼）
cat ~/.ssh/id_ed25519_dev_gitlab.pub    # 貼到 GitLab
claude                                   # 首次 OAuth 認證
# key 貼好後，把本 repo 的 origin 指向 GitHub（之後就能 git pull 更新）：
git remote set-url origin git@github.com:MiskaWu/dev-env-ansible.git
```

驗一下 podman 真的能用。第一條走 pasta 預設網路，第二組才會碰到防火牆規則
（自建 bridge network 是最容易出問題的路徑）：

```bash
podman run --rm docker.io/library/alpine true          # 基本
podman network create t
podman run -d --name svc --network t docker.io/library/alpine sleep 60
podman run --rm --network t docker.io/library/alpine getent hosts svc   # 容器名 DNS
podman run --rm --network t docker.io/library/alpine ping -c1 1.1.1.1   # 對外
podman rm -f svc && podman network rm t
```

（2026-07-27 在 podman 5.7.0 / WSL2 實測全數通過 —— 前提是 firewall driver 為
`iptables`，見下方與 CLAUDE.md。）

## 之後更新（day-2，不砍重建）

```bash
cd ~/projects/dev-env-ansible
git pull                 # 若遠端有更新
make list                # 忘了有哪些項目 / 這台裝了哪些 —— 唯讀，不會動到機器
make check-podman        # 預覽某一項會動什麼（diff）；LOCAL 預設 1，在 distro 內不用帶
make install-podman      # 套用
make install-all         # 或把已裝的全部重跑一次（會跟著上游走版，例如 Go latest）
```

`list` 與 `check` 回答的是不同問題，兩個都留著：**`list` 是「有哪些東西可裝、這台已經有
哪些」**（純唯讀、不連線做事），**`check` 是「這次會改哪些檔」**（真的去 host 上比對）。
第一次看 `list`，動手前的最後一眼看 `check`。

重跑會收斂（冪等）—— 對已裝好的 host `make check` 應該是 `changed=0`。

## 在 WSL 上：第一次裝完 podman 為什麼要 `wsl --shutdown`

rootless `podman.socket` 在安裝時已 enable，但 WSL 的 systemd 有 executor 冷啟動 race
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

`defaults/main.yml` 只剩「**怎麼裝**」的參數 ——「**裝不裝**」由你在指令列點名，不再有
變數。可在 `inventory/hosts.yml`、`group_vars/` 或 `host_vars/` 覆蓋：

| 變數 | 預設 | 控制 |
|---|---|---|
| `go_version` | `latest` | `latest` **每次 `make install-go` 都查 go.dev**（會跟著上游走版），或 pin 如 `1.26.5` |
| `podman_firewall_driver` | WSL 上 `iptables`，否則 `nftables` | netavark firewall driver。**一律明寫**，因為 netavark 的預設是編譯期決定的、換發行版就可能不同。可用 `iptables` / `nftables` / `firewalld` / `none`，或 `''` 表示完全不管 |

**這個 role 只裝不卸。** 沒有「解除安裝」的目標，也刻意不做 —— 卸載是破壞性動作，不該由
每次安裝順手跑一遍。要它真的從機器上消失是手動的事（`sudo apt purge --autoremove <pkg>`）。
動手前先 `apt-get -s purge --autoremove <pkg>` 看一次影響範圍，發行版自帶的套件尤其要看
（例如 `tmux` 是 Ubuntu WSL image 內建，purge 它會連 `byobu` 與 `ubuntu-wsl` metapackage
一起拔掉）。

**實測體積**（讓取捨有依據）：`build-essential` 260MB / 43 個套件，跟 Go 的 269MB、
Claude Code 的 263MB 同級 —— 它不是異常值。相對地整份 CLI 小工具只有約 24MB。
所以該不該裝 `build-essential` 的判準是「你編不編 native 東西」，不是體積 ——
而多數時候你不必自己判斷，`install-go` / `install-python` 會替你帶進來。

（SSH keys / git 身分的設定在 `wsl-bootstrap` 的 `config.ps1`，不在這裡。）
