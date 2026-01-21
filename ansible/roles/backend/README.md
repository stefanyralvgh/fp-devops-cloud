# Backend Role

Deploys Node.js Movie Analyst API with PM2 process manager.

## Requirements

- Amazon Linux 2
- Internet connectivity (for npm packages)
- MySQL/RDS database
- Git installed

## Variables

See `defaults/main.yml` for all configurable variables.

**Required variables (set in inventory):**
- `db_endpoint`: RDS endpoint
- `vault_db_password`: Database password (encrypted with Ansible Vault)
- `environment`: qa or prod

## Database

Application uses MySQL with these environment variables:
- `DB_HOST`: Database hostname
- `DB_PORT`: Database port (default: 3306)
- `DB_NAME`: Database name (default: movie_db)
- `DB_USER`: Database user
- `DB_PASS`: Database password

## Tasks

- `nodejs.yml`: Install Node.js 18 LTS
- `pm2.yml`: Install and configure PM2
- `application.yml`: Clone repo, install dependencies, run seeds
- `service.yml`: Start/manage PM2 service

## Tags

- `nodejs`: Node.js installation only
- `pm2`: PM2 setup only
- `application`: Application deployment only
- `service`: Service management only
- `seeds`: Database seeding only

## Endpoints

- `GET /` - Health check
- `GET /movies` - List all movies
- `GET /reviewers` - List all reviewers
- `GET /publications` - List all publications
- `GET /pending` - Movies released >= 2017