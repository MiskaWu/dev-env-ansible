SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
.NOTPARALLEL:

# ---- 可由外部覆蓋 ----------------------------------------------------------
INVENTORY ?= inventory/hosts.yml
PLAYBOOK  ?= site.yml
TAGS      ?=            # 例：TAGS=node make apply → 只裝 node
LIMIT     ?=            # 例：LIMIT=dev
LOCAL     ?= 0          # LOCAL=1 → 在本機對 localhost 跑（不走 control node SSH）
EXTRA     ?=            # 額外 ansible 參數，例：EXTRA='-e ssh_key_tag=dev'

# ---- 內部組裝 --------------------------------------------------------------
# COMMA：localhost, 裡的逗號會跟 $(if) 的引數分隔逗號相撞，必須用變數繞過。
COMMA  := ,
_CONN  := $(if $(filter 1,$(LOCAL)),-i localhost$(COMMA) -c local,-i $(INVENTORY))
_TAGS  := $(if $(TAGS),--tags $(TAGS),)
_LIMIT := $(if $(LIMIT),--limit $(LIMIT),)
_ARGS  := $(_CONN) $(_TAGS) $(_LIMIT) $(EXTRA)

.PHONY: help check apply syntax lint facts

help: ## 顯示所有可用命令
	@awk 'BEGIN {FS = ":.*##"; printf "\n使用方式:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ 操作
check: ## 乾跑預覽：列出這次會改什麼、不套用（--check --diff）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --check --diff

apply: ## 套用：把 host 收斂到期望狀態
	ansible-playbook $(PLAYBOOK) $(_ARGS)

##@ 檢查
syntax: ## 語法檢查（不連線）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --syntax-check

lint: ## ansible-lint（需先裝 ansible-lint）
	@command -v ansible-lint >/dev/null 2>&1 || { echo "Error: ansible-lint 未安裝"; exit 1; }
	ansible-lint

facts: ## 印出偵測到的環境（is_wsl / arch / uid）
	ansible-playbook $(PLAYBOOK) $(_ARGS) --tags always
