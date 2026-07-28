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
# TAGS：要裝什麼就寫在這裡，例 `make install TAGS=claude`、`TAGS=go,python`。
# 不設就是全部。有哪些可用跑 `make list`——刻意不在這裡列，手抄一份就會漂移。
TAGS      ?=
LIMIT     ?=
# LOCAL=1：對本機 localhost 跑（在 distro 內用就對了）；控制節點模式設 LOCAL=0
LOCAL     ?= 1
EXTRA     ?=

# ---- 內部組裝 --------------------------------------------------------------
# COMMA：localhost, 裡的逗號會跟 $(if) 的引數分隔逗號相撞，必須用變數繞過。
COMMA  := ,
_CONN  := $(if $(filter 1,$(LOCAL)),-i localhost$(COMMA) -c local,-i $(INVENTORY))
_TAGS  := $(if $(TAGS),--tags $(TAGS),)
_LIMIT := $(if $(LIMIT),--limit $(LIMIT),)
_ARGS  := $(_CONN) $(_TAGS) $(_LIMIT) $(EXTRA)

# 直接跟 playbook 要真實的 tag 清單（單一事實來源）。濾掉 never —— 它是「不明確指定
# 就不跑」的機制標記，不是使用者該挑的項目。pipefail 已開，ansible 失敗不會被後面
# 永遠回 0 的 sed/tr 洗掉（見 CLAUDE.md 那條「別把 exit code 洗掉」）。
_TAGS_OF_PLAYBOOK = ansible-playbook $(PLAYBOOK) $(_CONN) --list-tags \
	| sed -n 's/.*TASK TAGS: \[\(.*\)\]/\1/p' \
	| tr -d ' ' | tr ',' '\n' | grep -vx never | paste -sd' '

.PHONY: help init list check install syntax lint facts _ensure-ansible _check-tags

help: ## 顯示所有可用命令
	@awk 'BEGIN {FS = ":.*##"; printf "\n使用方式:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	echo
	echo "要裝什麼用 TAGS=，例 make install TAGS=claude 或 TAGS=go,python。"
	echo "不確定有什麼可裝？先跑 make list —— 它會列出每一項，並標出這台機器已經有哪些。"

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

# bring-up 只給 git+make；ansible 由這裡自己補（不能用 ansible 裝 ansible）。
# 是所有 ansible target 的前置，所以就算沒先跑 make init 也不會卡住 —— init 的價值
# 在於「明確的起手入口 + 印出下一步」，不是獨佔這件事。
_ensure-ansible:
	@if ! command -v ansible-playbook >/dev/null 2>&1; then
		echo "[make] 安裝 ansible-core（bring-up 沒裝，由 make 補）..."
		sudo apt-get update -y
		sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible-core
	fi
