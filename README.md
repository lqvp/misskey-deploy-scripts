# Misskey Deployment Scripts

This repository contains automated deployment scripts for Misskey instances with multi-repository support and Discord notifications.

## Features

- **Automatic Git Synchronization**: Checks and pulls updates from specified branches
- **Discord Integration**: Real-time deployment notifications with rich embeds
- **Centralized Configuration**: Manage multiple instances via config files
- **Comprehensive Logging**: Per-instance log files with timestamps
- **Dependency Checks**: Verifies required tools during initialization
- **Retry Mechanism**: Robust error handling with notification retries

## Directory Structure

```
misskey-deploy-scripts/
├── scripts/
│   ├── configs/
│   │   ├── misskey.conf
│   │   └── misskey-temp.conf
│   ├── config.sh
│   ├── deploy_functions.sh
│   ├── deploy.sh
│   ├── deploy_misskey.sh
│   └── deploy_temp.sh
├── logs/
│   ├── misskey/
│   └── misskey-temp/
├── README.md
└── LICENSE
```

## Setup Instructions

1. Clone the repository:
   ```bash
   git clone https://github.com/lqvp-hosted/misskey-deploy-scripts.git
   cd misskey-deploy-scripts
   ```

2. Prepare configuration files:
   ```bash
   cp scripts/configs/misskey.conf.example scripts/configs/misskey.conf
   cp scripts/configs/misskey-temp.conf.example scripts/configs/misskey-temp.conf
   ```

3. Edit configuration files:
   - Modify values in `scripts/configs/*.conf`:
     ```bash
     REPO_DIR="/path/to/your/misskey-instance"
     DISCORD_WEBHOOK_URL="your_discord_webhook_url"
     REPO_URL="https://github.com/your-repository"
     BRANCH="your-branch"
     ```

4. Make scripts executable:
   ```bash
   chmod +x scripts/*.sh
   ```

5. Test deployment:
   ```bash
   # Deploy main instance
   ./scripts/deploy_misskey.sh

   # Deploy temp instance
   ./scripts/deploy_temp.sh
   ```

## Adding New Instances

1. Create configuration file:
   ```bash
   cp scripts/configs/template.conf.example scripts/configs/new-instance.conf
   ```

2. Edit the new configuration file

3. Create deployment wrapper:
   ```bash
   echo '#!/bin/bash
   cd "$(dirname "$0")/.."
   bash scripts/deploy.sh new-instance' > scripts/deploy_new-instance.sh
   chmod +x scripts/deploy_new-instance.sh
   ```

## Cron Job Configuration

Add to crontab (`crontab -e`):
```bash
# Check main instance every 5 minutes
*/5 * * * * /bin/bash /path/to/misskey-deploy-scripts/scripts/deploy_misskey.sh

# Check temp instance every minute
* * * * * /bin/bash /path/to/misskey-deploy-scripts/scripts/deploy_temp.sh
```

## Requirements

- Bash 4.0+
- Git 2.20+
- Docker 20.10+
- jq 1.6+
- cURL 7.68+

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
