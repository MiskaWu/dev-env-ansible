# CLAUDE.md

## 這個 repo 是什麼

Ansible role，把一台 Linux 裝成完整開發環境：baseline 套件、Podman(rootless)、Go、
Claude Code、可選 Node/uv/client tools/SSH keys。**host-agnostic** —— WSL2-specific 的
task 用 `is_wsl` fact gate 起來，同一個 role 能跑純 Ubuntu VM / homelab 節點 / WSL。

跟 `wsl-bootstrap` 配對：後者在 Windows 上生出一台「systemd + 預設 user + **git + make**」
的乾淨 WSL distro（baseline **不含 ansible**），這個 role 在那台上**本機 `make apply`** 把
軟體裝起來。Makefile 是唯一操作入口，跨平台通用（任何有 git+make 的 host 都能 clone + `make
init`）。

「正確」= 對已裝好的 host 跑 `make check` 是 `changed=0`（完全冪等）。

## 執行模型

- **Makefile 是入口，ansible 由它自己補。** bring-up 只給 git+make；`check`/`apply`/`syntax`/
  `facts` 都依賴內部 `_ensure-ansible`，第一次跑會 `apt install ansible-core`（**不能用 ansible
  裝 ansible**，所以這層由 make 補）。這是刻意的解耦——bring-up 不預設你用哪套組態管理。
- **本機 make apply（預設）**：`cd ~/projects/dev-env-ansible && make apply`。`LOCAL` 預設
  `1`（`connection: local` 對 localhost 收斂），在 distro 內不用帶；控制節點模式設 `LOCAL=0`。
- **起手 / 收尾也走 make**：`make init` = apply + 印公鑰 + 收尾清單一鍵；`make ssh-keys` 印
  公鑰給你貼 GitHub/GitLab；`make git-config GIT_NAME=.. GIT_EMAIL=..` 設 git 身分。**貼公鑰到
  平台、`claude` OAuth 刻意保持手動**（不把 GitHub 憑證帶進自動化）。
- `make check` = 乾跑預覽（`--check --diff`）、`make apply TAGS=node` = 只裝某項。
- 未來要 control node 遠端管，用 Windows OpenSSH 的 ProxyJump 或 Tailscale——**不要用 WSL
  mirrored networking**（見下）。

## 慣例

- **`is_wsl` gate**：只在 WSL 成立的 task（netavark→iptables、containers.conf）放
  `when: is_wsl`。`detect.yml` 用 `ansible_facts.kernel` 判。跨用的關鍵，別拿掉。
- **fact 一律用 `ansible_facts.*`**（`ansible_facts.env.HOME`、`.date_time.date`…），不用
  top-level `ansible_env` / `ansible_date_time`——後者 `INJECT_FACTS_AS_VARS` 會在
  ansible-core 2.24 移除，用了會噴 deprecation。
- **冪等**：`curl|bash` 類用 `creates:`；Go 用「目標版本已在就跳過」；apt/lineinfile 天生冪等。
- **role 名 `dev_env` 用底線**（Galaxy 規定，不能連字號）。repo 名可用連字號。
- **`.gitattributes` `* text=auto eol=lf`**：只在 Linux 跑，全 LF。Makefile 用 tab、CRLF 會壞；
  `.yml` 裡餵給 shell task 的內容也怕 `\r`。
- **Makefile `?=` 後面不要接行內 `# 註解`**：make 會把「值到 `#` 之間的空白」算進變數值
  （`SSH_TAG ?= dev  # x` → `"dev  "`；`LOCAL ?= 1  # x` → `"1  "`，`$(filter 1,…)` 就對不上、
  `LOCAL=1` 預設靜默失效，`ssh-keys` 的 glob 也會抓錯路徑）。註解一律另起一行。2026-07 踩過。
- 註解 / commit 訊息 / README 都用繁體中文（2026-07 起 README 也改繁中）。

## 已知地雷（軟體 / WSL 層，2026-07 踩過）

**repo 要放 `~/`，不要 `/mnt/c`。** ansible 不讀 world-writable 目錄（`/mnt/c` 就是）的
`ansible.cfg`（會看到 `ignoring it as an ansible.cfg source` 警告），`stdout_callback`、
`roles_path` 全失效；加上 `/mnt/c` I/O 慢。clone 到 dev 的 `~/projects` 再跑。**教訓**：
從 `/mnt/c` 跑會**蓋掉 ansible.cfg 的問題**——2026-07 那次 `stdout_callback = yaml`（見下）
在 `/mnt/c` 完全沒事，搬到 `~/` 才炸。驗 role 一定要從 `~/` 跑。

**不要在 ansible.cfg 設 `stdout_callback = yaml`。** 舊的 `community.general.yaml` callback
在 ansible-core 2.20 已移除，設了會 `[ERROR]: The 'community.general.yaml' callback plugin
has been removed` **整個 run 開頭中止、什麼都沒裝**。更陰險：`make apply` 回非零，但外層
（背景任務 / wsl.exe）可能把 exit code 誤報成 0，看起來「成功」實則沒做事。要 yaml 輸出用
default callback 的 `result_format`，別用舊 callback。

**netavark 預設 nftables driver 在 WSL2 kernel 上失敗。** 症狀：`docker-compose up` 容器
卡在 `Created`，或 `netavark: nftables error: "nft" did not return successfully`。**只在
WSL**，且**只有自建 bridge network（compose 一定會）才炸**——`podman run` 走 pasta 預設
網路不碰防火牆規則所以正常，所以「`podman run` 全綠但 compose 全爆」是標準失敗形狀。
解法：裝 `iptables` + 寫 `/etc/containers/containers.conf` `firewall_driver = "iptables"`
（`podman.yml` 的 `when: is_wsl` task）。

**Ubuntu 完全不出貨 `/etc/containers/registries.conf`**，內建 short-name 別名表也沒有
`postgres`/`redis`/`nats` → `podman pull postgres` 直接失敗（fail fast，不卡 TTY）。
`podman.yml` 寫 `unqualified-search-registries = ["docker.io"]`。這是 Ubuntu-general，不 gate。

**環境變數放 `~/.profile`，不是 `~/.bashrc`。** Ubuntu 預設 `.bashrc` 開頭對非互動 shell
就 `return`，寫那裡的 `export`（`DOCKER_HOST`、`PATH`）`wsl -d dev -e`、腳本、cron 都讀不到。
alias 放 `.bashrc` 沒問題（本來只對互動有意義）。

**rootless `podman.socket` 用「建 enable symlink」啟用，不要 `systemctl --user enable`。**
WSL 上 systemd 259 的 user session 冷啟動 race 讓 `systemctl --user` 常連不上 user bus
（`Failed to connect to user scope bus`），會讓**整個 play abort**（後面的 go/claude/uv 全
沒跑）。而 enable 的本質就是 `sockets.target.wants/` 裡一個指向 unit 的 symlink——直接用
`file: state=link` 建，**不需要 live 的 user manager**；啟動則 best-effort（`command:
systemctl --user start ... ` + `failed_when: false`，race 擋住不致命）。

**socket 起不來、compose 連不到 socket → full `wsl --shutdown`（不是 `--terminate`）。**
根因是 WSL 上 systemd 259 的 `user@<uid>.service` 起來後 spawn systemd-executor 失敗
（journal: `Failed to spawn executor: Device or resource busy`），整個 user session
degraded。`--terminate` 只停單一 distro、留了 VM 層狀態清不掉；**full `wsl --shutdown`
重置整個 VM 才行**——之後乾淨 session 一來 `user@` active、symlink-enabled 的 podman.socket
自動起、compose 端到端通（實測）。所以 `make apply` 裝完，Windows 端跑一次 `wsl --shutdown`
再重進。這不是安裝失敗，是平台 race。

（另：`.config` 若被 root 建走，建 symlink 會 permission denied——見 wsl-bootstrap 的
provision.sh 用 `runuser` 建 `~/.config`。）

**要從 Windows 連 distro 內的容器 port，`.wslconfig` 必須是 `networkingMode=mirrored`。**
（2026-07 更正：這條原本寫「NAT + localhostForwarding 就夠」，但那個「實測通」是在
mirrored 開著時測的，功勞被錯算給 NAT。）關掉 mirrored 重測（容器確認存活、純 WSL 程序
作對照組）：

| 模式 | Windows → 純 WSL 程序 | Windows → rootless podman 容器 port |
|---|---|---|
| NAT | ✅ | ❌ **不通** |
| mirrored | ✅ | ✅ |

`localhostForwarding` 只轉 WSL init netns 裡的 listener，**不轉 pasta 為 rootless 容器發佈
的 port**。設定在 `wsl-bootstrap/wslconfig`（只用 `[wsl2]`，不加 `[experimental]` 的
`hostAddressLoopback`——`127.0.0.1` 路徑不靠它）。mirrored 的已知 podman bug
（#13868、#13317）本機實測未發生，但 WSL 更新後要重驗。
另一個小坑：綁 IPv6-only(`::`) 的服務不會被 relay，綁 `0.0.0.0`（podman `-p` 預設就是）。

**OOM trap（實測未遇到，記著防復發）**：compose 經 systemd user unit 呼叫 podman，容器繼承
`OOMScoreAdjust=100`，規格要求 0 時非特權調不下來 → `oom_score_adj: Permission denied`。
`podman run` 不受影響。解法：`user@.service` 加 `OOMScoreAdjust=0` drop-in。

**WSL 的 `/` 是 private mount propagation → 用 systemd unit 設成 rshared。** rootless
podman 會警告 `"/" is not a shared mount ... missing mounts with rootless containers`，
且容器內 mount 傳播可能不正確（**k3s 這種大量 mount 的負載特別會踩到**）。正常 systemd
開機會把 `/` 設 shared，WSL 沒做（實測 `findmnt -no PROPAGATION /` = `private`）。
`podman.yml` 裝一個開機早期的 oneshot unit（`rshared-root.service`，`is_wsl` gate，
`Before=sysinit.target`）跑 `mount --make-rshared /`。手動 `mount --make-rshared /` 不持久
（`wsl --shutdown` 就沒了），必須走 unit 才會每次開機生效。

**只用 podman，不 alias `docker=podman`（使用者決定）。** alias task 是 `state: absent`
——套用時**主動移除** `.bashrc` 裡既有的那行，不只是不再加。compose 走 `podman compose`
（`docker-compose` 二進位當 provider），`DOCKER_HOST`（podman socket）保留給
`podman compose` 與需要 Docker API 的工具（IDE / testcontainers）。

## 驗證

- `make syntax`（不連線）→ 語法。
- `make check`（對已裝好的 host）→ 應 `changed=0`；有 `changed` 就代表某 task 沒寫對冪等。
- 加新 task 後先 `make check` 看 diff，再 `make apply`。
