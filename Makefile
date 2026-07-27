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
# TAGS：只裝某些 tag，例 `make apply TAGS=python`。有哪些可用跑 `make list`
# ——刻意不在這裡列出來：手抄一份就會跟 tasks/main.yml 漂移（`clients` 那個 tag 隨
# clients.yml 移除後就在這裡多留了一陣子）。打錯字由 _check-tags 擋，見下。
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

.PHONY: help init list check apply syntax lint facts _ensure-ansible _check-tags

help: ## 顯示所有可用命令
	@awk 'BEGIN {FS = ":.*##"; printf "\n使用方式:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	echo
	echo "不確定有什麼可裝？先跑 make list —— 它會照目前的變數算出每一項裝或不裝。"

##@ 起手（乾淨機器 → 裝好軟體）
init: apply ## 裝軟體 + 印收尾清單（SSH keys / git 身分已由 bring-up 備好）
	@echo
	echo "軟體裝好了。收尾（手動，刻意不自動化）："
	echo "  1. SSH 公鑰貼到 GitHub / GitLab（bring-up 已生成）："
	echo "       cat ~/.ssh/id_ed25519_*.pub"
	echo "  2. claude    # 首次瀏覽器 OAuth"

##@ 軟體（Ansible）
# 兩個「先看再動」的指令，回答的是不同問題，都留著：
#   list  —— 有哪些東西可裝、開關現在是什麼值（不連線做事，純唯讀）
#   check —— 這次 apply 會改哪些檔（真的去 host 上比對）
# result_format=yaml 是為了讓 debug 的多行字串好好斷行；注意**不能**改成
# stdout_callback = yaml，那個舊 callback 在 ansible-core 2.20 已移除（見 CLAUDE.md）。
list: _ensure-ansible ## 有哪些可裝的項目、目前開關值、可用的 tag（唯讀）
	@ANSIBLE_CALLBACK_RESULT_FORMAT=yaml \
		ansible-playbook $(PLAYBOOK) $(_CONN) $(_LIMIT) $(EXTRA) --tags list
	echo "可用的 tag（直接跟 playbook 要的，不是手抄）："
	echo "    $$($(_TAGS_OF_PLAYBOOK))"
	echo

check: _ensure-ansible _check-tags ## 乾跑預覽：列出這次會改什麼、不套用（--check --diff）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --check --diff

apply: _ensure-ansible _check-tags ## 套用：把 host 收斂到期望狀態
	ansible-playbook $(PLAYBOOK) $(_ARGS)

##@ 檢查
syntax: _ensure-ansible ## 語法檢查（不連線）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --syntax-check

lint: ## ansible-lint（需先裝 ansible-lint）
	@command -v ansible-lint >/dev/null 2>&1 || { echo "Error: ansible-lint 未安裝"; exit 1; }
	ansible-lint

facts: _ensure-ansible ## 印出偵測到的環境（is_wsl / arch / uid）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --tags always

# ---- 內部 ------------------------------------------------------------------
# ansible 對不存在的 tag **不報錯**，只是什麼都不做 —— `make apply TAGS=pythn` 會
# 一路綠燈跑完卻一個套件都沒裝，是最難發現的那種失敗。這裡在動作之前先比對一次真實
# 的 tag 清單，把它變成大聲的錯誤。TAGS 沒設就直接跳過（不多花一次 ansible 啟動）。
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
		echo "（跑 make list 看每個 tag 各裝什麼）" >&2
		exit 1
	fi

# bring-up 只給 git+make；ansible 由這裡自己補（不能用 ansible 裝 ansible）。
_ensure-ansible:
	@if ! command -v ansible-playbook >/dev/null 2>&1; then
		echo "[make] 安裝 ansible-core（bring-up 沒裝，由 make 補）..."
		sudo apt-get update -y
		sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible-core
	fi
