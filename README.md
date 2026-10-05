# dev-env-ansible

把一台 Linux 裝成開發環境的 Ansible role。定位很窄：**協助把 Claude Code 的開發環境
準備起來**，其他工具都是選用的。

```bash
make init                     # 起手：只補上 ansible-core，並印出下一步
make install TAGS=claude      # 裝 Claude Code（相依自動帶）
make install TAGS=go,python   # 挑幾項，一次做完
make install                  # 全裝
make list                     # 有哪些可裝、這台已經有哪些
make uninstall TAGS=go        # 移除一項（必須點名，不帶 TAGS 會被拒絕）
```

**沒有「無條件裝」的東西 —— 連 Claude 都是一個要點名的項目。** 這個 repo 的定位表現在
`make init` 的指引與 `make list` 的排序上，不表現在偷偷幫你裝東西。真正基礎到不能選的
只有 ansible 本身，那個歸 `make init`。

**相依會自動帶進來，你不必知道誰需要誰。** `TAGS=python` 會順便裝 `build-essential`
（uv 遇到沒有預編譯 wheel 時要現場編 C extension）與 `curl` / `ca-certificates`
（installer 要）；`TAGS=rust` 也帶這兩組（rustc 連結任何程式都拿 `cc` 當 linker）；
`TAGS=claude` 會帶 `curl` / `jq`；任何會影響 PATH 的項目都會順手更新 `~/.profile`。

（git 身分與**開機那組** SSH keys 不在這裡 —— 由 [`wsl-bootstrap`](../wsl-bootstrap) 在
bring-up 就備好，因為 key 得先在才能 clone 私有 repo，屬「一台個人機」而非軟體層。
**之後**才多出來的 git 網域則有 `make ssh-host`，見下。）

**Host-agnostic** —— WSL2 專屬的 task 用 `is_wsl` fact gate 起來，所以同一個 role 也能跑在
純 Ubuntu VM、homelab 節點或 WSL distro。搭配 [`wsl-bootstrap`](../wsl-bootstrap)：它產出一台
已開 systemd、可連的 WSL distro，讓你在上面接手裝軟體。

## 怎麼選要裝什麼：`TAGS=`，不是開關

2026-07-28 之前這個 repo 有一整組布林開關（`install_go`、`install_python`、
`container_runtime`…），寫在 `group_vars` 裡宣告「這台機器該有什麼」，再由 `make apply`
收斂過去。**那層整組移除了** —— 既然定位是「Claude 環境 + 用到時再裝的東西」，宣告式
那套就是多餘的第二種選擇機制。現在 tag 本身就是選擇，指令只有一個：

```bash
make install                    # 不帶 TAGS = 不帶 --tags = 全裝
make install TAGS=claude        # 一項
make install TAGS=go,python     # 多項，一次 ansible run 做完
make check   TAGS=podman        # 乾跑預覽同一件事
```

`make install` 不帶 `TAGS` 就是全裝，跟底層 `ansible-playbook` 不帶 `--tags` 一對一 ——
**刻意沒有隱藏的預設值**。要只裝 Claude 就明確寫 `TAGS=claude`。

**相依用 tag 表達，不是布林運算式。** `base.yml` 在 `main.yml` 掛
`[base, claude, python, rust]`、`build-tools.yml` 掛 `[build-tools, go, python, rust]`，於是
`--tags python` 自動把兩者都帶進來。多一個需要編譯器的東西只要在它的 import 多掛一個 tag
—— Rust 加進來時就是這樣，沒有改任何運算式。

一起消失的三個坑：相依關係不必再寫成布林運算式；`-e install_go=false` 傳字串 `"false"`
進 Jinja 被當 truthy 那類 `| bool` 陷阱沒有了；「單跑一個 tag 不會帶到 `profile`」也不再
需要記 —— `profile` 掛在每個會影響環境變數的 tag 底下。

打錯字會被擋：ansible 對不存在的 tag 不報錯、只是什麼都不做，所以 Makefile 在動作前先
比對一次真實的 tag 清單（`make install TAGS=clade` → exit 2）。

**代價講清楚**：沒有「一句話把這台機器收斂回我要的組合」了。以前讀 `group_vars` 就知道
這台該有什麼，現在得自己記得裝過哪些 —— 所以 `make list` 改成**偵測機器上實際有什麼**，
補上這個缺口。

## 反安裝：`make uninstall TAGS=<項目>`

```bash
make uninstall TAGS=go           # 拿掉 Go，模組快取留著（會報告大小）
make uninstall TAGS=go DATA=1    # 連 ~/go 與 build cache 一起清
make uninstall                   # 拒絕執行 —— 這個指令沒有「全砍」這個意思
```

**必須點名要移除什麼。** 這是跟 `install` 最重要的不對稱：`make install` 不帶 `TAGS`
是「全裝」，`make uninstall` 不帶 `TAGS` 是**拒絕**。沒有人該靠少打幾個字就把機器清空。

**只支援這個 role 獨佔擁有的項目**（`claude` / `go` / `python` / `node` / `rust`）。分界線是
**所有權**，不是難易度：`/usr/local/go`、`/usr/local/node`、`~/.local/share/claude`、
`~/.local/bin/uv`、`~/.rustup` 這幾個整包是我們放的，刪掉不牽動任何別的東西。

**apt 裝的（`podman` / `playwright` / `lazygit` / `glab` / `gh` / `git-lfs` / `ffmpeg` / `unzip` /
`base` / `build-tools`）要手動**，指令會擋下來並告訴你怎麼做。理由不是懶：apt 套件是共同
持有的，移除的連帶結果**取決於這台機器現在還裝了什麼** —— 例如 purge `tmux` 會把 `byobu`
與 `ubuntu-wsl` metapackage 一起帶走。同一個指令在兩台機器上結果不同，這種決定沒辦法替你做：

```bash
apt-get -s purge --autoremove <套件名>    # 先看影響範圍，這步不會動到系統
sudo apt purge --autoremove <套件名>      # 確認沒有誤傷再執行
```

**`gh` 多放了兩個這個 role 自己的檔**：GitHub 官方套件庫的 keyring 與來源檔（見下）。所有權
是我們的，所以 `make uninstall TAGS=gh` 印手動步驟時會把它們的確切路徑一起列出來（直接讀
`gh.yml` 裡的 `dest:`，不是另外抄的）；但它們的生命週期綁在套件上 —— 模擬完決定 purge 了才
該拿掉，否則留下的 gh 就斷了更新來源 —— 所以同樣是手動、purge 之後再刪，不進自動移除。

**工具與資料是兩個決定。** 預設只拿掉工具，快取／模組／已下載的 runtime 留著並報出
大小，要一起清才加 `DATA=1`。因為那些目錄常混著你自己的東西 —— 最典型是 `~/go`，
`go install` 裝的二進位（`bin/`）跟模組快取（`pkg/mod`）在同一棵樹底下。
**`~/.claude` 是例外中的例外**：設定、專案紀錄、hooks、memory 都在那裡，`DATA=1` 也不動。

**Rust 的 `~/.cargo` 是混住的，所以拆開處理。** `~/.rustup`（工具鏈本體）整包是 rustup 的，
直接刪；`~/.cargo` 裡則同時有 rustup 本體與它的 proxy、cargo 的下載快取、你 `cargo install`
的東西、你的 `config.toml` / `credentials.toml`。預設只拿掉 rustup 放的那些；`DATA=1` 再清
`registry/`、`git/` 兩個快取與 `cargo install` 的二進位（跟 Go 的 `~/go/bin`、uv 的
`uv tool` 同一個待遇）；`config.toml` / `credentials.toml` 跟 `~/.claude` 一樣永遠保留。
所以**不用 `rustup self uninstall`** —— 它會把整個 `~/.cargo` 連設定與 token 一起刪掉。

**沒有對稱的 `uninstall-check`，這是刻意的。** ansible 的 `--check` 對移除給的是**假的
安全感**：它只會說「這個 task 會 changed」，不會說 purge 某個套件會連帶帶走誰 —— 那個
資訊只有 `apt-get -s purge --autoremove` 產得出來。乾跑印完一片綠字，你還是得手動模擬
一次才敢按下去。安全性改由「必須點名」「只碰獨佔路徑」「資料預設保留」三件事提供。

**移除後 `~/.profile` 會自動重生**（`profile.yml` 是偵測式的，看機器上現在有什麼），
但**這個 repo 沒有記著「這台不該有什麼」** —— 所以下一次不帶 `TAGS` 的 `make install`
會把它裝回來。這是純命令式模型的必然代價，跟上面「沒有一句話收斂機器」是同一件事。

## 多一個 git 網域：`make ssh-host`

公司內部 GitLab、客戶的 Gitea、第二個 GitHub 帳號 —— 這些是 bring-up 之後才冒出來的，
一個指令搞定（設定 + 金鑰 + 公鑰印出來）：

```bash
make ssh-host HOST=gitlab.dev.baasgames.com          # 沒有 key 就生一把，印出公鑰
make ssh-host HOST=gitlab.dev.baasgames.com KEY=~/.ssh/id_ed25519_dev_gitlab   # 用既有的
make ssh-host-rm HOST=gitlab.dev.baasgames.com       # 移掉設定（key 保留）
```

**寫的是 `~/.ssh/config.d/<網域>.conf`，一個 host 一個檔**，並在 `~/.ssh/config` 檔頭補一行
`Include config.d/*.conf`（OpenSSH 7.3+ 就有；相對路徑一律以 `~/.ssh` 為基準）。
**不碰 wsl-bootstrap 的 managed 區塊** —— 兩支工具在同一個檔裡各切各的正規表示式是找麻煩，
所以所有權切乾淨：bootstrap 擁有它自己那對標記之間的內容，這裡擁有整個 `config.d/`。
理由跟 `containers.conf.d` / `registries.conf.d` 用 drop-in 是同一條。

界線是**時間，不是主題**：`github.com` / `gitlab.com` 仍然歸 bring-up（key 得先在才
clone 得動私有 repo，包含這個 repo 自己），日常再冒出來的網域歸這裡 —— 走 bring-up 得回
Windows 改 `config.ps1` 再重跑一次，那是為「建一台機器」設計的路徑，不是為「加一行設定」。

幾個刻意的選擇：

- **`KEY=` 指到的檔案不存在就直接失敗**，不順手生一把。那正是打錯路徑的樣子，而它的
  失敗會延遲很久才顯形（你拿舊公鑰去貼，然後對著 `Permission denied` 查半天）。真要在
  自訂路徑生新的就明講 `GEN=1`；不帶 `KEY` 時路徑是我們自己組的，沒有這個風險，所以
  預設就是「沒有就生」。
- **key 的預設名字用完整網域**（`id_ed25519_dev_gitlab_dev_baasgames_com`）。取第一段標籤
  會變成 `id_ed25519_dev_gitlab` —— 那正是 bring-up 給 `gitlab.com` 的那把，會靜默把同一把
  key 用到兩個不同平台。
- **不跑 `ssh-keyscan`**：那等於替你把第一次連線的指紋吞下去。指令最後印
  `ssh -T git@<網域>` 讓你自己連、自己確認。
- **寫完會問 `ssh -G <網域>` 驗一次**，確認它真的解析到那把 key。這比「檔案寫出去了」
  強得多 —— 順便驗到 Include 有沒有生效、有沒有被更早匹配的設定攔走（ssh 對每個關鍵字
  都是**先出現的贏**，不是後蓋前）。
- **移除只刪設定檔**，key 留著（同 `uninstall` 的 `DATA` 慣例），而且訊息裡的 key 路徑是
  **從那個檔讀出來**的，不是猜的 —— 印錯路徑會讓人 `rm` 掉別的東西。

commit 的名字／信箱不歸這裡管，仍然是 `~/.gitconfig` 那份全域設定。公司 repo 要用不同
身分，用 git 自己的 `includeIf`（按目錄切換）。

## 檔案結構

```
dev-env-ansible/
├── ansible.cfg
├── site.yml                    # 頂層 playbook（安裝）
├── uninstall.yml               # 反安裝的入口 —— 獨立 playbook，理由見下
├── ssh-host.yml                # make ssh-host 的入口 —— 吃參數，所以也是獨立 playbook
├── inventory/hosts.yml         # 管理的 host
└── roles/dev_env/
    ├── defaults/main.yml       # 只剩「怎麼裝」的參數（go_version、firewall driver）
    ├── templates/              # containers 設定 drop-in、systemd unit、ssh drop-in、gh 的 apt 來源
    └── tasks/
        ├── detect.yml          # 設定 is_wsl / dev_env_arch fact      (tags: always)
        ├── list.yml            # `make list` 的輸出                   (tags: [list, never])
        ├── base.yml            # curl/jq/git/ca-certs  (tags: [base, claude, python, rust])
        ├── build-tools.yml     # build-essential   (tags: [build-tools, go, python, rust])
        ├── claude.yml          # Claude Code（native installer）      (tags: claude)
        ├── unzip.yml           # unzip                        (tags: [tools, unzip])
        ├── lazygit.yml         # lazygit（git 的 TUI）      (tags: [tools, lazygit])
        ├── glab.yml            # glab（GitLab CLI）            (tags: [tools, glab])
        ├── gh.yml              # gh（GitHub CLI，官方 apt 套件庫）  (tags: [tools, gh])
        ├── git-lfs.yml         # git-lfs                    (tags: [tools, git-lfs])
        ├── ffmpeg.yml          # ffmpeg（合成 MP4）          (tags: [tools, ffmpeg])
        ├── go.yml              # Go binary（目標版本已在就跳過）      (tags: go)
        ├── python.yml          # uv                                   (tags: python)
        ├── node.yml            # Node 官方 tarball → /usr/local/node   (tags: node)
        ├── rust.yml            # rustup → stable + rustfmt / clippy    (tags: rust)
        ├── playwright.yml      # headless 瀏覽器的 .so + 中文字型    (tags: playwright)
        ├── podman.yml          # podman + .d drop-in                  (tags: podman)
        ├── uninstall.yml       # 反安裝：只碰 role 獨佔的路徑   (由 uninstall.yml 進入)
        ├── ssh-host.yml        # ~/.ssh/config.d 的 drop-in      (由 ssh-host.yml 進入)
        └── profile.yml         # ~/.profile 單一 managed block
                                #  (tags: [profile, claude, go, python, node, rust, podman])
```

**`ssh-host` 也是獨立 playbook，但理由跟 uninstall 不同：它吃參數。** site.yml 那邊每個
tag 都是「一個可以裝的東西」，塞一個要 `HOST=` 的進去會讓 `make list` 多出一個看起來可裝
、實際上不帶參數只會失敗的項目，還得再掛一個 `never`。參數化的動作跟可安裝項目是兩種
東西，各自有自己的入口比較誠實。

**反安裝為什麼是獨立 playbook，不是 `site.yml` 裡一個 tag。** 因為 ansible 的 `--tags`
是 **OR** 語意：`--tags uninstall,go` 會把「掛 uninstall 的 task」與「掛 go 的 task」
**兩邊都選中**，也就是連安裝 Go 的那段一起跑。tag 之間沒有 AND，所以「移除語境下的
go」沒辦法用 tag 組合表達。拆成兩個 playbook 之後，`--tags go` 在各自的檔裡都只有一種
意思，兩邊的 tag 命名空間互不干擾（Makefile 的 guard 會分別跟兩份 playbook 要清單，
所以 `make uninstall TAGS=podman` 認得出那是「apt 裝的、要手動」而不是「打錯字」）。

**相依關係就寫在 `main.yml` 的 tag 上。** 前兩個是相依層 —— `base.yml` 掛
`[base, claude, python, rust]`（那三個都要 `curl` 跑官方 installer）、`build-tools.yml` 掛
`[build-tools, go, python, rust]`。所以 `--tags python` 會自動把兩者都帶進來。`go.yml` 沒掛
`base` 是因為它走 ansible 的 `get_url`，不呼叫 `curl` 二進位。`rust` 掛 `build-tools` 的
理由比另外兩個硬：Go / uv 是「碰到 cgo / C extension 才要」，rustc 是**連 hello world 都要**
—— 它連結時拿 `cc` 當 linker driver，PATH 裡沒有 cc 就是「error: linker `cc` not found」
（實驗與原始碼證據見 CLAUDE.md）。

**一個項目一個 task 檔，apt 小工具也不例外。** 多裝一個工具就是開一個 `<工具>.yml`，
在 `main.yml` 掛 `tags: [tools, <工具>]` —— 於是 `TAGS=lazygit` 只裝那一個、`TAGS=tools`
是這一類整包。分類的判準是**這是誰的東西**：你自己會敲的掛 `tools`；別人的相依進
`base.yml`（installer 要的）或 `build-tools.yml`（編譯工具鏈）。`build-essential` 屬後者
—— 它不是你會敲的工具，是 Go 與 uv 的前置，所以掛在**它們的** tag 底下。

**`ffmpeg` 屬前者，但常被問「Playwright 不是附了一支嗎？」** 附的那支
（`~/.cache/ms-playwright/ffmpeg-<build>/ffmpeg-linux`）是錄影專用的閹割版，實測
`-encoders` 只有 `png` 與 `libvpx`（VP8）、muxer 只有 `webm` / `image2`、沒有任何音訊
encoder —— 要出 X / YouTube Shorts 吃的 MP4（H.264 + AAC）只能用系統的。走 apt：Ubuntu 的
8.0.1 就帶 libx264 與內建 aac encoder，不必自己追靜態 build 的版本。**不掛 `playwright`**：
Playwright 錄影用的是自己那支，需要系統 ffmpeg 的是專案的合成步驟。Recommends 照預設裝 ——
關掉只少 8 個跟編碼無關的套件（藍光解密、PipeWire client 等，8.7MB / 178.8MB），不值得讓它
成為唯一長得不一樣的 apt task（數據見 `ffmpeg.yml` 檔頭）。

**`gh` 也屬前者，但它是唯一加了第三方 apt 套件庫的項目。** Ubuntu universe 有 gh（26.04 是
2.46.0），可是 gh 官方的[安裝文件](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
點名那一版已經不能用：

> As of November 2025, GitHub CLI maintainers strongly recommend official Debian packages
> especially as the community-distributed `2.45.x` / `2.46.x` version is broken due to
> deprecated GitHub APIs.

gh 是 GitHub 官方的工具，也是一個伺服器端會淘汰 API 的客戶端 —— 舊版不是少功能，是不能用，
跟 lazygit / glab「universe 跟上游同代就夠」正好相反。所以 `TAGS=gh` 照官方步驟加
`https://cli.github.com/packages`：keyring 放 `/etc/apt/keyrings/githubcli-archive-keyring.gpg`
（pin 文件公布的 SHA256）、來源寫成 deb822 的 `/etc/apt/sources.list.d/github-cli.sources`
（Ubuntu 26.04 自己的 `ubuntu.sources` 就是這個格式），套件用 `state: latest` 跟著官方走版。
全程 ansible 內建模組，沒有 `curl | tee`；為什麼不用 `apt_repository` / `deb822_repository`、
金鑰輪替怎麼處理，見 `gh.yml` 檔頭。

**這個 role 只裝 gh，不做認證** —— 跟 glab 同一個立場：token 是資料不是軟體，不歸這裡管，
存 token 的 `~/.config/gh/hosts.yml` 也不碰。唯一的例外是用 `gh config set` 改兩個設定：
**關掉 gh 預設開啟的 telemetry**（不用環境變數，是因為非登入 shell 讀不到 `~/.profile`），
以及把 **`git_protocol` 設成 ssh**（gh 指令叫 git 時也走 SSH，跟這台的 git 一致）。自己開一把 fine-grained token（查 Actions 結果只需要 Actions 唯讀），
然後 `gh auth login --with-token`（從 stdin 讀）。**不要跑 `gh auth setup-git`**（互動式登入問
要不要 "Authenticate Git with your GitHub credentials" 也答 No）：git 照舊走 SSH（bring-up 的
key），不該讓 github.com 的 HTTPS credential helper 改去用這把只能讀 Actions 的 token。

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

**2. 起手 —— 只補上 ansible。**

```bash
make init     # 裝 ansible-core（bring-up 沒給），並印出下一步
```

**3. 先看有什麼可裝。**

```bash
make list     # 每一項怎麼叫、這台機器已經有哪些、可用的 tag
```

輸出長這樣 —— **✓／· 是當場 stat 出來的**，不是寫死的文件（所以這段只是示意，以你自己
跑出來的為準）：

```
可安裝的項目（✓ 這台機器上已經有 / · 還沒裝）

  · claude       Claude Code —— 這個 repo 的存在理由
  · go           Go latest（GOTOOLCHAIN=auto 管專案版本，不需要版本管理器）
  · python       uv（自己也管 Python 版本，所以不需要 pyenv）
  · node         Node.js 24.18.0 LTS + npm（官方 tarball，不需要 nvm）
  · rust         Rust stable + rustfmt / clippy（官方 rustup；專案版本由 rust-toolchain.toml 管）
  · playwright   headless 瀏覽器的系統相依（.so + 中文字型；Playwright 本身與瀏覽器歸專案端）
  · podman       rootless Podman + DOCKER_HOST（firewall driver: iptables）
  · lazygit      lazygit（git 的 TUI）
  · glab         glab（GitLab CLI；工作管理的 issue／MR 走它，裝完要自己 glab auth login）
  · gh           gh（GitHub CLI 官方套件庫 —— Ubuntu 的 2.46 已壞；裝完要自己 gh auth login）
  · git-lfs      git-lfs（沒裝不會報錯 —— clone 拿到的是 pointer，commit 會把大檔直接塞進 git）
  · ffmpeg       ffmpeg（合成 MP4：H.264 + AAC；Playwright 附的那支只有 VP8／WebM）
  · unzip        unzip（不少 release 只出 zip）

相依層 —— 上面的項目會自動帶進來，很少需要自己點：

  · base         claude / uv / rustup 的 installer 相依（清單見 base.yml）
  · build-tools  build-essential —— Go cgo / uv C extension / rustc linker 的前置

可用的 tag（直接跟 playbook 要的，不是手抄）：
    base build-tools claude ffmpeg gh git-lfs glab go lazygit list node playwright podman profile python rust tools unzip
```

`gh` 裝了的話，那列底下會多印一行 `gh --version` —— 官方套件庫的新版與 Ubuntu universe 那支
壞掉的 2.46 都是 `/usr/bin/gh`，光打勾分不出是哪一支。

**4. 裝。**

```bash
make install TAGS=claude        # 這個 repo 的存在理由，先裝它
make install TAGS=go,python     # 之後用到什麼再裝什麼
make install                    # 或一次全裝
```

只想先看不動手：`make check TAGS=python`（或不帶 TAGS 看全部）。tag 打錯字
**ansible 自己不會報錯、只會什麼都不做**，所以 Makefile 在動作前先比對一次真實的 tag
清單，不存在就直接失敗（`make install TAGS=clade` → exit 2）。

**5. 裝了 podman 的話，回 Windows 端 full shutdown。** 讓 rootless `podman.socket` 在乾淨
session 起來（原因見下）：

```powershell
wsl --shutdown
```

**6. 收尾**（手動接上平台，刻意不自動化）。SSH keys 與 git 身分 bring-up 已備好，剩貼與認證：

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
make list                    # 忘了有哪些項目 / 這台裝了哪些 —— 唯讀，不會動到機器
make check   TAGS=podman     # 預覽某一項會動什麼（diff）；LOCAL 預設 1，在 distro 內不用帶
make install TAGS=podman     # 套用
make install                 # 或把全部重跑一次（會跟著上游走版，例如 Go latest）
make uninstall TAGS=node     # 用不到了就拿掉（apt 裝的會擋下來並教你手動怎麼做）
make ssh-host HOST=gitlab.dev.baasgames.com   # 多一個 git 網域（設定 + key + 印公鑰）
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

開發環境需要「每個專案用不同的語言版本」，但這個 role **刻意不裝通用版本管理器**：

| | 怎麼切版本 | 這個 role 做什麼 |
|---|---|---|
| **Go** | 語言內建。Go 1.21+ 預設 `GOTOOLCHAIN=auto`，`go.mod` 要求更新的版本時 `go` 指令自動下載並改用對應 toolchain | 只裝一個 bootstrap Go |
| **Python** | `uv` 自己管：`uv python install`、讀 `.python-version`、`uv run` 會自動抓缺的版本（預編譯 standalone build，不用現場編譯） | 裝 uv |
| **Node** | 不切。裝一個 LTS，版本 pin 在 `node_version` | 官方 tarball → `/usr/local/node` |
| **Rust** | rustup 自己管：專案根目錄放 `rust-toolchain.toml`，rustup 讀到就自動抓那個版本（`auto-install` 預設開） | 裝 rustup + 一個 stable |

**rustup 本身就是工具鏈管理器，這不違反「不裝版本管理器」。** 那條擋的是 mise / asdf 這種
跨語言、外掛式的東西；rustup 是 Rust 官方唯一的發行管道，跟 uv 之於 Python 同一個位置。
它也過得了「非互動 shell 拿不拿得到」那關（proxy 是真實路徑上的檔案，不是 shell function）。
Rust 沒有 `rust_version` 這種變數：機器層永遠是 **stable**，而且每次跑到 `rust` 這個 tag
都會跟著上游走版（同 `go_version: latest`）；要 pin 就是專案的 `rust-toolchain.toml`。
注意它裝的是 **minimal profile + rustfmt + clippy**（＝default 拿掉 737MB 的離線文件
rust-docs），這個 profile 會記在 `~/.rustup/settings.toml`，所以 `rust-toolchain.toml`
自動抓的版本也只有 minimal —— 專案要 fmt / clippy 就在那份檔裡列
`components = ["rustfmt", "clippy"]`（CI 本來也需要）。

Node 是四者中唯一沒有內建解法的，但**它也不需要版本管理器**，因為前端專案宣告的幾乎都是
**地板**而不是 pin（例：vite 8 要 `^20.19 || >=22.12`）—— 一個 active LTS 就蓋過去了。
真的出現硬衝突（A 要 20、B 要 26）時，隔離該待在**專案層**（那個專案自己的 devcontainer，
podman 已經裝好了），不是機器層。為了一個還不存在的衝突先在機器上疊一層抽象，代價比收益大。

**特別不要用 nvm** —— 它是 shell function 且 `install.sh` 在 bash 下只寫 `~/.bashrc`，而
Ubuntu 的 `.bashrc` 開頭對非互動 shell 直接 `return`，所以 `wsl -d dev -e node`、cron、
IDE、ansible 全都拿不到 node（這個 repo 2026-07 之前就是這樣）。`fnm` 同樣靠 shell hook。
`mise` 有 shims 那條真實路徑所以技術上可行，`volta` 則已宣告 unmaintained 並自己指向 mise。
apt 那條路也不通：Ubuntu 的 `nodejs` 套件不含 npm，而 apt 的 `npm` 停在 9.2.0 還會拖進
約 70 個 `node-*` 套件。官方 tarball 附帶版本相符的 npm 與 corepack，是真實路徑的 binary。

**要換 Node 版本就改 `defaults/main.yml` 的 `node_version`，然後 `make install TAGS=node`。**
`node_version` 刻意**不支援 `latest`**（跟 `go_version` 相反）：Node 的奇數版不進 LTS、
只活半年，追 latest 會定期把機器推到非 LTS 上。

### WSL 特有：PATH 順序才是 Node 真正的地雷

WSL 預設把 Windows PATH 接進來，且 `/mnt/c` 底下的檔案全被當成可執行 —— 所以 Linux 端沒裝
Node 時，`npm` 會解析到 `/mnt/c/Program Files/nodejs/npm`（**Windows 版**），在 WSL 裡跑
`npm ci` 會裝出一整包 Windows 原生模組（`*-win32-x64-msvc`），在 Linux 下完全不能用。
`profile.yml` 把 `/usr/local/node/bin` 放在 `$PATH` **前面**就是在擋這個。

**但光靠 `~/.profile` 擋不住，因為它只有登入 shell 會讀。** 行程樹的根不是登入 shell 的
情境（`wsl.exe -e`、systemd unit、cron、Windows 側 spawn 的東西、未來的
`ssh dev '<cmd>'`）全都讀不到 —— 2026-07-28 實測 `wsl -d dev -e bash -c 'command -v npm'`
拿到的正是 Windows 那支。所以凡是**沒有裝進預設 PATH** 的執行檔，role 都另外 symlink 進
`/usr/local/bin/` —— 那個目錄在上述每個 context 的預設 PATH 裡都有，而且排在 Windows
路徑前面：

| 來源 | symlink 的執行檔 |
|---|---|
| `node.yml`（`/usr/local/node/bin`） | `node` `npm` `npx` `corepack` |
| `go.yml`（`/usr/local/go/bin`） | `go` `gofmt` |
| `claude.yml`（`~/.local/bin`） | `claude` |
| `python.yml`（`~/.local/bin`） | `uv` `uvx` |
| `rust.yml`（`~/.cargo/bin`） | `cargo` `rustc` `rustdoc` `rustfmt` `rustup` |

apt 裝的（podman、lazygit、glab、gh、unzip、git-lfs、ffmpeg、base、build-tools、playwright 的
`.so`）本來就在 `/usr/bin`，不需要處理。

兩個機制互補，都需要：symlink 管固定入口，`.profile` 的 PATH 管**裝完之後才長出來**的
東西（`npm i -g` 的 bin 在 `/usr/local/node/bin`、`go install` 的在 `~/go/bin`，那些不會
被 symlink 到）。要驗就實跑 `wsl -d dev -e bash -c 'command -v <cmd>'` —— 用互動 shell
驗一定是綠的，驗不出東西。

`rust` 那列要多驗一件事：rustup 的 cargo / rustc / rustfmt… 都是指向**同一支** `rustup`
的 symlink，靠 argv[0] 決定要當誰，所以 `/usr/local/bin/cargo` 是兩段鏈。實測經由 symlink
執行時分流照樣正確；`cargo clippy` / `cargo fmt` 不必另外連（cargo 本來就會在
`~/.cargo/bin` 找子命令），在只有 `/usr/bin:/bin:/usr/local/bin` 的 `env -i` 與
`wsl -d dev -e` 下都實測通過。

`claude` / `uv` / `rust` 那三列有個 go / node 沒有的但書：目標在 `$HOME` 底下，所以這支 root
擁有的 symlink 綁死了一個使用者。這個 role 本來就是「一台機器供一個開發者」的模型
（`~/.profile`、`~/.claude`、rootless podman 都只服務一個 uid），所以可以這樣做；同機
真的要跑第二個使用者時要知道那會是後寫的贏，細節見 CLAUDE.md。

已經誤裝過的專案，**光裝 Node 不會自動修好** —— 要先把舊的整包砍掉：

```bash
cd <專案>
rm -rf node_modules && npm ci
```

`rm -rf` 這步不能省：不少專案的 Makefile 用 `node_modules: package-lock.json` 這種時間戳
規則判斷要不要重裝，而誤裝出來的 `node_modules` 比 lock 檔**新**，`make init` 會直接跳過
`npm ci`、靜默沿用那堆 Windows 二進位。

## 設定

`defaults/main.yml` 只剩「**怎麼裝**」的參數 ——「**裝不裝**」由你在指令列點名，不再有
變數。可在 `inventory/hosts.yml`、`group_vars/` 或 `host_vars/` 覆蓋：

| 變數 | 預設 | 控制 |
|---|---|---|
| `go_version` | `latest` | `latest` **每次跑到 `go` 這個 tag 都查 go.dev**（會跟著上游走版），或 pin 如 `1.26.5` |
| `podman_firewall_driver` | WSL 上 `iptables`，否則 `nftables` | netavark firewall driver。**一律明寫**，因為 netavark 的預設是編譯期決定的、換發行版就可能不同。可用 `iptables` / `nftables` / `firewalld` / `none`，或 `''` 表示完全不管 |

**這個 role 只裝不卸。** 沒有「解除安裝」的目標，也刻意不做 —— 卸載是破壞性動作，不該由
每次安裝順手跑一遍。要它真的從機器上消失是手動的事（`sudo apt purge --autoremove <pkg>`）。
動手前先 `apt-get -s purge --autoremove <pkg>` 看一次影響範圍，發行版自帶的套件尤其要看
（例如 `tmux` 是 Ubuntu WSL image 內建，purge 它會連 `byobu` 與 `ubuntu-wsl` metapackage
一起拔掉）。

**實測體積**（讓取捨有依據）：`build-essential` 260MB / 43 個套件，跟 Go 的 269MB、
Claude Code 的 263MB 同級 —— 它不是異常值。相對地整份 CLI 小工具只有約 24MB。
所以該不該裝 `build-essential` 的判準是「你編不編 native 東西」，不是體積 ——
而多數時候你不必自己判斷，`TAGS=go` / `TAGS=python` 會替你帶進來。

（SSH keys / git 身分的設定在 `wsl-bootstrap` 的 `config.ps1`，不在這裡。）
