SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
.NOTPARALLEL:

# ---- 可由外部覆蓋 ----------------------------------------------------------
# 注意：這些 ?= 後面不要接行內 `# 註解` —— make 會把「值到 `#` 之間的空白」算進變數值
# （LOCAL 會變 "1   " 讓 $(filter 1,…) 對不上），故註解一律另起一行。
INVENTORY ?= inventory/hosts.yml
PLAYBOOK  ?= site.yml
# 反安裝走自己的 playbook —— ansible 的 --tags 是 OR 語意，沒辦法用 tag 組合表達
# 「移除語境下的 go」（詳見 uninstall.yml 檔頭）。
UNPLAYBOOK ?= uninstall.yml
# git host 的 SSH 設定（`make ssh-host`）也走自己的 playbook —— 它吃參數而不是 tag，
# 理由見 ssh-host.yml 檔頭。
SSHPLAYBOOK ?= ssh-host.yml
# TAGS：要裝什麼就寫在這裡，例 `make install TAGS=claude`、`TAGS=go,python`。
# 不設就是全部。有哪些可用跑 `make list`——刻意不在這裡列，手抄一份就會漂移。
TAGS      ?=
LIMIT     ?=
# LOCAL=1：對本機 localhost 跑（在 distro 內用就對了）；控制節點模式設 LOCAL=0
LOCAL     ?= 1
EXTRA     ?=
# DATA=1：只給 `make uninstall` 用 —— 連資料（模組快取、build cache、uv 裝的 Python
# runtime…）一起清，不只拿掉工具本身。預設保留，理由見 defaults/main.yml。
DATA      ?=
# 下面四個只給 `make ssh-host` / `make ssh-host-rm` 用。
# HOST 必填（要設定的網域）；其餘可選：
#   KEY=<路徑>   用既有的 key（不存在就失敗 —— 那是打錯路徑的樣子）
#   GEN=1        允許在 KEY 指的路徑上生一把新的
#   COMMENT=<字> 生 key 時的註解，預設 <user>@<hostname>-<host> <日期>
# 不帶 KEY 時本來就是「沒有就生」，不需要 GEN。
HOST      ?=
KEY       ?=
GEN       ?=
COMMENT   ?=

# ---- 內部組裝 --------------------------------------------------------------
# COMMA：localhost, 裡的逗號會跟 $(if) 的引數分隔逗號相撞，必須用變數繞過。
COMMA  := ,
_CONN  := $(if $(filter 1,$(LOCAL)),-i localhost$(COMMA) -c local,-i $(INVENTORY))
_TAGS  := $(if $(TAGS),--tags $(TAGS),)
_LIMIT := $(if $(LIMIT),--limit $(LIMIT),)
_ARGS  := $(_CONN) $(_TAGS) $(_LIMIT) $(EXTRA)

# 直接跟 playbook 要真實的 tag 清單（單一事實來源）。濾掉 never / always —— 兩者都是
# 機制標記（「不明確指定就不跑」、「一律跑」），不是使用者該挑的項目。pipefail 已開，
# ansible 失敗不會被後面永遠回 0 的 sed/tr 洗掉（見 CLAUDE.md 那條「別把 exit code 洗掉」）。
#
# 寫成 $(call) 是因為現在有兩個 playbook 要問：site.yml（可裝什麼）與 uninstall.yml
# （可移除什麼）。兩份清單刻意不同 —— apt 的項目只出現在前者。
_TAGS_OF = ansible-playbook $(1) $(_CONN) --list-tags \
	| sed -n 's/.*TASK TAGS: \[\(.*\)\]/\1/p' \
	| tr -d ' ' | tr ',' '\n' | grep -vxE 'never|always' | paste -sd' '
_TAGS_OF_PLAYBOOK  = $(call _TAGS_OF,$(PLAYBOOK))
_TAGS_OF_UNINSTALL = $(call _TAGS_OF,$(UNPLAYBOOK))

.PHONY: help init list check install uninstall ssh-host ssh-host-rm syntax lint facts \
	_ensure-ansible _check-tags _check-uninstall-tags _check-ssh-host

help: ## 顯示所有可用命令
	@awk 'BEGIN {FS = ":.*##"; printf "\n使用方式:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	echo
	echo "要裝什麼用 TAGS=，例 make install TAGS=claude 或 TAGS=go,python。"
	echo "不確定有什麼可裝？先跑 make list —— 它會列出每一項，並標出這台機器已經有哪些。"
	echo
	echo "移除是 make uninstall TAGS=<項目> —— 必須點名，不帶 TAGS 會被拒絕（沒有「全砍」）。"
	echo "只支援 tarball / installer 裝的那幾項；apt 裝的要手動，指令會告訴你怎麼做。"
	echo
	echo "多一個 git 網域（例：公司內部 GitLab）用 make ssh-host HOST=gitlab.example.com ——"
	echo "沒有 key 就生一把並印出公鑰，設定寫進 ~/.ssh/config.d/<網域>.conf。"

##@ 起手（乾淨機器）
# bring-up 給的 baseline 只有 git + make。這個 target 把機器準備到「跑得動這個 repo」
# 為止，也就是補上 ansible-core，然後告訴你下一步。
#
# **刻意不裝任何開發工具，連 Claude 都不裝** —— Claude Code 是 `TAGS=claude` 這個選項
# 之一。這個 repo 的定位表現在下面的指引與 `make list` 的排序，不表現在偷偷幫你裝東西。
init: _ensure-ansible ## 起手：補上 ansible-core，並印出下一步
	@echo
	echo "ansible 就緒。接下來："
	echo "  make list                     看有哪些可裝、這台已經有哪些"
	echo "  make install TAGS=claude      只裝 Claude Code（這個 repo 的存在理由）"
	echo "  make install                  全裝"
	echo
	echo "另外兩件手動的事（刻意不自動化）："
	echo "  1. SSH 公鑰貼到 GitHub / GitLab（bring-up 已生成）："
	echo "       cat ~/.ssh/id_ed25519_*.pub"
	echo "  2. 裝完 Claude 後跑一次 claude，做瀏覽器 OAuth"

##@ 安裝（Ansible）
# 不帶 TAGS = 不帶 --tags = 全部，跟底層 ansible 一對一，沒有隱藏的預設值。
# 相依會自動帶進來（TAGS=python 會拉 base + build-tools + profile），不必自己列。
install: _ensure-ansible _check-tags ## 裝東西：不帶 TAGS 全裝，或 TAGS=claude / TAGS=go,python
	ansible-playbook $(PLAYBOOK) $(_ARGS)

##@ 移除
# **必須點名 TAGS，不帶就拒絕** —— 這是這個 target 的安全機制，也是跟 install 最重要的
# 不對稱：install 不帶 TAGS 是「全裝」，uninstall 不帶 TAGS 是「拒絕」。這個指令沒有
# 「全砍」這個意思，也不該有人靠少打幾個字就得到它。
#
# 刻意**沒有**對稱的 `uninstall-check`：ansible 的 `--check` 對移除給的是假的安全感
# （它看不到 apt 的連帶移除），完整理由在 roles/dev_env/tasks/uninstall.yml 檔頭。
#
# 只支援這個 role 獨佔擁有的項目（tarball / installer 裝的那幾個）。apt 裝的由下面的
# guard 擋下並印出手動步驟 —— 那類移除的後果取決於機器現況，必須人看過模擬再決定。
uninstall: _ensure-ansible _check-uninstall-tags ## 移除：必須帶 TAGS，例 TAGS=go；加 DATA=1 連快取一起清
	ansible-playbook $(UNPLAYBOOK) $(_CONN) --tags $(TAGS) $(_LIMIT) $(EXTRA) \
		$(if $(filter 1,$(DATA)),-e dev_env_uninstall_data=true,)

##@ git host 的 SSH 設定
# 「之後才多出來的網域」用的（典型：公司內部 GitLab）。開機那一組（github.com /
# gitlab.com）仍然歸 bring-up —— 界線是時間不是主題，理由見 tasks/ssh-host.yml 檔頭。
#
# 寫的是 `~/.ssh/config.d/<host>.conf`（一個 host 一個檔），並在 `~/.ssh/config` 檔頭補一行
# `Include config.d/*.conf`。**不碰 wsl-bootstrap 的 managed 區塊**，兩邊所有權完全分開。
#
# result_format=yaml 的理由同 `make list`：最後那則說明是多行的（公鑰、驗證指令），
# 用預設的 JSON 格式會被壓成一行滿是 \n 的字串，正好是最需要看清楚的那一則。
ssh-host: _ensure-ansible _check-ssh-host ## 加一個 git host：HOST=gitlab.example.com [KEY= GEN=1 COMMENT=]
	@ANSIBLE_CALLBACK_RESULT_FORMAT=yaml \
	ansible-playbook $(SSHPLAYBOOK) $(_CONN) $(_LIMIT) $(EXTRA) \
		-e ssh_host='$(HOST)' \
		$(if $(KEY),-e ssh_host_key='$(KEY)',) \
		$(if $(filter 1,$(GEN)),-e ssh_host_gen=true,) \
		$(if $(COMMENT),-e ssh_host_key_comment='$(COMMENT)',)

# 只刪 ~/.ssh/config.d 那個檔。**key 一律保留**（key 是資料，同 uninstall 的慣例），
# 那行 Include 也留著 —— 對空目錄無害，下次再加就直接生效。
ssh-host-rm: _ensure-ansible _check-ssh-host ## 移除一個 git host 的 SSH 設定（key 保留）
	@ANSIBLE_CALLBACK_RESULT_FORMAT=yaml \
	ansible-playbook $(SSHPLAYBOOK) $(_CONN) $(_LIMIT) $(EXTRA) \
		-e ssh_host='$(HOST)' -e ssh_host_state=absent

##@ 先看再動
# 三個「先看」的指令，回答的是不同問題：
#   list     —— 有哪些可裝、這台機器已經有哪些（唯讀，不改任何東西）
#   check    —— 這次會改哪些檔（真的去 host 上比對）
#   facts    —— 偵測到的環境（is_wsl / arch / uid）
# result_format=yaml 是為了讓 debug 的多行字串好好斷行；注意**不能**改成
# stdout_callback = yaml，那個舊 callback 在 ansible-core 2.20 已移除（見 CLAUDE.md）。
list: _ensure-ansible ## 有哪些可裝的項目、已裝了哪些、可用的 tag（唯讀）
	@ANSIBLE_CALLBACK_RESULT_FORMAT=yaml \
		ansible-playbook $(PLAYBOOK) $(_CONN) $(_LIMIT) $(EXTRA) --tags list
	echo "可用的 tag（直接跟 playbook 要的，不是手抄）："
	echo "    $$($(_TAGS_OF_PLAYBOOK))"
	echo

check: _ensure-ansible _check-tags ## 乾跑預覽：列出會改什麼、不套用（--check --diff）；同樣吃 TAGS=
	ansible-playbook $(PLAYBOOK) $(_ARGS) --check --diff

facts: _ensure-ansible ## 印出偵測到的環境（is_wsl / arch / uid）
	ansible-playbook $(PLAYBOOK) $(_CONN) $(_LIMIT) $(EXTRA) --tags always

##@ 檢查
syntax: _ensure-ansible ## 語法檢查（不連線）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --syntax-check

lint: ## ansible-lint（需先裝 ansible-lint）
	@command -v ansible-lint >/dev/null 2>&1 || { echo "Error: ansible-lint 未安裝"; exit 1; }
	ansible-lint

# ---- 內部 ------------------------------------------------------------------
# ansible 對不存在的 tag **不報錯**，只是什麼都不做 —— `make install TAGS=pythn` 會
# 一路綠燈跑完卻一個套件都沒裝，是最難發現的那種失敗。這裡在動作之前先比對一次真實
# 的 tag 清單，把它變成大聲的錯誤。**別把這個 guard 拿掉。**
# TAGS 沒設就直接跳過（那是「全裝」，沒有東西要驗，也不多花一次 ansible 啟動）。
_check-tags: _ensure-ansible
	@[ -n "$(TAGS)" ] || exit 0
	known="$$($(_TAGS_OF_PLAYBOOK))"
	bad=""
	for t in $$(echo '$(TAGS)' | tr ',' ' '); do
		case " $$known " in
			*" $$t "*) ;;
			*) bad="$$bad $$t" ;;
		esac
	done
	if [ -n "$$bad" ]; then
		echo "Error: playbook 裡沒有這些 tag：$$bad" >&2
		echo "可用：$$known" >&2
		echo "（跑 make list 看每一項是什麼）" >&2
		exit 1
	fi

# uninstall 的 guard。比 _check-tags 多做兩件事：
#
#   1. **TAGS 空的就拒絕**。這是整個 uninstall 最重要的一道防線 —— 不帶 TAGS 絕不可以
#      退化成「全砍」，也不可以靜默什麼都不做（那會讓人以為砍過了）。
#   2. 對「site.yml 裡有、uninstall.yml 裡沒有」的 tag 給**專屬的錯誤訊息**，而不是
#      籠統的「沒有這個 tag」。那些正是 apt 裝的項目，使用者需要知道的不是「打錯了」，
#      而是「這類東西為什麼要手動、手動怎麼做」。
_check-uninstall-tags: _ensure-ansible
	@if [ -z "$(TAGS)" ]; then
		echo "Error: make uninstall 必須點名要移除什麼，例：" >&2
		echo "    make uninstall TAGS=go" >&2
		echo "    make uninstall TAGS=go,node DATA=1" >&2
		echo >&2
		echo "install 不帶 TAGS 是「全裝」，uninstall 不帶 TAGS 一律拒絕 ——" >&2
		echo "這個指令沒有「全砍」這個意思。" >&2
		exit 1
	fi
	known="$$($(_TAGS_OF_UNINSTALL))"
	# 從「可裝的」裡拿掉兩個**機制** tag：list 是 make list 的入口、profile 是被別的項目
	# 帶著跑的收尾。它們不是「可安裝的東西」，所以 `make uninstall TAGS=profile` 應該回
	# 「沒有這個項目」，而不是掉進下面那段「這是 apt 裝的」——後者會講出假話。
	# 這兩個名字寫死在這裡是可以接受的：它們是 main.yml 的結構，不是會增減的套件清單。
	installable="$$($(_TAGS_OF_PLAYBOOK) | tr ' ' '\n' | grep -vxE 'list|profile' | paste -sd' ')"
	bad=""
	manual=""
	for t in $$(echo '$(TAGS)' | tr ',' ' '); do
		case " $$known " in
			*" $$t "*) continue ;;
		esac
		case " $$installable " in
			*" $$t "*) manual="$$manual $$t" ;;
			*) bad="$$bad $$t" ;;
		esac
	done
	if [ -n "$$bad" ]; then
		echo "Error: 沒有這些項目：$$bad" >&2
		echo "可以移除的：$$known" >&2
		echo "（跑 make list 看每一項是什麼）" >&2
		exit 1
	fi
	if [ -n "$$manual" ]; then
		echo "Error: 這些是 apt 裝的，不提供自動反安裝：$$manual" >&2
		echo >&2
		echo "apt 套件是共同持有的 —— 移除的連帶結果取決於這台機器現在還裝了什麼，" >&2
		echo "同一個指令在兩台機器上結果不同（例：purge tmux 會一起帶走 byobu 與" >&2
		echo "ubuntu-wsl）。這種決定沒辦法替你做，所以不包成指令。手動兩步：" >&2
		echo >&2
		echo "    apt-get -s purge --autoremove <套件名>    # 先看影響範圍，不會動到系統" >&2
		echo "    sudo apt purge --autoremove <套件名>      # 確認沒有誤傷再執行" >&2
		echo >&2
		echo "套件名看 roles/dev_env/tasks/ 底下對應的檔案（那是唯一的事實來源）。" >&2
		echo "可以自動移除的：$$known" >&2
		exit 1
	fi

# ssh-host / ssh-host-rm 的 guard。只擋一件事：**HOST 沒給**（同 uninstall 的「必須點名」
# ——「加一個 host」與「移除一個 host」都沒有「全部」這個意思）。順便把目前設定過的列出來，
# 因為忘記的通常不是指令而是「我當初打的是哪個網域」。
#
# HOST 的**格式**檢查刻意不放這裡，留在 tasks/ssh-host.yml 的 assert：規則只該有一份，
# 抄成兩份就會漂移（list.yml 檔頭記過同一個教訓）。
_check-ssh-host:
	@if [ -n "$(HOST)" ]; then exit 0; fi
	echo "Error: 必須點名 HOST，例：" >&2
	echo "    make ssh-host    HOST=gitlab.dev.baasgames.com" >&2
	echo "    make ssh-host-rm HOST=gitlab.dev.baasgames.com" >&2
	echo >&2
	d="$$HOME/.ssh/config.d"
	if compgen -G "$$d/*.conf" >/dev/null 2>&1; then
		echo "目前設定過的 host（$$d）：" >&2
		for f in "$$d"/*.conf; do
			echo "    $$(basename "$$f" .conf)" >&2
		done
	else
		echo "（$$d 底下還沒有任何設定；bring-up 給的 github.com / gitlab.com 不在這裡" >&2
		echo "  ——那組在 ~/.ssh/config 的 wsl-bootstrap 區塊裡，本指令不碰）" >&2
	fi
	exit 1

# bring-up 只給 git+make；ansible 由這裡自己補（不能用 ansible 裝 ansible）。
# 是所有 ansible target 的前置，所以就算沒先跑 make init 也不會卡住 —— init 的價值
# 在於「明確的起手入口 + 印出下一步」，不是獨佔這件事。
_ensure-ansible:
	@if ! command -v ansible-playbook >/dev/null 2>&1; then
		echo "[make] 安裝 ansible-core（bring-up 沒裝，由 make 補）..."
		sudo apt-get update -y
		sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible-core
	fi
