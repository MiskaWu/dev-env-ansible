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
# TAGS：`make check` / `make syntax` 用得到（例 `make check TAGS=python`）。
# 裝東西不必碰它 —— 用 `make install-python`，pattern rule 會自己把 TAGS 設好。
TAGS      ?=
LIMIT     ?=
# LOCAL=1：對本機 localhost 跑（在 distro 內用就對了）；控制節點模式設 LOCAL=0
LOCAL     ?= 1
EXTRA     ?=

# ---- 內部組裝 --------------------------------------------------------------
# COMMA：localhost, 裡的逗號會跟 $(if) 的引數分隔逗號相撞，必須用變數繞過。
COMMA  := ,
_CONN  := $(if $(filter 1,$(LOCAL)),-i localhost$(COMMA) -c local,-i $(INVENTORY))
# _TAGS / _ARGS 必須是 `=`（遞迴展開）而**不是** `:=`。install-% 用 target-specific
# variable 把 $* 餵進 TAGS，而 `:=` 會在 parse 時就把當時還是空的 TAGS 定死，
# 於是 `make install-python` 會變成「不帶 --tags 全裝」—— 靜默且危險。實測確認過。
_TAGS  = $(if $(TAGS),--tags $(TAGS),)
_LIMIT = $(if $(LIMIT),--limit $(LIMIT),)
_ARGS  = $(_CONN) $(_TAGS) $(_LIMIT) $(EXTRA)

# 直接跟 playbook 要真實的 tag 清單（單一事實來源）。濾掉 never —— 它是「不明確指定
# 就不跑」的機制標記，不是使用者該挑的項目。pipefail 已開，ansible 失敗不會被後面
# 永遠回 0 的 sed/tr 洗掉（見 CLAUDE.md 那條「別把 exit code 洗掉」）。
_TAGS_OF_PLAYBOOK = ansible-playbook $(PLAYBOOK) $(_CONN) --list-tags \
	| sed -n 's/.*TASK TAGS: \[\(.*\)\]/\1/p' \
	| tr -d ' ' | tr ',' '\n' | grep -vx never | paste -sd' '

# ansible 對不存在的 tag **不報錯**，只是什麼都不做 —— `make install-pythn` 會一路
# 綠燈跑完卻一個套件都沒裝，是最難發現的那種失敗。這段在動作之前先比對一次真實的
# tag 清單，把它變成大聲的錯誤。**別拿掉。**
#
# 為什麼是 define 而不是一個當前置條件的 target：pattern rule 的 target-specific
# 變數**傳不到前置條件**（實測 _check-tags 收到的 TAGS 是空的），而且 make 會把 phony
# 前置條件視為「已經做過」，`make install-go install-python` 只會檢查第一個。寫在
# recipe 裡兩個問題都沒有 —— 實測每個目標各驗一次，打錯字 exit 2。
define _assert_tags
known="$$($(_TAGS_OF_PLAYBOOK))"
bad=""
for t in $$(echo '$(1)' | tr ',' ' '); do
	case " $$known " in
		*" $$t "*) ;;
		*) bad="$$bad $$t" ;;
	esac
done
if [ -n "$$bad" ]; then
	echo "Error: playbook 裡沒有這些 tag：$$bad" >&2
	echo "可用：$$known" >&2
	echo "（跑 make list 看每個項目怎麼叫）" >&2
	exit 1
fi
endef

.PHONY: help init list check install install-all syntax lint facts \
	_ensure-ansible _check-tags

help: ## 顯示所有可用命令
	@awk 'BEGIN {FS = ":.*##"; printf "\n使用方式:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_%-]+:.*?## / { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
	echo
	echo "不確定有什麼可裝？先跑 make list —— 它會列出每一項，並標出這台機器已經有哪些。"

##@ 起手（乾淨機器 → 裝好 Claude）
init: install ## 裝 core + 印收尾清單（SSH keys / git 身分已由 bring-up 備好）
	@echo
	echo "Claude 環境好了。其他工具用到時再裝，跑 make list 看有哪些。"
	echo "收尾（手動，刻意不自動化）："
	echo "  1. SSH 公鑰貼到 GitHub / GitLab（bring-up 已生成）："
	echo "       cat ~/.ssh/id_ed25519_*.pub"
	echo "  2. claude    # 首次瀏覽器 OAuth"

##@ 安裝（Ansible）
# 這個 repo 的定位是「協助把 Claude 開發環境準備起來」，其他工具都是選用的 ——
# 所以 `make install` 只裝 core，其餘一律自己點名。沒有布林開關，tag 就是選擇本身。
install: _ensure-ansible ## 只裝 core：Claude Code + 它的相依 + ~/.profile
	ansible-playbook $(PLAYBOOK) $(_CONN) $(_LIMIT) $(EXTRA) --tags core

install-all: _ensure-ansible ## 暴力全裝：core + 所有選裝項目
	ansible-playbook $(PLAYBOOK) $(_CONN) $(_LIMIT) $(EXTRA)

# 單項安裝。相依由 playbook 的 tag 表達，這裡不必知道 —— `make install-python` 會
# 自動把 build-essential 帶進來，任何影響 PATH 的項目也會順便更新 ~/.profile。
#
# 為什麼是 `install-python` 而不是 `make install python`：後者在 make 的模型裡是
# 「依序 build 兩個 target」，要撐起來得加一條 catch-all 規則 `%:;@:` 把假 target 吃掉，
# 而那條規則會讓 `make pythn` 靜默成功什麼都不做 —— 正是 _assert_tags 要擋的病。
# pattern rule 是純標準 make，零 hack，打錯字照樣大聲失敗。
install-%: TAGS = $*
install-%: _ensure-ansible ## 裝單一項目及其相依（make install-go / install-python / install-lazygit）
	@$(call _assert_tags,$*)
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

check: _ensure-ansible _check-tags ## 乾跑預覽全部：列出會改什麼、不套用（--check --diff）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --check --diff

check-%: TAGS = $*
check-%: _ensure-ansible ## 乾跑預覽單一項目（make check-podman）
	@$(call _assert_tags,$*)
	ansible-playbook $(PLAYBOOK) $(_ARGS) --check --diff

facts: _ensure-ansible ## 印出偵測到的環境（is_wsl / arch / uid）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --tags always

##@ 檢查
syntax: _ensure-ansible ## 語法檢查（不連線）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --syntax-check

lint: ## ansible-lint（需先裝 ansible-lint）
	@command -v ansible-lint >/dev/null 2>&1 || { echo "Error: ansible-lint 未安裝"; exit 1; }
	ansible-lint

# ---- 內部 ------------------------------------------------------------------
# 給 check / syntax 這種吃 TAGS= 變數的 target 用（install-% / check-% 走 recipe 內的
# $(call _assert_tags,…)，理由見上面 define 的註解）。TAGS 沒設就跳過，不多花一次
# ansible 啟動。
_check-tags: _ensure-ansible
	@[ -n "$(TAGS)" ] || exit 0
	$(call _assert_tags,$(TAGS))

# bring-up 只給 git+make；ansible 由這裡自己補（不能用 ansible 裝 ansible）。
_ensure-ansible:
	@if ! command -v ansible-playbook >/dev/null 2>&1; then
		echo "[make] 安裝 ansible-core（bring-up 沒裝，由 make 補）..."
		sudo apt-get update -y
		sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible-core
	fi
