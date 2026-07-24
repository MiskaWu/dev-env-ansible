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
# TAGS：只裝某些 tag，例 `make apply TAGS=node`
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

.PHONY: help init check apply syntax lint facts _ensure-ansible

help: ## 顯示所有可用命令
	@awk 'BEGIN {FS = ":.*##"; printf "\n使用方式:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ 起手（乾淨機器 → 裝好軟體）
init: apply ## 裝軟體 + 印收尾清單（SSH keys / git 身分已由 bring-up 備好）
	@echo
	echo "軟體裝好了。收尾（手動，刻意不自動化）："
	echo "  1. SSH 公鑰貼到 GitHub / GitLab（bring-up 已生成）："
	echo "       cat ~/.ssh/id_ed25519_*.pub"
	echo "  2. claude    # 首次瀏覽器 OAuth"

##@ 軟體（Ansible）
check: _ensure-ansible ## 乾跑預覽：列出這次會改什麼、不套用（--check --diff）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --check --diff

apply: _ensure-ansible ## 套用：把 host 收斂到期望狀態
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
# bring-up 只給 git+make；ansible 由這裡自己補（不能用 ansible 裝 ansible）。
_ensure-ansible:
	@if ! command -v ansible-playbook >/dev/null 2>&1; then
		echo "[make] 安裝 ansible-core（bring-up 沒裝，由 make 補）..."
		sudo apt-get update -y
		sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible-core
	fi
