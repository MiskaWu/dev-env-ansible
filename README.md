# dev-env-ansible

把一台 Linux 裝成完整開發環境的 Ansible role：baseline 套件、Podman（rootless）、Go、
Claude Code，以及可選的 toolchain（Node、uv、DB/cache clients、SSH keys）。

**Host-agnostic** —— WSL2 專屬的 task 用 `is_wsl` fact gate 起來，所以同一個 role 也能跑在
純 Ubuntu VM、homelab 節點或 WSL distro。搭配 [`wsl-bootstrap`](../wsl-bootstrap)：它產出一台
已開 systemd、可連的 WSL distro，讓你在上面接手裝軟體。

## 檔案結構

```
dev-env-ansible/
├── ansible.cfg
├── site.yml                    # 頂層 playbook
├── inventory/hosts.yml         # 管理的 host
└── roles/dev_env/
    ├── defaults/main.yml       # 可調項（toolchain 開關、go 版本、ssh scopes）
    └── tasks/
        ├── detect.yml          # 設定 is_wsl / go_arch / login_uid fact
        ├── base.yml            # baseline apt 套件
        ├── podman.yml          # podman + registries.conf；WSL 部分用 is_wsl gate
        ├── go.yml              # Go binary（冪等：目標版本已在就跳過）
        ├── claude.yml          # Claude Code（native installer）
        ├── node.yml            # nvm + Node        (when: install_node)
        ├── python.yml          # uv               (when: install_python)
        ├── clients.yml         # psql, redis-cli, nats (when: install_clients)
        └── ssh_keys.yml        # 每個 scope 一把 ed25519 (when: generate_ssh_keys)
```

## 用法

在機器上用 `make`（baseline 已有 ansible）：

```bash
make check           # 乾跑預覽（--check --diff）：列出會改什麼，不套用
make apply           # 套用
make apply TAGS=node # 只裝某項（例如把 install_node 改成 true 後）
```

`make check` 是乾跑預覽（就是那個「diff」）；`make apply TAGS=<tag>` 只裝一部分；重跑會收斂
（冪等）—— 這就是「加新東西不砍重建」的流程。`LOCAL=1` 對 localhost 跑。底層等同
`ansible-playbook site.yml --check --diff` 等。

### 在 WSL 上：第一次 apply 後跑 `wsl --shutdown`

在 WSL distro 上 `make apply` 之後，到 Windows 端跑一次 **`wsl --shutdown`**（不是
`--terminate`）再重進。rootless `podman.socket` 已 enable，但 WSL 的 systemd 有 executor
冷啟動 race（`Failed to spawn executor: Device or resource busy`）；只有 full VM shutdown
清得掉，之後 socket 會自動起、`docker-compose` 就能用。這不是安裝失敗，是平台 race。

### 本機測試（無 control node）

```bash
ansible-playbook -i 'localhost,' -c local site.yml -e ssh_key_tag=dev --check
```

## 設定

在 `inventory/hosts.yml`、`group_vars/` 或 `host_vars/` 覆蓋預設：

| 變數 | 預設 | 控制 |
|---|---|---|
| `container_runtime` | `podman` | runtime（只實作 `podman` 路徑） |
| `compose_shim` | `true` | `docker-compose` 二進位 + `DOCKER_HOST` |
| `go_version` | `latest` | `latest` 查 go.dev，或 pin 如 `1.26.5` |
| `install_node` / `node_version` | `false` / `lts` | nvm + Node |
| `install_python` | `true` | uv |
| `install_clients` | `true` | `psql`、`redis-cli`、`nats` |
| `generate_ssh_keys` | `true` | 每個 scope 一把 `id_ed25519_<ssh_key_tag>_<scope>` |
| `ssh_key_scopes` | `[github, gitlab]` | 要產哪些 key |
| `ssh_key_comment` | `miskawu@baasgames-dev` | key 註解；task 會接上 `-<scope>` 與建置日期 |
