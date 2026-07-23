# dev-env-ansible

Ansible role that provisions a complete Linux development environment: baseline
packages, Podman (rootless), Go, Claude Code, and an opt-in toolchain (Node, uv,
DB/cache clients, SSH keys).

Host-agnostic — the WSL2-specific tasks are gated on an `is_wsl` fact, so the same
role runs on a plain Ubuntu VM, a homelab node, or a WSL distro. Pairs with
[`wsl-bootstrap`](../wsl-bootstrap), which produces an SSH-reachable, systemd-enabled
WSL distro for the control node to manage.

## Layout

```
dev-env-ansible/
├── ansible.cfg
├── site.yml                    # top playbook
├── inventory/hosts.yml         # managed hosts
└── roles/dev-env/
    ├── defaults/main.yml       # tunables (toolchain toggles, go version, ssh scopes)
    └── tasks/
        ├── detect.yml          # sets is_wsl / go_arch / login_uid facts
        ├── base.yml            # baseline apt packages
        ├── podman.yml          # podman + registries.conf; WSL bits gated on is_wsl
        ├── go.yml              # Go binary (idempotent: skips if target version present)
        ├── claude.yml          # Claude Code (native installer)
        ├── node.yml            # nvm + Node        (when: install_node)
        ├── python.yml          # uv               (when: install_python)
        ├── clients.yml         # psql, redis-cli, nats (when: install_clients)
        └── ssh_keys.yml        # one ed25519 per scope (when: generate_ssh_keys)
```

## Usage

From the control node:

```bash
# preview what would change (the "diff") — nothing is applied
ansible-playbook site.yml --check --diff

# apply
ansible-playbook site.yml

# install just one thing (e.g. Node) after flipping install_node=true
ansible-playbook site.yml --tags node
```

`--check` is the dry-run preview; `--tags` installs a subset; re-running converges
(idempotent) — that's the "add new things without tearing down" workflow.

### Local test (no control node)

```bash
ansible-playbook -i 'localhost,' -c local site.yml -e ssh_key_tag=dev --check
```

## Config

Override defaults in `inventory/hosts.yml`, `group_vars/`, or `host_vars/`:

| Var | Default | Controls |
|---|---|---|
| `container_runtime` | `podman` | runtime (only `podman` path implemented) |
| `compose_shim` | `true` | `docker-compose` binary + `DOCKER_HOST` |
| `go_version` | `latest` | `latest` from go.dev, or pin e.g. `1.26.5` |
| `install_node` / `node_version` | `false` / `lts` | nvm + Node |
| `install_python` | `true` | uv |
| `install_clients` | `true` | `psql`, `redis-cli`, `nats` |
| `generate_ssh_keys` | `true` | one `id_ed25519_<ssh_key_tag>_<scope>` per scope |
| `ssh_key_scopes` | `[github, gitlab]` | which keys to generate |
| `ssh_key_comment` | `miskawu@baasgames-dev` | key comment; task appends `-<scope>` + build date |
