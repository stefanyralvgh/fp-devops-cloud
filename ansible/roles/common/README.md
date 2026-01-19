# Common Role

Baseline system configuration for all Movie Analyst instances.

## Purpose

Prepares instances with:
- Latest security patches
- Essential development tools
- Correct timezone and time synchronization
- Basic security hardening
- Custom login banner

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `common_timezone` | `America/Bogota` | System timezone |
| `common_ntp_service` | `chronyd` | NTP service name |
| `common_base_packages` | See defaults/main.yml | Base packages to install |

## Usage
```yaml
- hosts: backend
  become: yes
  roles:
    - common
```

## Tags

- `packages`: Package installation tasks
- `system`: System configuration tasks
- `security`: Security hardening tasks

## Dependencies

None

## Author

DevOps Final Project - 2026