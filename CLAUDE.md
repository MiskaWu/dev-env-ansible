# CLAUDE.md

## 執行模型

- 未來要 control node 遠端管，用 Windows OpenSSH 的 ProxyJump 或 Tailscale——**不要用 WSL
  mirrored networking**（見下）。

## 慣例

- **核心只有 Claude Code + 它的最低相依，其餘一律是選裝。** 這個 repo 是「協助把 Claude
  開發環境準備起來」的工具，所以 `core.yml` 的 core packages（`ca-certificates` / `curl` /
  `git` / `jq`）與 `claude.yml` 掛 `core` tag、`make install` 就這些，**其他每一個 import
  都必須有自己的 tag、要自己點名才會跑**——**包含 Go**（2026-07 之前它是無條件必裝，
  那是分層畫錯）。判斷「這個要不要放 core」
  只問一句：少了它還能不能把這台機器準備起來？「好用」不是理由。
  **`jq` 是唯一通過這關的「小工具」（2026-07-27 從選裝升上來）**，靠的不是好用，是
  `install.sh` 裡真的有它的分支：解 manifest checksum 時有 jq 走 jq、沒有就退回
  `get_checksum_from_manifest()` 的 bash regex（假設 platform 與 checksum 之間不出現 `}`），
  上游改 manifest 結構就靜默失效、還印出誤導的 "Platform … not found in manifest"。
  要再往 core 加東西就拿出這種等級的證據：**在某個必經路徑的原始碼裡指得出它被呼叫**，
  而不是「Claude 大概會用到」。
  **`ripgrep` 查過了，不夠格 —— 2026-07-27 連選裝也一起拿掉了。** 它確實是 Claude Code
  唯一另一個會 `command -v` 找的工具（binary 裡 `command -v` 的對象只有 4 個：`rg`、
  `jq`、`powershell.exe`、`compinit`），一度看起來跟 jq 同級。但 rg 有兩種來源，binary
  裡的 mode 只有 `"embedded"` 與 `"system"` 兩個值，而它自己的錯誤訊息把話講死了：
  `ripgrep not found on PATH. Install it (…) or use the native claude binary which
  embeds it.` —— **我們走的正是 native installer，rg 是內嵌的**，系統那支只有 npm
  安裝版才需要。
  **這條有實驗，不是只讀字串**：把常用工具 symlink 進一個乾淨目錄（**故意不放 `rg`**）、
  以那個目錄當唯一 `PATH`，再跑
  `claude -p "<用 Grep 搜某個字串>" --allowedTools Grep`（只給 Grep、不給 Bash，逼它走
  內建搜尋路徑）—— **命中目標、零錯誤**。所以系統上沒有 rg 也不影響 Claude。
  剩下的理由只有「自己在 shell 敲 `rg`」，使用者用不太到，就不裝了。
  **副作用比想像小（2026-07-27 追加實測，修正了本條原本的說法）**：Claude **自己的
  Bash 工具裡仍然有 `rg`**。偵測到 PATH 上沒有時，它會在 shell snapshot 注入一個 `rg`
  function（binary 裡那段 heredoc 的結束標記就叫 `RIPGREP_FUNC_END`），內容是
  `( exec -a rg "$_cc_bin" "$@" )` —— 拿 **claude 二進位自己**當 ripgrep 跑，靠 argv[0]
  分流，busybox 那種 multi-call binary 的作法。所以真正少掉的只有**你自己互動 shell
  裡的 `rg`**；已經裝了的機器完全不受影響（只裝不卸）。
  **`USE_BUILTIN_RIPGREP=0` 在這裡沒有用**，別被網路文章誤導：那個變數宣稱能改用系統
  rg（少一層 Node wrapper、更快），但上游 [issue #6415](https://github.com/anthropics/claude-code/issues/6415)
  記錄 Grep 工具直接忽略它，本機實測也一樣 —— 設成 `0` 且 PATH 無 rg，搜尋照樣成功。
  另注意網路上談的多半是 **npm 版**（`@vscode/ripgrep`，rg 是 vendor 目錄裡的獨立檔案），
  跟我們用的 native binary 形狀不同，別把那邊的結論直接搬過來。
  **要分辨手上跑的是哪一支 rg，看版本號就好**：內嵌的是 **ripgrep 14.1.1
  (rev f6d0fcd24a)**，Ubuntu 26.04 的 `ripgrep` 套件是 **15.1.0**。2026-07-27 在本機
  `apt purge --autoremove ripgrep`（只拔它一個、無連帶、無殘留）之後，`rg --version`
  從 15.1.0 變成 14.1.1、`type -a rg` 從檔案變成 function，而 Grep 工具在**完全沒有
  模擬**的正常環境下照樣命中 —— 這是這條規則最硬的證據，勝過先前所有讀字串的推論。
  **這組對照就是這條規則的範本**：兩個工具都被 Claude「用到」，但 jq 是外部相依
  （installer 是 shell script，沒辦法內嵌），rg 是自帶。要往 core 加東西就查到這個
  程度為止 —— 「Claude 會用到」不等於「Claude 需要系統上有」。
- **「裝不裝」由 tag 決定，不要再引入布林開關（2026-07-28 整組移除）。** 以前同時有兩套
  選擇機制：布林開關（`install_go` 等，宣告式：「這台機器的定義包含 Go」）與 tag（命令式：
  「這次只跑這段」）。既然定位是「Claude 環境 + 其他用到時再裝」，那就是純命令式，宣告式
  那層是多餘的。使用者端入口是 `make install-<tag>`。**相依關係也用 tag 表達** ——
  `build-tools.yml` 在 `main.yml` 掛 `[build-tools, go, python]`，於是 `--tags python`
  自動把編譯工具鏈帶進來（`--list-tasks` 實測確認），比舊的
  `install_build_tools: "{{ install_go or install_python }}"` 好在：多一個需要編譯器的東西
  只要多掛一個 tag，不必回頭改運算式。加新 import 時三件事：給它 tag、如果會影響 PATH
  就把 tag 也加到 `profile.yml` 那行、回 `list.yml` 補一行。
  **代價要記著**：沒有「一句話把這台機器收斂回我要的組合」了，所以 `make list` 改成偵測
  機器上實際有什麼（`stat` 那幾個 binary），`profile.yml` 也改成偵測而不是讀開關。
- **多裝一個 apt 小工具＝在 `tools.yml` 加一個帶自己 tag 的 task**，不要開新的 task 檔。
  獨立檔案是留給「要查版本 / 抓 tarball / 跑官方 installer」的東西（`go.yml`、`python.yml`）。
  以前 psql/redis 有自己的 `clients.yml` + `install_clients`、lazygit 也差點為了一句
  `apt install` 開一個檔 + 一個布林 + `main.yml` 一筆 + README 一列——就是要避免那個。
  （2026-07-28 之前這些是 `dev_env_packages` 一份清單裡的一行。改成一 task 一 tag 是為了
  能單裝 —— tag 必須在 parse 時就是靜態的，沒辦法從 list 變數生出來。成本從一行變五行，
  這是 per-tool 選擇的必要代價。）
  **但編譯工具鏈不進 `tools.yml`**：`build-essential` 不是「你會敲的工具」，是 Go（cgo）與
  uv（C extension）共用的前置，所以獨立成 `build-tools.yml`、掛在它們的 tag 底下。
  `tools.yml` 是「日常敲的東西」，別讓它變成什麼都往裡丟的雜物袋。
- **這個 role 只裝不卸（使用者決定），卸載一律手動。** apt 的 `state: present` 只保證
  「有」，所以從 `tools.yml` 刪掉一個 task 只是「以後不裝」，已經裝好的會留著。**不要**因此
  去加一個「absent 清單 + `purge`」的機制、也不要加 `make uninstall-%`——那等於把破壞性
  動作放進日常路徑，清單打錯一個字就照刪；移除交給使用者刻意執行。2026-07 加過又拿掉，
  別再繞回來。
  手動移除前先 `apt-get -s purge --autoremove <pkg>` 看影響範圍，發行版自帶的尤其要看：
  `tmux` 是 Ubuntu WSL base image 內建（跟 `byobu`、`ubuntu-wsl` 同一批裝進來，dpkg.log
  可查，所以 role 那行 `apt: tmux` 一直是 no-op），purge 它會連 `byobu` 和 `ubuntu-wsl`
  metapackage 一起拔掉。
- **`is_wsl` gate**：只在 WSL 成立的 task（netavark firewall driver、rshared-root unit）放
  `when: is_wsl`。`detect.yml` 用 `ansible_facts.kernel` 判。跨用的關鍵，別拿掉。
- **fact 一律用 `ansible_facts.*`**（`ansible_facts.env.HOME`、`.date_time.date`…），不用
  top-level `ansible_env` / `ansible_date_time`——後者 `INJECT_FACTS_AS_VARS` 會在
  ansible-core 2.24 移除，用了會噴 deprecation。
- **facts 已經有的別再 shell 出去拿**：`ansible_facts.user_uid` / `.user_id` 就是「ansible
  實際連進去的那個 user」，不用另外跑 `id -u`（少一個 task，也少一個 `check_mode: false` 例外）。
- **冪等**：`curl|bash` 類用 `creates:`；Go 用「目標版本已在就跳過」；apt/lineinfile 天生冪等。
  但**`creates:` 只解決冪等，不解決失敗偵測**——它在**執行前**檢查、事後不驗，所以
  `curl … | bash` 還必須自己 `set -o pipefail` + `executable: /bin/bash`（Ubuntu 的
  `/bin/sh` 是 dash，沒有 pipefail）。少了它，curl 失敗時 bash 收到空輸入乾淨結束、
  pipeline 回 0 → **task 綠燈但 binary 不存在**，而且因為 `creates` 事後不檢查，這個失敗
  會一路靜默到下次有人真的要用。2026-07 review 時 `claude.yml` / `python.yml` 都有這個洞。
- **驗證指令別把 exit code 洗掉**：`if cmd | grep x | sed …; then` 的成敗取決於 pipeline
  的**最後一個**指令，而 `sed` 永遠回 0 —— 失敗會被判成成功。2026-07 驗 podman 網路時就
  這樣做出一次假陽性，差點把「其實還壞著」的 WSL workaround 拿掉。要判成敗就
  `out=$(cmd 2>&1)` 之後對 `$out` 檢查，或加 `set -o pipefail`。
- **`dpkg -S` 要一個檔查一次，不要一次餵多個路徑。** 只要其中**任一個**路徑不屬於任何套件，
  整個指令就回非零（實測 `rc=1`），所以合查會把「A 屬於套件、B 不屬於」判成「兩個都不屬於」。
  拿它當「刪檔」的 gate 時這個誤判會直接刪掉屬於套件的檔案 —— 要 loop 逐檔查、逐檔判
  （`podman.yml` 清舊版 `containers.conf` / `registries.conf` 那段就是）。2026-07 review 抓到。
- **`~/.profile` 只有一個 managed block**（`profile.yml` 的 `blockinfile`）。以前 go / claude /
  python / podman 四個 task 檔各自 `lineinfile` 一行，`~/.local/bin` 還被寫了兩次，PATH 順序
  沒人管得住。要加環境變數就往那個 block 加，別回頭散寫。另外兩條配套規則：
  - **block 的內容讀「機器上實際有什麼」，不讀開關**（`stat /usr/local/go/bin/go`、
    `stat /usr/bin/podman`）。理由是命令式模型下沒有任何地方記著「這台有 Go」——使用者
    可能今天 `make install-go`、下週才 `make install-python`，偵測讓兩次都產出正確的
    `.profile`。順序上安全：`profile.yml` 是 `main.yml` 最後一個 import。
    **附帶好處是整類 `| bool` 陷阱消失了**：`stat.exists` 是真布林，而以前
    `-e install_go=false` 傳進來是字串 `"false"`，`when:` 看得懂但 Jinja
    `{% raw %}{% if %}{% endraw %}` 一律 truthy，少寫 `| bool` 就會裝出「Go 沒裝但
    `.profile` 有 Go PATH」——**只有某一種傳法會壞**，最難查的那種。2026-07 踩過，
    2026-07-28 隨開關一起移除。
    已知落差：`--check` 不會真的裝，所以在還沒有 Go 的機器上乾跑，diff 會顯示成不含
    Go PATH。那是 check mode 的本質（後面的 task 看不到前面沒真的做的事），不是 bug。
  - **`lineinfile: state=absent` 不認 managed block 的邊界**，它比對整行、block 內外一起刪。
    清舊版殘留的那幾行字串，必須確定在**任何情況下**都不會跟 block 產出的行逐字相同，
    否則會變成「清掉 → blockinfile 補回 → 每次跑都 changed」。`.local/bin` 那行就是這樣
    才被拆成獨立、`when: _go_bin.stat.exists` 的 task。
- **設定檔用 `.d` drop-in，不整檔覆寫**：`/etc/containers/containers.conf.d/`、
  `registries.conf.d/`。整檔覆寫會在發行版哪天開始出貨主檔時把它蓋掉，語意也比較不清楚。
- **不裝通用版本管理器**（mise / asdf / nvm / pyenv）。Go 靠語言內建的 `GOTOOLCHAIN=auto`、
  Python 靠 uv，兩者都不需要外部工具。要推翻這個決定前先看 README 的「版本管理」段，
  那裡有完整理由與各方案的取捨。
- **Node / nats / docker-compose 在 2026-07 移除**（用不到）。三者的安裝方式都研究定案過，
  要加回來看 README 的「版本管理」段與 git log —— 別重新從 nvm / `go install` /
  `releases/latest/download` 那些踩過的路開始。
- **「可以裝什麼」的清單從 playbook 投影出來，不要手抄。** 2026-07 之前那份清單同時
  存在三個地方（Makefile 的 `TAGS` 註解、README、真正的 `tasks/main.yml`），而只有第三個
  是真的 —— `clients` 那個 tag 隨 `clients.yml` 移除後，前兩份還掛著它。現在的分工：
  - **`make list`** 是唯一的入口，跑 `list.yml`（`tags: [list, never]`，`never` 保證一般
    install 掃不到）。它印的 ✓／· 是**當場 `stat` 出來**的，不是文件裡的宣稱 —— 開關移除
    之後沒有東西記著「這台該有什麼」，偵測正好補上那個缺口。它仍然必須是 ansible task
    而不是 Makefile 裡一串 `echo`：`podman_firewall_driver` 這種求值後才知道的東西，
    role defaults 只有在 play 的 scope 裡才拿得到。
  - **tag 清單**由 `make list` 結尾直接跑 `--list-tags` 取得，完全不手寫。
  - **往 `main.yml` 加一個 import 時，回 `list.yml` 補一行。** 只有那句說明與偵測路徑是
    人寫的；✓／· 不會騙人。偵測路徑挑「裝完一定會出現的檔案」（`build-essential` 是
    metapackage、沒有自己的檔案，用 `/usr/bin/gcc` 當代理）。
- **`make install-xxx` 打錯字會靜默無事發生** —— ansible 對不存在的 tag 不報錯、只是
  什麼都不做，一路綠燈跑完卻一個套件都沒裝。Makefile 的 `_assert_tags` 在動作前先比對
  `--list-tags` 的結果，不存在就 fail（實測 `make install-pythn` → exit 2）。**別把這個
  guard 拿掉**，它擋的是最難發現的那種失敗。
  - **`_assert_tags` 是 `define`、寫在 recipe 裡，不是當前置條件的 target。** 兩個實測
    出來的理由：pattern rule 的 target-specific 變數**傳不到前置條件**（`install-%: TAGS = $*`
    設好了，前置的 `_check-tags` 收到的仍是空字串），而且 phony 前置條件 make 只會做一次
    —— `make install-go install-python` 只檢查得到第一個。寫在 recipe 裡兩個問題都沒有。
  - **`_TAGS` / `_ARGS` 必須用 `=` 不能用 `:=`。** 遞迴展開才吃得到 `install-%` 設的
    target-specific `TAGS`；用 `:=` 會在 parse 時把當時還空的 `TAGS` 定死，於是
    `make install-python` 靜默變成「不帶 `--tags`、全部裝一遍」。
  - **不要為了 `make install python`（空格形式）加 catch-all 規則 `%:;@:`。** make 把
    空格後面那個字當成另一個 target，撐起來就得吃掉未知 target —— 而那正好會讓
    `make pythn` 靜默成功什麼都不做，跟上面那個 guard 擋的是同一種病。pattern rule
    (`install-%`) 是純標準 make、零 hack，維持這個形狀。
  - **`profile` 不必再自己補**：它掛在 `[profile, core, go, python, podman]` 上，任何會
    影響 PATH 的項目都會帶到它（舊設計得記得寫 `TAGS=go,profile`）。仍然刻意**不用**
    `always` —— 那會讓 `make facts` 從唯讀變成會改 `~/.profile`。
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
has been removed` **整個 run 開頭中止、什麼都沒裝**。更陰險：`make install` 回非零，但外層
（背景任務 / wsl.exe）可能把 exit code 誤報成 0，看起來「成功」實則沒做事。要 yaml 輸出用
default callback 的 `result_format`，別用舊 callback。

**netavark 的 firewall driver 一律明寫，不要吃發行版預設。** netavark 的預設是**編譯期**
決定的（上游 `src/firewall/mod.rs` 的 `#[cfg(default_fw = ...)]`；runtime 偵測 firewalld
那段在上游是被註解掉的），所以**同一版 netavark 在不同發行版預設可能不同**——Ubuntu 26.04
的 netavark 1.16.1 實測 `default_fw_driver = nftables`（`netavark version` 會直接印出來），
Debian changelog 也兩次寫明「Default to nftables, again」。吃預設 = 換台機器行為就變，所以
`podman.yml` 在所有 host 上都寫 drop-in，不只在 WSL 蓋掉。

**WSL2 上 nftables driver 會壞 —— 2026-07-27 在 podman 5.7.0 / netavark 1.16.1 /
Ubuntu 26.04 / kernel 6.6.87.2 重新實測，仍然壞。** 失敗簽章非常明確：

```
[INFO  netavark::firewall::nft] Creating container chain nv_<hash>_10_89_0_0_nm24
internal:0:0-0: Error: Could not process rule: No such file or directory
internal:0:0-0: Error: Could not process rule: No such file or directory
Error: netavark: nftables error: "nft" did not return successfully while applying ruleset
```

**全新 network、第一個容器就炸**（不是狀態累積），且**只有自建 bridge network 才炸**
——`podman run` 走 pasta 預設網路不碰防火牆規則所以正常，「`podman run` 全綠但一接自建
網路就爆」是標準失敗形狀。解法是 `podman_firewall_driver` 在 WSL 上設 `iptables`
（**現代 Ubuntu 的 `iptables` 套件裝的其實是 iptables-nft 相容層，不是 legacy xtables**）。
同日以 iptables driver 實測，五個場景全通過：容器取得 IP、aardvark 容器名 DNS、
masquerade 對外連線、`-p` 埠發佈、背景容器。

**別把原因記成「WSL kernel 不支援 nftables」——那是錯的，已用實驗排除。** 在
`unshare -Urn --map-root-user`（rootless podman 完全相同的權限形狀）裡、從冷模組狀態
（起始只載入 `ip_tables`）、用 netavark 實際走的 `nft -j` JSON 介面，成功套用了
inet table + nat postrouting/prerouting hook + `masquerade` + `ct state established,related`
+ `meta mark` + `dnat` + `counter`，而且 `nft_ct.ko` 自動載入成功。kernel 側
`CONFIG_NF_TABLES=y`、`NF_TABLES_INET/IPV4/IPV6=y`、`NFT_NAT=y`、`NFT_MASQ=y` 都是
builtin，模組目錄有 924 個模組。**也排除了「缺 `nft_counter`」**（該模組確實不存在，
但 `counter` 表達式實測可用）。

**根因（2026-07-27 查到）：WSL2 kernel 沒編 `CONFIG_NFT_FIB_IPV6`。** 實測：

```
CONFIG_NFT_FIB=m
CONFIG_NFT_FIB_IPV4=m
# CONFIG_NFT_FIB_IPV6 is not set      ← 關鍵
```

連鎖：`nft_fib_ipv6` 沒編 → **`nft_fib_inet` 模組不存在**（它需要 v4+v6 兩者）→
netavark 建的是 **`inet` family** 的 `table inet netavark`，其中規則用了 `fib`
（判斷封包是否來自本機）→ `inet` 表裡的 `fib` 找不到模組 → nft 回 ENOENT
（`Could not process rule: No such file or directory`）→ netavark 包成
`"nft" did not return successfully`。

決定性對照組（在 `unshare -Urn` 裡重現，一字不差）：

| 測試 | 結果 |
|---|---|
| `table inet t { chain c { fib daddr type local accept } }` | ❌ `Could not process rule: No such file or directory` |
| `table ip t { chain c { fib daddr type local accept } }`（純 v4） | ✅ 通過 |

iptables driver 完全不碰 `fib`，所以不受影響。**注意**：這是高信心推論而非直接證據
——已證明「本 kernel 上 inet+fib 會產生該錯誤」且「netavark 二進位含 Fib 表達式
（`struct Fib with 2 elements`）」，但沒攔截到 netavark 送出的字面 ruleset。

**這是 WSL 通病，不是本機問題。** 上游 [podman#25201](https://github.com/containers/podman/issues/25201)
（已關閉，官方解法就是改用 iptables，但沒查出原因）、
[microsoft/WSL#9772](https://github.com/microsoft/WSL/issues/9772)（WSL kernel 裁掉
netfilter 選項，已關閉）、netavark#1057 / #1411、podman-compose#1154 都是同一個錯誤
在各家 WSL distro 上的回報。理論上自編 WSL kernel（`.wslconfig` 的 `kernel=`）加上
`CONFIG_NFT_FIB_IPV6=y` 可解，但每次 WSL 更新都要重編，不划算 —— **維持 iptables**。

**重驗方式**（升級 podman/netavark 後值得再跑一次；通了就能把整個 workaround 連同
`iptables` 相依一起砍掉）：

```bash
podman network rm -f fwtest
printf '[network]\nfirewall_driver = "nftables"\n' \
  | sudo tee /etc/containers/containers.conf.d/50-firewall-driver.conf
podman network create fwtest
podman run --rm --network fwtest docker.io/library/alpine true && echo OK || echo FAIL
podman network rm -f fwtest && make install-podman     # 還原
```

**driver 對應的後端工具要自己裝。** iptables driver 會呼叫 `iptables` 二進位、nftables
driver 會呼叫 `nft`；前者只在 podman 的 `Suggests`、後者只在 netavark 的 `Recommends`，
少了**不會在安裝階段報錯**，而是等到起第一個接自建網路的容器時才爆。跟下面 `passt` /
`aardvark-dns` 是同一類陷阱。

**換 driver 不影響既有 network。** netavark 把 driver 記在每個 network 上（二進位裡有
`create firewall-driver file` / `read firewall-driver`），改了設定要 `podman network rm`
重建、或整台重開才會完全乾淨。

**Ubuntu 的 `/etc/containers/registries.conf` 是一份「全註解」的樣板，沒有任何生效設定。**
（2026-07-27 更正：這條原本寫「Ubuntu 完全不出貨」，那是錯的 —— `golang-github-containers-image`
5.38.0 確實出貨這個檔，而且是 conffile；實機看不到它是因為被 role 自己刪掉了，見下。從 .deb
解出來看過：唯一那行 `unqualified-search-registries` 是**被註解掉的** `# … ["example.com"]`。）
所以結論不變：實際生效的 unqualified search 清單是空的，內建 short-name 別名表也沒有
`postgres`/`redis`/`nats` → `podman pull postgres` 直接失敗（fail fast，不卡 TTY）。
寫在 `/etc/containers/registries.conf.d/50-unqualified-search.conf`。Ubuntu-general，不 gate。

**別刪 `/etc/containers/registries.conf` —— 它是別人的 conffile。** `podman.yml` 清舊版整檔
設定的那段，2026-07-27 之前用 `dpkg -S <兩個路徑>` 一次查、rc 非零就兩個一起刪；因為
`containers.conf` 無主（rc=1）而 `registries.conf` 有主（rc=0），合查回 1 → **把有主的那個
一起刪了**。實機上這件事已經發生過：同一次 apply 在 17:42:47 裝進
`golang-github-containers-image`、17:43 就把它的 conffile 刪掉。後果不嚴重（那份檔沒有生效
設定，drop-in 也照樣管用），但每次該套件升級 dpkg 會把 conffile 補回來、role 又刪一次，
變成無止境的來回。改成逐檔查、逐檔判之後 `registries.conf` 會被正確跳過。

**podman 幾個關鍵相依在 Ubuntu 上只是 `Recommends`，要明確寫進套件清單。** `uidmap`
（rootless 的 uid 映射，沒有它 rootless 完全不能用）、`passt`（提供 pasta，podman 5 的
**預設** rootless 網路後端）、`dbus-user-session`（systemd `--user` 的 D-Bus 整合，rootless
`podman.socket` 要）都只是 podman 的 Recommends；**`aardvark-dns` 更隱蔽——它是 `netavark`
的 Recommends**，負責自建 bridge network 裡的容器名解析（容器之間用名字互連就靠它）。
apt 預設會裝 Recommends 所以平常看不出問題，但只要誰用
`--no-install-recommends`、或換個 base image，就會靜默壞掉。不該碰運氣。
（反過來，`buildah` / `skopeo` / `slirp4netns` / `fuse-overlayfs` 是舊清單的贅肉，2026-07
砍掉：前兩個 podman 已內建等價功能，slirp4netns 被 pasta 取代，fuse-overlayfs 在
kernel 5.11+ 的 rootless 下可直接用 native overlay。）

**環境變數放 `~/.profile`，不是 `~/.bashrc`。** Ubuntu 預設 `.bashrc` 開頭對非互動 shell
就 `return`，寫那裡的 `export`（`DOCKER_HOST`、`PATH`）`wsl -d dev -e`、腳本、cron 都讀不到。
alias 放 `.bashrc` 沒問題（本來只對互動有意義）。

**同一條的延伸：整類「靠 shell rc 才生效」的工具都不能用。** nvm 就是典型——它是 shell
function，且 install.sh 在 bash 下只寫 `.bashrc`，所以當年用 nvm 裝的 Node，
`wsl -d dev -e node -v` 一直是找不到（2026-07 大整理才發現）。挑工具先問一句「非互動 shell
拿不拿得到」：**真實路徑的 binary 可以，shell function / shell hook 不行**（同理 `fnm` 也
必須靠 hook；`mise` 之所以能用是因為它有 shims 目錄這條真實路徑）。這條規則跟 Node 裝不裝
無關（現在不裝了），是挑任何工具都適用的判準。

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

**socket 起不來、Docker API 用戶端連不到 socket → full `wsl --shutdown`（不是 `--terminate`）。**
根因是 WSL 上 systemd 259 的 `user@<uid>.service` 起來後 spawn systemd-executor 失敗
（journal: `Failed to spawn executor: Device or resource busy`），整個 user session
degraded。`--terminate` 只停單一 distro、留了 VM 層狀態清不掉；**full `wsl --shutdown`
重置整個 VM 才行**——之後乾淨 session 一來 `user@` active、symlink-enabled 的 podman.socket
自動起、socket 端到端通（實測）。所以 `make install-podman` 裝完，Windows 端跑一次 `wsl --shutdown`
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

**OOM trap（實測未遇到，記著防復發）**：容器經 systemd user unit 啟動時會繼承
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
——套用時**主動移除** `.bashrc` 裡既有的那行，不只是不再加。**compose 也不裝**（2026-07
移除 `docker-compose` 二進位）。但 `DOCKER_HOST` 與 rootless `podman.socket` 保留 ——
那是給需要 Docker API 的工具（IDE、testcontainers）用的，跟 compose 是兩回事。將來要
compose，`podman compose` 需要一個外部 provider 二進位才會動。
