SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
.NOTPARALLEL:

# ---- 可由外部覆蓋 ----------------------------------------------------------
# 注意：這些 ?= 後面不要接行內 `# 註解` —— make 會把值到 # 之間的空白算進變數值
# （SSH_TAG 會變 "dev   "、LOCAL 會變 "1   "，$(filter 1,…) 就對不上），故註解另起一行。
INVENTORY ?= inventory/hosts.yml
PLAYBOOK  ?= site.yml
# TAGS：只裝某些 tag，例 `make apply TAGS=node`
TAGS      ?=
LIMIT     ?=
# LOCAL=1：對本機 localhost 跑（在 distro 內用就對了）；控制節點模式設 LOCAL=0
LOCAL     ?= 1
EXTRA     ?=
# SSH_TAG：SSH key 檔名前綴，對齊 role 的 ssh_key_tag
SSH_TAG   ?= dev
# GIT_NAME / GIT_EMAIL：make git-config 用
GIT_NAME  ?=
GIT_EMAIL ?=

# ---- 內部組裝 --------------------------------------------------------------
# COMMA：localhost, 裡的逗號會跟 $(if) 的引數分隔逗號相撞，必須用變數繞過。
COMMA  := ,
_CONN  := $(if $(filter 1,$(LOCAL)),-i localhost$(COMMA) -c local,-i $(INVENTORY))
_TAGS  := $(if $(TAGS),--tags $(TAGS),)
_LIMIT := $(if $(LIMIT),--limit $(LIMIT),)
_ARGS  := $(_CONN) $(_TAGS) $(_LIMIT) $(EXTRA)

.PHONY: help init check apply syntax lint facts ssh-keys git-config _ensure-ansible

help: ## 顯示所有可用命令
	@awk 'BEGIN {FS = ":.*##"; printf "\n使用方式:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ 起手（乾淨機器 → 一路裝好）
init: apply ssh-keys ## 一鍵：裝軟體 + 印公鑰 + 印收尾清單
	@echo
	echo "收尾（這幾步是你手動，刻意不自動化）："
	echo "  1. 上面的公鑰貼到 GitHub / GitLab"
	echo "  2. make git-config GIT_NAME=\"你的名字\" GIT_EMAIL=\"你的信箱\""
	echo "  3. claude    # 首次瀏覽器 OAuth"

git-config: ## 設定 git 身分（GIT_NAME=... GIT_EMAIL=...）
	@if [ -z "$(GIT_NAME)" ] || [ -z "$(GIT_EMAIL)" ]; then
		echo "用法：make git-config GIT_NAME=\"你的名字\" GIT_EMAIL=\"你的信箱\""
		exit 1
	fi
	git config --global user.name  "$(GIT_NAME)"
	git config --global user.email "$(GIT_EMAIL)"
	echo "git 身分：$$(git config --global user.name) <$$(git config --global user.email)>"

ssh-keys: ## 印出 SSH 公鑰（貼到 GitHub/GitLab；key 由 apply 產生）
	@shopt -s nullglob
	keys=($$HOME/.ssh/id_ed25519_$(SSH_TAG)_*.pub)
	if [ $${#keys[@]} -eq 0 ]; then echo "（還沒有 key —— 先 make apply）"; exit 0; fi
	for f in "$${keys[@]}"; do echo "--- $$(basename "$$f") ---"; cat "$$f"; done

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
