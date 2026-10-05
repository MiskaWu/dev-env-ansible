# CLAUDE.md

## 執行模型

- 未來要 control node 遠端管，用 Windows OpenSSH 的 ProxyJump 或 Tailscale——**不要用 WSL
  mirrored networking**（見下）。

## 慣例

- **沒有「無條件裝」的東西 —— 連 Claude Code 都是一個要點名的 tag（2026-07-28）。**
  這個 repo 是「協助把 Claude 開發環境準備起來」的工具，但那個定位表現在 `make init`
  的指引與 `make list` 的排序上，**不表現在偷偷幫你裝東西**。真正基礎到不能選的只有
  ansible 本身，歸 Makefile 的 `make init`。**每一個 import 都必須有自己的 tag**——
  **包含 Go**（2026-07 之前它是無條件必裝，那是分層畫錯）。
  `base.yml` 那四個 apt 套件（`ca-certificates` / `curl` / `git` / `jq`）**不是「基本
  必裝」，是別人的相依**：掛 `[base, claude, python, rust]`，因為 `claude.yml`、`python.yml`、
  `rust.yml` 都是 `curl … | sh` 跑官方 installer。要往那裡加東西只問一句：**某個 installer 的必經
  路徑上真的用得到它嗎？**「好用」不是理由。
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
  那層是多餘的。使用者端入口只有一個指令：**`make install TAGS=<項目>`，不帶 TAGS 就是
  全裝**（= 不帶 `--tags`，跟底層 ansible 一對一，**刻意沒有隱藏的預設值**）。
  **相依關係也用 tag 表達** —— `base.yml` 掛 `[base, claude, python, rust]`、`build-tools.yml`
  掛 `[build-tools, go, python, rust]`，於是 `--tags python` / `--tags rust` 自動把兩者都帶進來
  （`--list-tasks` 實測確認）。比舊的
  `install_build_tools: "{{ install_go or install_python }}"` 好在：多一個需要編譯器的東西
  只要多掛一個 tag，不必回頭改運算式。加新 import 時四件事：給它 tag、把它的 tag 掛到
  它需要的前置 import 上、如果會影響 PATH 就把 tag 也加到 `profile.yml` 那行、回
  `list.yml` 補一行。
  **代價要記著**：沒有「一句話把這台機器收斂回我要的組合」了，所以 `make list` 改成偵測
  機器上實際有什麼（`stat` 那幾個 binary），`profile.yml` 也改成偵測而不是讀開關。
- **一個項目一個 task 檔，apt 小工具也不例外（2026-07-28 拆開 `tools.yml`）。** 多裝一個
  工具就是開一個 `<工具>.yml`，在 `main.yml` 掛 `tags: [tools, <工具>]` —— 兩種叫法都成立：
  `TAGS=lazygit` 只裝那一個，`TAGS=tools` 是這一類整包。
  **這條 2026-07-28 當天翻過一次，理由是成本變了、不是喜好變了**：舊規則寫「不要為一句
  `apt install` 開一個檔」，因為當時的代價是「一個檔 + **一個布林** + `main.yml` 一筆 +
  README 一列」。布林開關同一天整組移除之後，代價只剩「一個檔 + 一行 import」，就沒有
  理由讓這幾個跟 `go.yml` / `node.yml` 長得不一樣。
  （更早的演化：這些原本是 `dev_env_packages` 一份清單裡的一行，改成一 task 一 tag 是為了
  能單裝 —— tag 必須在 parse 時就是靜態的，沒辦法從 list 變數生出來。）
  **判準是「這是誰的東西」，不是檔案大小**：
  - **你自己會敲的** → 自己一個檔（`lazygit.yml`、`unzip.yml`），掛 `tools`。
  - **別人的相依** → `base.yml`（installer 要的）或 `build-tools.yml`（編譯工具鏈）。
    `build-essential` 不是「你會敲的工具」，是 Go（cgo）與 uv（C extension）共用的前置，
    所以它掛在**它們的** tag 底下，不掛 `tools`。
  - 要把某個工具從「選裝」升進相依層，看下面 jq（升格）與 ripgrep（駁回）那組對照。
- **反安裝分兩半：role 獨佔的路徑有 `make uninstall`，apt 的一律手動（2026-07-28 加）。**
  分界線是**所有權**，不是難易度。`/usr/local/go`、`/usr/local/node`、
  `~/.local/share/claude`、`~/.local/bin/uv`、`~/.rustup` 這幾個整包是我們放的，刪掉不牽動任何別的
  東西，所以能自動化；apt 套件是**共同持有**的，移除的連帶結果取決於這台機器現在還裝了
  什麼（同一個指令在兩台機器上結果不同），那是整個 repo 裡唯一一類「讀 playbook 讀不出
  後果」的操作 —— 正確做法必然包含「人看過 `apt-get -s purge --autoremove` 的輸出再
  決定」，**沒辦法替你做決定的動作，不該包成一個看起來會替你做決定的指令**。
  `make uninstall TAGS=podman` 會被 Makefile 的 guard 擋下並印出手動步驟。
  另一個不碰 apt 的現實理由：要在 uninstall 端模擬就得把套件名再抄一份，那份抄本一定
  會漂移（list.yml 檔頭記過同一個教訓）。連抄都不抄就沒有這個問題。
  **史實更正**：本條原本寫「2026-07 加過又拿掉，別再繞回來」——git 上查不到，`purge`
  這個字從沒進過 repo、`Makefile` 也從沒有過 `uninstall` target。那應該是在對話裡提過
  又否決、沒進版本庫。別花時間去找「舊實作」。
  - **刻意沒有對稱的 `uninstall-check`。** ansible 的 `--check` 對移除給的是**假的
    安全感**：它只說「這個 task 會 changed」，不會說 purge 某個套件會連帶帶走誰 ——
    那個資訊只有 `apt-get -s purge --autoremove` 產得出來。乾跑印完一片綠字，你還是
    得手動模擬一次才敢按，那個 target 什麼也沒買到，只是讓人以為自己看過了。
  - **安全性由三件事提供**：① **必須點名 `TAGS`，不帶就拒絕**（跟 install 最重要的
    不對稱 —— install 不帶 TAGS 是「全裝」，uninstall 不帶 TAGS 是「拒絕」，這個指令
    **沒有「全砍」這個意思**）；② 只碰 role 獨佔的路徑；③ **工具與資料分開**，預設
    只拿掉工具、資料留著並報告大小，要一起清得明確加 `DATA=1`。
  - **`~/.claude` 任何情況下都不動**（設定 / 專案紀錄 / hooks / memory 是你的資料，
    不是這個 role 裝的東西），連 `DATA=1` 也不碰。同理 `~/go` 預設保留 —— `go install`
    裝的二進位跟模組快取在同一棵樹底下，沒辦法只刪一半又講得清楚。
  - **走獨立的 `uninstall.yml` playbook，不併進 `site.yml`。** 因為 ansible 的
    `--tags` 是 **OR** 語意：`--tags uninstall,go` 會把安裝 Go 的 task 一起選中，
    tag 之間沒有 AND，「移除語境下的 go」沒辦法用 tag 組合表達。兩個 playbook 各自
    有一份乾淨的 tag 命名空間，`make list` 印的是 site.yml 的、guard 兩份都問。
  - **加新項目的判準**：只有「role 獨佔一整個目錄」的才適合進 `uninstall.yml`。
  - **Rust 是第一個「一半獨佔、一半混住」的項目（2026-10-05）。** `~/.rustup` 整包是
    rustup 的 → 工具，直接刪；`~/.cargo` 卻混著 rustup 本體與 proxy、cargo 的快取、
    `cargo install` 的東西、使用者的 `config.toml` / `credentials.toml`。它跟 `~/go` 同類，
    差別在**切得開**（Cargo Book 的 Cargo Home 一節逐項寫了每個路徑是什麼），所以只拿掉
    rustup 放的那些，其餘照 DATA 規則：`registry/`、`git/`、`bin/`（剩下的都是
    `cargo install` 的）＋`.crates.toml` / `.crates2.json` 歸 `DATA=1`（對齊 Go 的
    `~/go/bin`、uv 的 `uv tool`，那兩邊 `DATA=1` 也一起清）；`config.toml` /
    `credentials.toml` 永遠保留（`~/.claude` 那一類）。
    - **rustup 的 proxy 用 `find -L ~/.cargo/bin -maxdepth 1 -samefile ~/.cargo/bin/rustup`
      認，不手抄名單。** 1.29.1 的 proxy 是指向 `rustup` 的相對 symlink，舊版是 hardlink，
      `-L -samefile` 兩種都認得；名單是上游的（現在 13 個，含 `rls` / `rust-gdbgui`），
      抄過來就會漂移。乾跑實測正好挑出本體 + 13 個 proxy，不碰別的。
    - **刻意不用 `rustup self uninstall`**：它把整個 `~/.cargo` 連設定、token、
      `cargo install` 的東西一起刪，正是「工具與資料是兩個決定」要擋的那種一個字全砍。
  - **gh 是第一個「apt 套件 + role 自己放的檔」的項目（2026-10-05）。** 套件照 apt 的規矩手動；
    但 keyring（`/etc/apt/keyrings/githubcli-archive-keyring.gpg`）與來源檔
    （`/etc/apt/sources.list.d/github-cli.sources`）的**所有權是 role 的**，所以手動步驟必須
    把它們列出來，不能讓人 purge 完留一把第三方金鑰和一個沒人用的來源。
    - **不進 `uninstall.yml` 自動刪**：它們的生命週期綁在套件上，要等人看過模擬、決定 purge
      之後才該拿掉（先刪而最後決定不 purge，gh 就斷了更新來源），而 playbook 沒辦法排在一個
      手動步驟後面。也不能讓 `make uninstall TAGS=gh` 只刪檔不動套件 —— 那正是「斷了更新來源」。
    - **路徑由 Makefile 從 `gh.yml` 的 `dest: /etc/apt/…` 行讀出來印**，不在 Makefile 抄一份
      （同 ssh-host-rm 從 `IdentityFile` 讀 key 路徑：印錯路徑，使用者會照著 `rm`）。比對只認
      `dest:` 行，所以 `gh.yml` 註解裡提到的路徑不會被誤印。之後別的項目也加了套件庫，同一段
      自動涵蓋，不必改 Makefile。
    - `~/.config/gh`（token）不在清單裡，同 `~/.claude` —— 是使用者的資料。
- **`make ssh-host HOST=<網域>`：git host 的 SSH 設定，寫 `~/.ssh/config.d/`，不碰
  `~/.ssh/config` 的既有內容（2026-08-05 加）。** 界線是**時間，不是主題** —— 「SSH keys
  不在這個 role」那條仍然成立，但它指的是**開機那一組**（github.com / gitlab.com，key 得
  先在才 clone 得動私有 repo，包含這個 repo 自己）。日常又冒出一個網域（公司內部 GitLab）
  走 bring-up 要回 Windows 改 `config.ps1` 再重跑，那是為「建一台機器」設計的路徑。
  - **所有權切乾淨，不是兩支工具在同一個檔裡互切**：bootstrap 擁有 `~/.ssh/config` 裡
    它自己那對 `# >>> wsl-bootstrap managed` 標記之間的內容，我們擁有整個
    `~/.ssh/config.d/`，唯一交集是檔頭那行 `Include config.d/*.conf`。讀過
    provision.sh 確認它的作法是「sed 刪掉自己的區塊 → append 到檔尾」，所以**那行
    Include 不會被洗掉**。同一條 drop-in 原則見 `containers.conf.d`。
  - **`Include` 的四件事，2026-08-05 實測（OpenSSH_10.2p1）**：① 相對路徑一律以
    **`~/.ssh`** 為基準，跟「正在讀哪個檔」無關（用 `-F /somewhere/config` 測，相對
    Include 仍然解析到 `~/.ssh/config.d`）；② 同一個 Host 出現兩次是**先出現的贏**，
    不是後蓋前；③ glob 沒對到任何檔**不是錯誤**，靜靜跳過（所以移除後把 Include 留著
    無害）；④ include 進來的檔權限鬆（0660）ssh **不抱怨**，嚴格檢查只針對主 config。
  - **Include 放 BOF ⇒ config.d 永遠優先於 bootstrap 的區塊**，這是必然不是偏好：
    bootstrap 重跑是「刪自己的區塊 → append 到檔尾」，不管一開始插在哪都會收斂成這個
    順序。所以一開始就擺對位置，而不是讓優先權取決於誰最後跑。
  - **`ssh` 的 `~` 取自 passwd，不看 `$HOME`（實測）。** 寫完會跑 `ssh -G <host>` 驗
    「真的解析到那把 key」，這一步在改寫 `HOME` 的沙箱裡**一定失敗**（ansible 的 file
    task 用 `$HOME`、ssh 用 passwd，兩邊指到不同地方）。那是預期行為，assert 的
    fail_msg 有寫；別為了讓沙箱綠燈去改成 `ssh -F`——帶 `-F` 反而失真，因為檔案裡的
    相對 Include 仍然以 `~/.ssh` 為基準。
  - **`KEY=` 指到不存在的檔就失敗，不順手生一把。** 那正是打錯路徑的樣子，而失敗會延遲
    很久才顯形（拿舊公鑰去貼 → `Permission denied` → 查半天）。要在自訂路徑生新的才加
    `GEN=1`；不帶 `KEY` 時路徑是我們自己組的、不可能打錯，所以預設就是「沒有就生」。
  - **預設 key 名用完整網域**（`id_ed25519_dev_gitlab_dev_baasgames_com`），不取第一段
    標籤 —— `gitlab.dev.baasgames.com` 取 `gitlab` 會撞上 bring-up 給 `gitlab.com` 的
    `id_ed25519_dev_gitlab`，靜默把同一把 key 用到兩個平台。
  - **移除時訊息裡的 key 路徑要從那個檔 `IdentityFile` 讀出來，不能用預設路徑推**——
    `ssh-host-rm` 不帶 `KEY`，推出來的常常不是它實際綁的那把，而使用者會照著 `rm`。
  - **刻意不跑 `ssh-keyscan`**（那等於替你吞掉第一次連線的指紋確認），改印
    `ssh -T git@<host>`。也**不碰 git 身分** —— 那要用 git 自己的 `includeIf`。
  - **獨立 playbook（`ssh-host.yml`），不進 site.yml。** 理由跟 uninstall 不同：**它吃
    參數**。塞進 site.yml 會讓 `make list` 多出一個看似可裝、不帶 `HOST` 只會失敗的項目，
    還得再掛一個 `never` 把 `never` 的語意搞糊。所以「每個 import 都要有自己的 tag」那條
    在這裡不適用 —— 那條講的是可安裝項目，這是帶參數的動作。
- **apt 裝的東西只裝不卸，`state: present` 只保證「有」**（唯一用 `latest` 的是 gh，理由見
  gh 那條）。從 `tools.yml` 刪掉一個 task 只是「以後不裝」，已經裝好的會留著。**不要**去加「absent 清單 + `purge`」的機制
  ——清單打錯一個字就照刪，而且那正是上面說的「替你做了不該替你做的決定」。
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
    可能今天 `TAGS=go`、下週才 `TAGS=python`，偵測讓兩次都產出正確的
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
    才被拆成獨立、`when: _go_bin.stat.exists or _node_bin.stat.exists` 的 task ——
    **條件要涵蓋「所有會往那行 PATH 塞路徑的項目」**，漏掉一個就是白白跳過清理
    （加 Node 時就補過一次）。只有全部都沒裝時，block 那行才會退化成跟清理目標逐字
    相同，那時才真的必須跳過。
- **`~/.profile` 的 PATH 不夠 —— 裝在預設 PATH 之外的執行檔還要 symlink 進
  `/usr/local/bin/`（2026-07-28 加，node 與 go 已做）。** `~/.profile` **只有登入 shell
  會讀**，所以凡是**行程樹的根不是登入 shell** 的情境都拿不到它加的 PATH：`wsl.exe -e`、
  systemd unit、cron、Windows 側程式 spawn 出來的東西，以及未來遠端管時的
  `ssh dev '<cmd>'`（見檔頭「執行模型」——那會讓這個洞從偶爾變日常）。
  **實測**（`wsl -d dev -e bash -c 'command -v …'`，非登入非互動）：

  | 指令 | 解析到 |
  |---|---|
  | `node` / `go` / `claude` / `uv` | **NOT FOUND** |
  | `npm` | **`/mnt/c/Program Files/nodejs/npm`** ← Windows 的 npm |

  第二列才是重點：**不是「找不到」而是靜默用錯一支**，於是在 Linux 專案裡裝出
  `*-win32-x64-msvc`（下面「PATH 順序」那條記的事故，同一個根因的另一個入口）。
  - **`bash -c` / agent 本身沒問題，別把規則記成那樣。** `bash -c` **繼承**父行程的
    PATH，從讀過 `.profile` 的 shell 開出去完全正常。判準是行程樹的根是誰，不是有沒有
    `-c`。
  - **`/usr/local/bin` 是對的落點**（實測都有，且排在 Windows 路徑**前面**）：`wsl -e`
    第 2 位、systemd system manager、`systemd --user`、bash 編譯內建 fallback、
    `/etc/environment`、cron 實跑一次確認。**cron 那格特別要注意**：`/usr/sbin/cron`
    二進位裡是有 `/usr/bin:/bin` 這個舊 vixie 預設字串，但 Ubuntu 現在改成從環境繼承
    （`/etc/crontab` 自己寫著），實跑拿到的含 `/usr/local/bin` —— **讀字串會得到相反
    結論，要實跑**。另外 cron 的 PATH 裡完全沒有 Windows 路徑，所以 cron 只會「找不到」，
    不會誤用 Windows 版；有 fallback 危險的只有 `wsl -e` 那條。
  - **symlink 不會弄壞這兩個 runtime，但這是必須驗的一點**（換別的工具要重驗）：Go 從
    自己執行檔的位置回推 GOROOT 時會解 symlink、node 解 realpath。在只有 symlink 目錄的
    `env -i` 環境實測 `go env GOROOT`=`/usr/local/go`、`GOTOOLCHAIN`=auto、
    `node -v` / `npm -v` / `npx -v` / `corepack -v` 全通。
  - **守備範圍只有「安裝當下那幾個固定名字」，`profile.yml` 那份 PATH 不能拿掉。**
    `npm i -g <pkg>` 的執行檔落在 `/usr/local/node/bin`（實測 `npm config get prefix`
    = `/usr/local/node`）、`go install` 落在 `~/go/bin` —— 這些**裝完之後才多出來**的
    都不會被 symlink 到。兩個機制互補：symlink 管固定入口，`.profile` 管後來長出來的。
  - **移除端必須配套刪 symlink**（`uninstall.yml` 已加）。留著就是**指向不存在路徑的
    symlink**，比找不到更糟：`command -v go` 仍然命中、一跑才爆。這跟 Claude 那段
    「只刪 versions/ 會留下壞 symlink」是同一個陷阱。
  - **加新工具時的判準**：裝完問一句「它的執行檔在不在
    `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` 裡」。apt 裝的一律在
    （`/usr/bin`），不必管；**tarball / installer 裝進自己目錄的就要 symlink**。
    驗收方式是實跑 `wsl -d dev -e bash -c 'command -v <cmd>'`，不要用互動 shell 驗
    ——互動 shell 讀過 `.profile`，一定是綠的，驗不出東西。
  - **`~/.local/bin` 的 `claude` / `uv` / `uvx` 也一樣做（2026-07-28 補上）。** 本條原本
    寫「不能用同一招，因為 root 擁有的 symlink 指向某個使用者的 `$HOME`，多帳號機器上
    語意是錯的」——**推翻了，理由是那個前提本來就不成立**：這個 role 從頭到尾就是
    「一台機器供一個開發者」的模型（寫 `~/.profile`、`~/.claude`，把 claude / uv 裝進
    某個 `$HOME`，rootless podman 也只設一個 uid），「哪個使用者」在這裡從來不模糊。
    為一個這個 role 不支援的情境放棄一致性、讓最常被腳本呼叫的 `claude -p` 繼續壞著，
    划不來。
    - **但它確實引入了一層以前沒有的跨使用者耦合，這個要記著**：`~/.profile` 只影響
      本人，`/usr/local/bin` 的 symlink 會讓**別的使用者**也解析到這一個人的 binary，
      同機第二個使用者跑一次就是後寫的贏、而且是靜默的。真要支援多使用者，逃生口是
      改放一支解析 `$HOME` 的 wrapper script
      （`exec "${HOME:?}/.local/bin/claude" "$@"` —— **真實檔案不是 shell function**，
      所以非互動 shell 一樣拿得到，符合「挑工具先問非互動 shell 拿不拿得到」那條）。
    - **一定要指向 `~/.local/bin/<名字>`，不要指向 `versions/<版本>`。** claude 自動
      更新是「寫新的 `versions/<新版>` 再把 `~/.local/bin/claude` 重指過去」，指在穩定
      路徑上這條**兩段鏈**更新後照樣通；指到版本目錄則每次更新都變 dangling。實測
      `readlink -f /usr/local/bin/claude` 一路解到 `versions/2.1.220`。
      `uv self update` 是原地換檔，同樣不受影響。
    - **`uvx` 不是 `uv` 的 alias，是獨立執行檔**（實測兩個都是 `~/.local/bin` 底下的
      實體檔案），漏掉就是 `uvx` 在非登入 shell 找不到。
    - 做完之後**這個 role 裝的每一樣東西都在預設 PATH 裡了**，實測 `wsl -d dev -e`
      下 claude / uv / uvx / node / npm / npx / corepack / go / gofmt / podman /
      lazygit / unzip 全部命中。（2026-10-05 加 Rust 後同一個方式實測
      cargo / rustc / rustdoc / rustfmt / rustup 與 `cargo clippy` / `cargo fmt` 也全部命中；
      同日加 ffmpeg 後 `ffmpeg` / `ffprobe` 也命中 `/usr/bin`；加 gh 後 `wsl -d dev -e` 與
      `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/local/bin` 也都解析到 `/usr/bin/gh`。）
  - **rustup 的 proxy 是 multi-call binary，symlink 之前要驗 argv[0]（2026-10-05）。**
    `~/.cargo/bin` 裡的 cargo / rustc / rustfmt… 全是指向 `rustup` 的相對 symlink
    （1.29.1 實測 `cargo -> rustup`），靠 argv[0] 決定要當誰，所以
    `/usr/local/bin/cargo → ~/.cargo/bin/cargo → rustup` 是兩段鏈。多一段不會弄壞分流：
    經由 symlink 執行時 argv[0] 是 symlink 自己的名字。在 `env -i HOME=$HOME
    PATH=/usr/bin:/bin:/usr/local/bin` 實測 `cargo` / `rustc` / `rustdoc` / `rustfmt` /
    `rustup` 都回對的版本、`cargo build` 成功。
    - **只連五個入口（cargo / rustc / rustdoc / rustfmt / rustup）。** `cargo clippy` /
      `cargo fmt` 不需要另外連 `cargo-clippy` / `cargo-fmt`：cargo 找外部子命令本來就會搜
      `$CARGO_HOME/bin`（同一個 `env -i` 環境實測兩者都通；繞過 rustup proxy、直接跑工具鏈
      裡的 cargo 且 PATH 只有 `/usr/bin:/bin` 也通 —— 所以是 cargo 自己的行為，不是靠
      proxy 改 PATH）。沒裝的元件的 proxy
      （rust-analyzer、rust-gdb、cargo-miri…）也不連，連出來只會讓 `command -v` 命中一支
      只會說「元件沒裝」的東西。
    - `rust-toolchain.toml` 自動抓版本在同一個 `env -i` 環境也成立（見 Rust 那段），
      所以非登入 shell 不只拿得到 stable，也拿得到專案 pin 的版本。
- **設定檔用 `.d` drop-in，不整檔覆寫**：`/etc/containers/containers.conf.d/`、
  `registries.conf.d/`。整檔覆寫會在發行版哪天開始出貨主檔時把它蓋掉，語意也比較不清楚。
- **不裝通用版本管理器**（mise / asdf / nvm / pyenv）。Go 靠語言內建的 `GOTOOLCHAIN=auto`、
  Python 靠 uv、Rust 靠 rustup 讀 `rust-toolchain.toml`，三者都不需要外部工具（rustup 本身是
  Rust 官方的工具鏈管理器，跟 uv 同一個位置，不是這條擋的「跨語言、外掛式」那種）。要推翻這個決定前先看 README 的「版本管理」段，
  那裡有完整理由與各方案的取捨。
- **nats / docker-compose 在 2026-07 移除**（用不到）。安裝方式都研究定案過，要加回來看
  README 的「版本管理」段與 git log —— 別重新從 `go install` /
  `releases/latest/download` 那些踩過的路開始。
- **Node 2026-07-27 移除、2026-07-28 因為真的有前端專案要用而加回來（`TAGS=node`）。**
  形狀跟移除前一樣（nodejs.org 官方 tarball → `/usr/local/node`，PATH 歸 `profile.yml`），
  這裡只記那次「加回來」查到的東西：
  - **`node_version` 明確 pin，刻意不支援 `latest`** —— 這點跟 `go_version` 相反，別為了
    一致性去改。Go 只有一條線，latest 永遠是「該用的那個」；Node 的**奇數版不進 LTS、
    只活半年**，追 latest 會定期把機器推到非 LTS 上。現值 `24.18.0`（active LTS，Krypton）。
  - **不需要版本管理器，理由不是「暫時將就」**：前端專案宣告的幾乎都是**地板**而不是 pin
    —— 實測過的專案連 `.nvmrc` / `.node-version` / `engines` / `volta` / `packageManager`
    都沒有，真正的約束來自工具鏈自己（例如 vite 8 要 `^20.19 || >=22.12`），一個 LTS
    就蓋過去。真的硬衝突時隔離該待在**專案層**（專案自己帶 devcontainer，podman 已就緒），
    不是機器層。nvm / fnm 另有硬傷（shell function，非互動 shell 拿不到）；mise 技術上可行
    但沒有必要 —— 這條跟「不裝通用版本管理器」那條是同一個判斷。
  - **PATH 順序不是理論問題，是實際發生過的事故。** 2026-07-28 實測：Linux 端
    沒有 node 時 `command -v npm` 拿到 `/mnt/c/Program Files/nodejs/npm`（Windows npm 11.6.2），
    於是那包 `node_modules` 整組是 `lightningcss-win32-x64-msvc` /
    `@rolldown/binding-win32-x64-msvc` / `@tailwindcss/oxide-win32-x64-msvc`，還缺 `.bin/vite`。
    `profile.yml` 把 `/usr/local/node/bin` 放 `$PATH` **前面**就是在擋這個。
  - **誤裝過的專案，光裝 Node 不會自動修好，而且失敗是靜默的。** 要先 `rm -rf node_modules`
    再 `npm ci`。不能只跑 `make init` —— 專案 Makefile 常見的 `node_modules: package-lock.json`
    時間戳規則，遇到「誤裝出來的 node_modules 比 lock 檔新」會直接跳過 `npm ci`，
    一路綠燈卻仍在用 Windows 二進位。
  - **`node.yml` 不掛 `base` / `build-tools`**：tarball 安裝的必經路徑只用到 `get_url` 與
    tar/xz（`xz-utils` 是 Ubuntu base 的 priority: important）。node-gyp 那類要編原生模組的
    是**某個 npm 套件**的相依、不是 Node 自己的 —— 真的遇到再點 `TAGS=build-tools`。
- **Rust 2026-10-05 加入（`TAGS=rust`）：官方 rustup → stable，minimal profile + rustfmt +
  clippy。** 為 hyaku-monogatari（Godot 前端 + Rust 後端）加的。形狀跟 claude / uv 一樣是
  `curl … | sh` 官方 installer，PATH 歸 `profile.yml`，入口 symlink 進 `/usr/local/bin`。
  這裡記加的時候查到的東西：
  - **不走 apt**：Ubuntu 26.04 的 `rustc` / `cargo` 是 1.93.1，上游 stable 1.99.0 ——
    六週一版，落後九個月，crate 的 `rust-version` 一抬就編不過；apt 的 `rustup` 套件也停在
    1.27.1（官方 1.29.1）。
  - **rustup 不違反「不裝通用版本管理器」**，見那條。它也過「非互動 shell」那關：proxy 是
    檔案系統上的 symlink 指向真實 binary，不是 shell function / hook。
    `rust-toolchain.toml` 自動抓版本**實測成立**：只放一份 `channel = "1.98.0"`，在
    `env -i` 非登入環境直接 `cargo --version` → rustup 自己抓 1.98.0（48 秒）然後回
    `cargo 1.98.0`（`auto-install` 預設 enable）。
  - **工具鏈組成 = default profile 拿掉 rust-docs。** channel manifest 寫死
    `minimal = rustc + rust-std + cargo`、`default = minimal + rust-docs + rustfmt + clippy`。
    rust-docs 是 `rustup doc` 的離線 HTML：解開 **67,446 個條目、737MB**（xz 24.3MB），
    比整套裝好的工具鏈（`~/.rustup` 617MB）還大，WSL 上還得另外接瀏覽器，線上版就是同一份。
    rust-analyzer / rust-src 是編輯器的事，不裝。
    **`--profile minimal` 會寫進 `~/.rustup/settings.toml`，之後自動抓的工具鏈也是 minimal**
    —— 上面那個 1.98.0 實測只有 cargo / rust-std / rustc，沒有 rustfmt / clippy。專案的
    `rust-toolchain.toml` 要 fmt / clippy 就自己列 `components`（本來就該列，CI 沒有我們這台的設定）。
  - **`--no-modify-path`**：rustup 預設會往 `.profile` / `.bashrc` 加 `. "$HOME/.cargo/env"`，
    違反「`~/.profile` 只有一個 managed block」。實測加了之後兩個檔都沒被碰，只多一個沒人
    source 的 `~/.cargo/env`；`~/.cargo/bin` 進 block 那行 PATH（給 `cargo install` 的東西用）。
  - **`creates` 在 rustup 上不代表「裝完了」，所以 installer 之後還有收斂步驟。** claude / uv
    的 `creates` 檔是 installer 最後一步才放的；rustup-init 反過來，先放
    `~/.cargo/bin/rustup` 再下載工具鏈 —— 下載失敗那次會紅，但下一次 `creates` 就跳過、綠燈，
    cargo 卻沒有工具鏈可跑。所以每次都跑 `rustup toolchain install stable --profile minimal
    --component rustfmt,clippy`（已裝好時印 `… unchanged - rustc …`，有新 stable 就更新 ——
    等於 `go_version: latest`），再「**沒有 default 才** `rustup default stable`」。三個情境都
    實測過：
    - `rustup component remove clippy` 後重跑 → changed=1，clippy 回來；
    - `rustup default none` 後重跑 → 收斂步驟補上 stable 但**沒有設 default**
      （`rustup toolchain install` 不會順手設，cargo 照樣「no default is configured」）——
      這就是後面那步存在的理由；加上之後 changed=1、`stable (default)`；
    - 自己 `rustup default <別的>` 後重跑 → 那步 skipped，**不蓋掉使用者的選擇**。
    裝好之後重跑 `changed=0`。
  - **相依的證據（照 jq / ripgrep 那組的標準）**：
    - **base**：installer 本身是 `curl https://sh.rustup.rs | sh`，`rustup-init.sh` 的
      `downloader()` 也先找 curl 去抓 rustup-init 二進位 —— 必經路徑上指得出來。
      **但 rustup 二進位自己下載工具鏈不吃系統 CA**，別把 ca-certificates 的理由記成那裡：
      在 `unshare -rm` 裡把 `/etc/ssl/certs` bind 成空目錄，`rustup check` 照樣成功
      （`unshare -rn` 斷網時同一條會失敗，證明它真的有連線、不是讀快取），同條件下
      `curl` 是 `error 77 … ca-certificates.crt`。所以 ca-certificates 對 rust 而言純粹是
      curl 那段的相依。
    - **build-tools**：rustc 連結**任何**程式都要 `cc`，不是「碰到 C 相依才要」。
      決定性對照：PATH 只放 cargo / rustc / rustup 三個 symlink → hello world
      「error: linker `cc` not found」；同一個目錄**只多一支 cc** → 編過。原始碼層面：
      `RUSTC_BOOTSTRAP=1 rustc -Z unstable-options --print target-spec-json` 顯示
      `linker-flavor: gnu-lld-cc`、沒有 `linker` 鍵（＝預設 cc）、`link-self-contained`
      只含 `linker`（rust-lld 自帶，所以 binutils 的 ld 不是重點）；`--print link-args` 是
      `cc -m64 … -lgcc_s -lc -B…/gcc-ld -fuse-ld=lld -pie -nodefaultlibs`。cc 背後的
      `Scrt1.o` / `crti.o` / `libc.so` / `libc_nonshared.a` 全屬 `libc6-dev`（`dpkg -S`），
      `cc` 本身屬 gcc —— 兩者合起來就是 build-essential。
  - **uninstall 的切法**見上面反安裝那條的 Rust 子項。
- **`TAGS=playwright` 給的是「這台機器能跑 headless 瀏覽器」，不是 Playwright 本身
  （2026-07-28 加）。** Playwright 的東西分三層，只有第三層歸機器，判準是**要不要 root**
  與**綁不綁專案版本**：語言套件（歸專案）／瀏覽器 binary（歸專案）／系統 `.so` + 字型
  （歸機器）。完整理由與 21 個套件的清單在 `playwright.yml` 檔頭。兩個容易走錯的地方：
  - **不掛 `node`。** Playwright 有 Node / Python / Java / .NET 四種綁定，那批 `.so` 對
    四者一模一樣；掛上去只會讓 Python 那條路平白拖一份 Node 進來。
  - **不下載瀏覽器。** build id 綁死語言套件的版本（實測 1.59.x ↔ build 1217、
    1.62.x ↔ 1234），機器層不知道專案 pin 哪版，猜錯就是一份沒人用的 630MB；而
    `~/.cache/ms-playwright` 本來就是 per-user 全域的，任一專案抓一次全機器共用。
  **字型是這個項目唯一的靜默失敗**，也是 `list.yml` 拿字型檔（而不是某個 `.so`）當偵測
  路徑的原因：少了 `.so`，chromium 當場起不來，大聲到不可能漏；少了 CJK 字型卻是
  **測試全綠、只有截圖裡的中文變豆腐** —— `textContent` / `getByRole` / `toBeVisible`
  讀的都是 DOM，不是畫出來的像素。實測同一段 20px 文字，有字型「登入」寬 40.00、
  無字型 24.00（差 40%，高度 27→24），所以版面是真的會偏，但沒有任何常見斷言在看寬度。
  只裝中文一個字型；日文／泰文／西里爾／emoji 官方清單雖然有，**沒有實測證據說少了會壞
  就不裝**（同 jq／ripgrep 那組判準）。`xvfb` 那批 11 個是 headed 模式用的，headless 實測
  完全不需要。
  **另記一個專案端的地雷**：Playwright **1.61 之前不認得 Ubuntu 26.04**，而且是下載階段
  就擋（`ERROR: Playwright does not support chromium on ubuntu26.04-x64`），`install-deps`
  一併失敗。那是專案升版就解決的事、機器層修不了；真的被迫留在舊版，逃生口是
  `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-x64`（**必須帶 `-x64`**，整字串替換不補
  arch），而且**只有下載時需要、執行時不用，所以不該寫進 `~/.profile`**。
- **`TAGS=ffmpeg`（2026-10-05 加）：系統 ffmpeg，走 apt，掛 `[tools, ffmpeg]`。** 為
  hyaku-monogatari 加的（Playwright 逐格截圖 → ffmpeg 合成 H.264 + AAC 的 MP4 短影片）。
  形狀跟 glab 一樣：別的 repo 的腳本會呼叫它，但不是這個 role 任何 installer 的相依，所以
  放 tools、不進 base。查到的東西：
  - **Playwright 附的 ffmpeg 不能拿來用，不是「多裝一份」。** `~/.cache/ms-playwright/
    ffmpeg-1011/ffmpeg-linux`（n7.0.1）的 configure 是 `--disable-everything` 再逐項打開，
    實測 `-encoders` 只有 `png` / `libvpx`（VP8）、`-muxers` 只有 `image2` / `webm`、
    `-decoders` 只有 `mjpeg` / `libvpx` —— 沒有 H.264、沒有 mp4、沒有任何音訊 encoder，
    連 PNG 截圖都讀不進來。
  - **不掛 `playwright`**：Playwright 自己錄影用的是附的那支，`TAGS=playwright` 的機器不需要
    系統 ffmpeg；需要它的是專案的合成步驟。同 `playwright.yml` 不掛 `node` 的理由。
  - **走 apt 不抓靜態 build**：Ubuntu 26.04 是 8.0.1（上游已到 9.0.2），但要的 libx264 與內建
    `aac` 是成熟到不需要追版的東西；靜態 build 要自己追版、對 checksum，還落在預設 PATH 之外。
  - **Recommends 照預設裝，查過數據才決定的。** `apt-get -s install [--no-install-recommends]
    ffmpeg` 對照：預設 104 個套件／安裝後 178.8MB／下載 70.5MB，關掉 Recommends 96 個／
    170.2MB／67.6MB。**ffmpeg 自己沒有 Recommends**，那 96 個全是 libavcodec62 / libsdl2 等的
    硬 Depends、關不掉；差的 8 個是下游函式庫的 Recommends（libbluray → libaacs0 / libbdplus0、
    libopenal1 → PipeWire client 一串、libdecor 的 GTK 外掛），跟編碼無關、合計 8.7MB。
    libx264-165 是 libavcodec62 的**硬 Depends**、`aac` 是內建 encoder，兩種裝法都編得出
    H.264 + AAC —— 所以這是純體積取捨，省 5% 不值得造出 repo 裡第一個帶
    `install_recommends: false` 的 apt task。**別把「ffmpeg recommends 很多」當前提**，
    看起來很多的那堆是 Depends。
  - **實測（本機套用）**：`make install TAGS=ffmpeg` → changed=1，dpkg.log 正好 104 個套件
    （跟模擬一致），重跑 changed=0；`ffmpeg -encoders` 有 `libx264` 與 `aac`；
    `testsrc=1080x1920:rate=30` + `sine` 編 2 秒 → ffprobe 看到 h264（High、yuv420p）與
    aac（LC）兩個串流、容器 mp4。apt 裝在 `/usr/bin`，不必 symlink、不碰 `profile.yml`。
- **`TAGS=gh`（2026-10-05 加）：GitHub 官方 CLI，走 GitHub 的官方 apt 套件庫，掛
  `[tools, gh]` —— 整個 repo 第一個（目前唯一一個）第三方 apt 套件庫。** 為了讓 Claude 查
  私有 repo 的 GitHub Actions 結果（`gh run list` / `gh run watch` / `gh run view --log-failed`）
  加的。形狀跟 glab 一樣是 tools；差在套件不能從 universe 拿。查到的東西：
  - **破例的理由是官方點名 universe 那支壞了，不是「想要新版」。** Ubuntu 26.04 universe 是
    2.46.0-4，而[官方安裝文件](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
    （Ubuntu Community 一節）寫：「As of November 2025, GitHub CLI maintainers strongly
    recommend official Debian packages especially as the community-distributed 2.45.x / 2.46.x
    version is broken due to deprecated GitHub APIs.」gh 是伺服器端會淘汰 API 的**客戶端**，
    舊版不是少功能而是不能用 —— 跟 lazygit / glab / ffmpeg 留在 universe 的理由（跟上游同代、
    不必追版）正好相反。下一個想加第三方套件庫的項目，要拿得出同等級的理由。
  - **金鑰網址、keyring 路徑、權限（`0644` = 文件的 `chmod go+r`）、URI / suite / component /
    arch / signed-by 全照官方文件**，只有來源檔格式不同：用 template 寫 deb822 的
    `github-cli.sources`，不是文件那行單行 `github-cli.list`。arch 用 `dev_env_arch`（Debian
    拼法，等於 `dpkg --print-architecture`）。不用 `apt_repository` / `deb822_repository` 的理由：
    - Ubuntu 26.04 自己的來源就是 deb822（`ubuntu.sources`），apt 3.2 內建
      `apt modernize-sources` 把單行轉過去；`apt_repository` 只會寫單行 `.list`。
    - `deb822_repository` 要 python3-debian，這台沒有；ansible-core 2.20 起
      `install_python_debian` 預設 false（沒有就失敗），而且 **check mode 下連自動安裝都不做**
      —— 實測 `--check` 回 `python3-debian must be installed to use check mode`，新機器上
      `make check TAGS=gh` 會整個中止。為一個六行的檔多裝一個只有 ansible 用得到的套件，不划算。
    - 來源檔本質上就是 `sources.list.d` 的 drop-in，用 template 寫是這個 repo 寫 drop-in 的
      既有做法（containers.conf.d / registries.conf.d / ssh config.d），check mode 的 diff 也準。
    - 上機前先在**不用 root 的私有 apt 目錄**（`apt-get -o Dir::Etc::SourceList=/dev/null
      -o Dir::Etc::SourceParts=<暫存> -o Dir::State=<暫存> -o Dir::Cache=<暫存>
      -o Debug::NoLocking=1 update`）拿渲染出來的檔與下載的 keyring 跑過：簽章驗過、
      檔頭的 `#` 註解不影響 deb822 解析、候選版本 2.102.0。加第三方來源前值得先這樣試。
  - **keyring pin 官方文件公布的 SHA256**（`get_url` 的 `checksum`）。金鑰真的會輪替：
    2026-10-05 抓到的那份裡有兩把，2022 那把（`…23F3D4EA75716059`）已在 2026-09-05 到期、
    2026-04-07 換上 `…5612B36462313325`，兩個指紋都跟文件頂端一致（`gpg --show-keys`）。
    pin 讓輪替變成大聲的失敗，而且修法只有一個：照文件改 checksum 再跑 —— get_url 發現既有檔
    對不上 pin 會重抓；**不 pin 的話 dest 已存在時 get_url 不會重抓**，舊機器只能手動刪檔。
  - **新來源加進去要立刻無條件 `apt update`，不能吃 `cache_valid_time: 3600`。** 一小時內
    update 過的機器（同一次 run 先跑了任何別的 apt 項目就是）會跳過刷新，快取裡還沒有官方
    套件庫，`name: gh` 就**靜默裝成 universe 的 2.46**。所以 keyring 或來源檔 changed 時另跑
    一次刷新。之後任何加第三方來源的項目都有同一個坑。
  - **`state: latest`，apt 小工具裡唯一不是 `present` 的。** 同一個理由（落後會壞），等於
    `go_version: latest`。也順手修掉「之前手動從 universe 裝過 2.46」的機器 —— `present` 會把它
    當成已經有了、原封不動。最後再 assert 裝到的版本 ≥ 2.47（`dpkg-query`），擋「官方來源沒抓到、
    靜默退回 universe」；check mode 跳過（沒真的裝，原本是 2.46 的機器會誤報）。
  - **不掛 base**：keyring 用 `get_url`（Python 發 HTTPS，不呼叫 curl），官方 gh 套件自己
    `Depends: git`；apt 走 https 要的 ca-certificates 是 Priority: important（同 node 對 xz-utils
    的判斷）。base.yml 當初拿掉的 gnupg / lsb-release 也照樣用不到：官方給的是二進位 keyring，
    suite 是固定的 `stable`。
  - **認證不在這裡做**（同 glab）：token 是資料不是軟體。使用者自己開 fine-grained token
    （查 Actions 只需要 Actions 唯讀）、`gh auth login --with-token`。role 不碰存 token 的
    `~/.config/gh/hosts.yml`（唯一碰 `~/.config/gh` 的是下面關 telemetry 那一個設定鍵）。
    **不要 `gh auth setup-git`**（互動式登入問 "Authenticate Git with your GitHub credentials?"
    也答 No）：它把 github.com 的 HTTPS credential helper 指向 gh；這台的 git 照舊走 SSH，
    `~/.gitconfig` 也不歸這個 role 管。
  - **gh 的 telemetry 一律關掉（使用者 2026-10-05 決定）**：2.102 預設開，第一次執行
    （`gh --version` 就算）會建 `~/.local/state/gh/device-id`，收集指令名稱、旗標、repo 是否公開、
    是否由 AI agent 執行等（官方說明 docs.github.com/en/github-cli/github-cli/github-cli-telemetry）。
    **用 `gh config set telemetry disabled`，不用 `GH_TELEMETRY=0` 環境變數**：`~/.profile` 只有
    登入 shell 讀，Claude Code 的 Bash 工具這類非登入 shell 跑 gh 時環境變數根本不在 —— 而那正是
    這台最常跑 gh 的地方。config 寫進 `~/.config/gh/config.yml`，誰跑都生效；gh.yml 先 `gh config
    get` 比對，已經是 disabled 就不動（冪等）。
  - **`make list` 的 gh 那列多印一行 `gh --version`**：官方新版與 universe 的 2.46 都是
    `/usr/bin/gh`，光打勾分不出來。做法是 `list.yml` 清單項目的選填 `version` 欄位（跑
    `<偵測路徑> <version>`、印輸出第一行），目前只有 gh 登記 —— 別的項目真有「有沒有分不出
    好壞」的情況再加，不要為了整齊全部補上。
  - **反安裝**見上面反安裝那條的 gh 子項。
  - **實測（本機套用）**：`make check TAGS=gh` 在還沒裝的機器上 changed=4、正常跑完；
    `make install TAGS=gh` → changed=4（keyring、來源檔、刷新、安裝），重跑 changed=0；
    `gh version 2.102.0 (2026-09-30)`；`apt-cache policy gh` 已裝版本來自
    `https://cli.github.com/packages stable/main`（universe 的 2.46.0-4 仍在候選表，版本較低
    不會被選）；`gh auth status` 回 "You are not logged into any GitHub hosts"；
    `apt-get -s purge --autoremove gh` 只拔 gh 一個。
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
- **`make install TAGS=xxx` 打錯字會靜默無事發生** —— ansible 對不存在的 tag 不報錯、只是
  什麼都不做，一路綠燈跑完卻一個套件都沒裝。Makefile 的 `_check-tags` 在動作前先比對
  `--list-tags` 的結果，不存在就 fail（實測 `make install TAGS=clade` → exit 2）。
  **別把這個 guard 拿掉**，它擋的是最難發現的那種失敗。
  - **`install` 不可以把任何 `--tags` 寫死。** 不帶 `TAGS` 就是不帶 `--tags`（＝全裝），
    跟底層 ansible 一對一。2026-07-28 有一版寫死 `--tags core`，結果 `make install TAGS=go`
    靜默裝成 core —— 隱藏的預設值就是這樣咬人的。
  - **`profile` 不必自己補**：它掛在 `[profile, claude, go, python, node, rust, podman]` 上，任何會
    影響 PATH 的項目都會帶到它（舊設計得記得寫 `TAGS=go,profile`）。仍然刻意**不用**
    `always` —— 那會讓 `make facts` 從唯讀變成會改 `~/.profile`。
- **指令介面只有 `make install TAGS=…`，不要再引入 `install-<項目>` 那種 target。**
  2026-07-28 試過 pattern rule (`install-%`) 版本、當天就拆掉了。**它能動**，但買到的只有
  「指令名說的是東西，不是過濾器」這一個語感差別，代價是二十幾行 make 機制加三個坑，
  而且多項安裝要跑兩次 ansible（`TAGS=go,python` 只跑一次）。三個坑記在這裡，免得誰又
  繞回去：
  - pattern rule 的 target-specific 變數**傳不到前置條件**（`install-%: TAGS = $*` 設好了，
    前置的 `_check-tags` 收到的仍是空字串），而且 phony 前置條件 make 只會做一次 ——
    `make install-go install-python` 只檢查得到第一個。驗證得搬進 recipe 用 `define`。
  - `_TAGS` / `_ARGS` 得從 `:=` 改成 `=`，否則 parse 時就把當時還空的 `TAGS` 定死，
    `make install-python` 靜默變成全裝。（**現在用 `:=` 是對的** —— 指令列變數在讀
    makefile 之前就設好了。）
  - target-specific 賦值要加 `override`，否則指令列變數優先權較高，
    `make install-go TAGS=python` 會裝 python。
  - 附帶：pattern rule **不能 tab 補完**。`make -npq` 只露出 `install-%` 這個字面。
- **`make python`（裸名 + catch-all `%:`）實測可行，但不要用。** 打錯字照樣 exit 1、
  既有 target 與預設 goal 都不會被攔截（實測過），所以別把它記成「行不通」。不用的理由是
  `%:` 會攔截整個 Makefile 命名空間裡任何不認得的字 —— 哪天有個工具叫 `list` 或 `check`，
  明確 target 會靜默贏。
  （**真正行不通的是 `make install python` 空格形式**：make 把它當成兩個 target，要撐起來
  得加 no-op catch-all `%:;@:`，而那會讓 `make pythn` 靜默成功什麼都不做。差別在 catch-all
  是不是安裝規則本身 —— 是的話驗證寫得進去，不是的話擋不住。）
- **`make init` 只補 ansible，不裝任何開發工具。** 它是「把機器準備到跑得動這個 repo」的
  入口，外加印出下一步。**不要讓它順手裝 Claude** —— Claude 是 `TAGS=claude` 這個選項之一，
  repo 的定位靠 `init` 的指引與 `list` 的排序表達，不靠偷偷幫你裝東西。
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
podman network rm -f fwtest && make install TAGS=podman   # 還原
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
自動起、socket 端到端通（實測）。所以 `make install TAGS=podman` 裝完，Windows 端跑一次 `wsl --shutdown`
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

**WSL 的 `/` 是 private mount propagation → 用 systemd unit 設成 rshared。**
（2026-07-28 大幅查證並修正；舊版這段的說法有兩處是錯的，見下。）

**根因：systemd 刻意跳過那一步，因為它認定自己在容器裡。** 上游
[`src/shared/mount-setup.c`](https://github.com/systemd/systemd/blob/main/src/shared/mount-setup.c)：

```c
if (detect_container() <= 0 && !leave_propagation)
    if (mount(NULL, "/", NULL, MS_REC|MS_SHARED, NULL) < 0)
        log_warning_errno(errno, "Failed to set up the root directory for shared mount propagation: %m");
```

註解原文：「kernel 預設是 private，但我們認為預設 shared 更合理，這樣 nspawn 和容器工具
才能開箱即用。」而本機 `systemd-detect-virt` 回的是 **`wsl`**（PID 1 確實是 systemd）→
**systemd 主動跳過這一行**；WSL 自己的 `/init` 也沒接手。兩邊都以為不該由自己做。

**不是「WSL 想隱藏 Windows 掛載層」——這個推測已用實驗排除。** ① 它擋不住任何東西：
`-v /mnt/c:/x` 直接讀到 `$Recycle.Bin`、`PerfLogs`。② WSL **自己**把 `/mnt/wsl`、
`/mnt/wslg` 設成 shared，要隔離就不會這樣做；`/mnt/c`、`/mnt/d` 是 private 只是**沒人
去設**的 kernel 預設。③ [microsoft/WSL#7477](https://github.com/microsoft/WSL/issues/7477)
要求改成預設 shared，已關閉且**沒有給出任何安全理由**。

**shared 才是 Linux 常態，這不是給 WSL 加 hack。** 一般 systemd 機器開機後 `/` 就是
shared；Docker 上游也把自己 unit 裡的 `MountFlags=slave` 拿掉
（[moby#22806](https://github.com/moby/moby/pull/22806)），Fedora/RHEL 更早就完全移除、
讓 daemon 直接跑在 host mount namespace。設 rshared 是把 WSL 漏掉的一步補回標準狀態。

**失敗形狀（實測，跟舊說法不同）**：

- **podman 5.7 已經不印 `"/" is not a shared mount` 警告了。** 舊版會印（本條原本就是照
  那句寫的），現在 `podman run` 是零輸出 —— **線索消失，所以更難查**。
- 真正的機制：rootless podman 有一個**長駐的 pause process** 持有 mount namespace
  （`/run/user/<uid>/libpod/tmp/pause.pid`）。容器看到的掛載表 = **那個 namespace 建立
  時的快照** ＋ 之後傳播進來的。`/` private ⇒ 第二項是零。
- 決定性對照（同一個目錄、同一條 `podman run`、`/` 都是 private，只差掛載時間點）：

  | tmpfs 掛載時機 | 容器內讀得到嗎 |
  |---|---|
  | pause process 建立**之前** | ✅ 讀得到 |
  | pause process 建立**之後** | ❌ `No such file or directory`（目錄在但是空的） |

- **判準是「時間點」，不是「有沒有巢狀 mount」**（本條原本寫成後者，那是錯的）：
  `-v /mnt:/x` 底下 `c`/`d`/`wsl`/`wslg` 全部正常，因為它們都是開機時就掛好的；普通檔案
  與普通巢狀目錄一律正常。自我檢查用 **`findmnt -R <要掛的路徑>`**，沒有輸出就代表那底下
  沒有掛載點、完全不受影響。
- 真正會踩到的場景只有一種：**podman 用過之後，才在 host 新掛東西**（插 USB、掛網路
  磁碟、kubelet 掛 PV）然後想掛進容器。k3s / CSI 是最常見的上游回報
  （`path /var/lib/kubelet is mounted on / but it is not a shared mount`）。

**壞處評估（查過，對本機不成立）**：shared 的已知代價是「容器建的 mount 洩漏到 host
且不被清掉、容器重啟還會重複累積」與隨之而來的 `device or resource busy`
（[moby#36179](https://github.com/moby/moby/issues/36179)）。但那**只在明確使用
`:rshared` / `bind-propagation=rshared` 時才發生** —— podman `-v` 的預設是 `rprivate`
（實測容器內 mountinfo 第 7 欄是 `-`），而 busy 那一類特別吃 devicemapper，本機是
overlay。要監控就看掛載表筆數（`wc -l < /proc/self/mountinfo`，基準 41）。

**實作與還原**：`podman.yml` 裝一個開機早期的 oneshot unit（`rshared-root.service`，
`is_wsl` gate，`Before=sysinit.target`）跑 `mount --make-rshared /`。手動下不持久
（`wsl --shutdown` 就沒了），必須走 unit。unit 除了 `enabled` 還要 **`state: started`**
——否則「裝完到下次重開」之間 `/` 仍是 private（實測過這個空窗）。
**不要用 `mount --make-rprivate /` 還原** —— 它是遞迴的，會把 WSL 刻意設成 shared 的
`/mnt/wsl`、`/mnt/wslg` 一起改掉，那才真的可能弄壞 WSLg。要還原就移掉 unit ＋
`wsl --shutdown`：傳播狀態不落地到任何檔案，重啟就回原廠，**不可能弄成永久壞掉**。

**只用 podman，不 alias `docker=podman`（使用者決定）。** alias task 是 `state: absent`
——套用時**主動移除** `.bashrc` 裡既有的那行，不只是不再加。**compose 也不裝**（2026-07
移除 `docker-compose` 二進位）。但 `DOCKER_HOST` 與 rootless `podman.socket` 保留 ——
那是給需要 Docker API 的工具（IDE、testcontainers）用的，跟 compose 是兩回事。將來要
compose，`podman compose` 需要一個外部 provider 二進位才會動。
