# CLAUDE.md

## 執行模型

- 未來要 control node 遠端管，用 Windows OpenSSH 的 ProxyJump 或 Tailscale——**不要用 WSL
  mirrored networking**（見下）。

## 慣例

- **`is_wsl` gate**：只在 WSL 成立的 task（netavark firewall driver、rshared-root unit）放
  `when: is_wsl`。`detect.yml` 用 `ansible_facts.kernel` 判。跨用的關鍵，別拿掉。
- **fact 一律用 `ansible_facts.*`**（`ansible_facts.env.HOME`、`.date_time.date`…），不用
  top-level `ansible_env` / `ansible_date_time`——後者 `INJECT_FACTS_AS_VARS` 會在
  ansible-core 2.24 移除，用了會噴 deprecation。
- **facts 已經有的別再 shell 出去拿**：`ansible_facts.user_uid` / `.user_id` 就是「ansible
  實際連進去的那個 user」，不用另外跑 `id -u`（少一個 task，也少一個 `check_mode: false` 例外）。
- **冪等**：`curl|bash` 類用 `creates:`；Go / Node 用「目標版本已在就跳過」；apt/lineinfile 天生冪等。
- **`~/.profile` 只有一個 managed block**（`profile.yml` 的 `blockinfile`）。以前 go / claude /
  python / podman 四個 task 檔各自 `lineinfile` 一行，`~/.local/bin` 還被寫了兩次，PATH 順序
  沒人管得住。要加環境變數就往那個 block 加，別回頭散寫。
- **設定檔用 `.d` drop-in，不整檔覆寫**：`/etc/containers/containers.conf.d/`、
  `registries.conf.d/`。整檔覆寫會在發行版哪天開始出貨主檔時把它蓋掉，語意也比較不清楚。
- **不裝通用版本管理器**（mise / asdf / nvm / pyenv）。Go 靠語言內建的 `GOTOOLCHAIN=auto`、
  Python 靠 uv，兩者都不需要外部工具；Node 目前鎖單一版本。要推翻這個決定前先看 README
  的「版本管理」段，那裡有完整理由與各方案的取捨。
- **role 名 `dev_env` 用底線**（Galaxy 規定，不能連字號）。repo 名可用連字號。
- **`.gitattributes` `* text=auto eol=lf`**：只在 Linux 跑，全 LF。Makefile 用 tab、CRLF 會壞；
  `.yml` 裡餵給 shell task 的內容也怕 `\r`。
- **Makefile `?=` 後面不要接行內 `# 註解`**：make 會把「值到 `#` 之間的空白」算進變數值
  （`LOCAL ?= 1  # x` → `"1  "`，`$(filter 1,…)` 就對不上、`LOCAL=1` 預設靜默失效，
  變成走 inventory 而不是 localhost）。註解一律另起一行。2026-07 踩過。
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
解法：裝 `iptables`（**注意現代 Ubuntu 的 `iptables` 套件裝的其實是 iptables-nft 相容層，
不是 legacy xtables**）+ 寫 `/etc/containers/containers.conf.d/50-firewall-driver.conf` 的
`firewall_driver = "iptables"`。由 `podman_firewall_driver` 變數控制（WSL 上預設
`iptables`，空字串 = 不寫 drop-in、用 netavark 預設）。**這條是 2026-07 在較舊的 podman
上驗的，現在的 Ubuntu 26.04 是 podman 5.7 / netavark 1.16 —— 上游可能已修，值得重驗一次
再決定要不要把這個 workaround 拿掉。**

**Ubuntu 完全不出貨 `/etc/containers/registries.conf`**，內建 short-name 別名表也沒有
`postgres`/`redis`/`nats` → `podman pull postgres` 直接失敗（fail fast，不卡 TTY）。
寫在 `/etc/containers/registries.conf.d/50-unqualified-search.conf`。Ubuntu-general，不 gate。

**podman 幾個關鍵相依在 Ubuntu 上只是 `Recommends`，要明確寫進套件清單。** `uidmap`
（rootless 的 uid 映射，沒有它 rootless 完全不能用）、`passt`（提供 pasta，podman 5 的
**預設** rootless 網路後端）、`dbus-user-session`（systemd `--user` 的 D-Bus 整合，rootless
`podman.socket` 要）都只是 podman 的 Recommends；**`aardvark-dns` 更隱蔽——它是 `netavark`
的 Recommends**，負責 bridge network 裡的容器名解析，也就是 compose 裡 `app` 連
`postgres:5432` 靠的東西。apt 預設會裝 Recommends 所以平常看不出問題，但只要誰用
`--no-install-recommends`、或換個 base image，就會靜默壞掉。不該碰運氣。
（反過來，`buildah` / `skopeo` / `slirp4netns` / `fuse-overlayfs` 是舊清單的贅肉，2026-07
砍掉：前兩個 podman 已內建等價功能，slirp4netns 被 pasta 取代，fuse-overlayfs 在
kernel 5.11+ 的 rootless 下可直接用 native overlay。）

**環境變數放 `~/.profile`，不是 `~/.bashrc`。** Ubuntu 預設 `.bashrc` 開頭對非互動 shell
就 `return`，寫那裡的 `export`（`DOCKER_HOST`、`PATH`）`wsl -d dev -e`、腳本、cron 都讀不到。
alias 放 `.bashrc` 沒問題（本來只對互動有意義）。

**同一條的延伸：整類「靠 shell rc 才生效」的工具都不能用。** nvm 就是典型——它是 shell
function，且 install.sh 在 bash 下只寫 `.bashrc`，所以舊的 `node.yml` 裝完後
`wsl -d dev -e node -v` 一直是找不到（2026-07 大整理才發現）。挑工具先問一句「非互動 shell
拿不拿得到」：**真實路徑的 binary 可以，shell function / shell hook 不行**（同理 `fnm` 也
必須靠 hook；`mise` 之所以能用是因為它有 shims 目錄這條真實路徑）。Node 改成裝 nodejs.org
官方 tarball 到 `/usr/local/node`；順帶一提 apt 那條路也不通——Ubuntu 的 `nodejs` 套件不含
npm，而 apt 的 `npm` 停在 9.2.0 還會拖進約 70 個 `node-*` 套件。

**WSL 預設把 Windows PATH 接進來，且 `/mnt/c` 底下的檔案全被當成可執行 → 指令會解析到
Windows 版。** 實測：Linux 端沒裝 node 時，`command -v npm` 拿到的是
`/mnt/c/Program Files/nodejs/npm`，於是在 WSL 裡 `npm install` 跑的其實是 Windows 的 Node，
裝出來的原生模組是 Windows 二進位。防法是 PATH 順序——`profile.yml` 把自己裝的路徑放最
前面，WSL 附加到尾端的 Windows 路徑就永遠搶不贏。要根治可在 `/etc/wsl.conf` 設
`appendWindowsPath = false`（順便加快 shell 啟動，PATH 查找不必走到 Windows 檔案系統），
代價是 `code .` / `explorer.exe` 這類 interop 指令要自己加回 PATH ——**尚未採用**，目前
只靠順序擋著。

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
