# Misskey Deployment Scripts

Automated deployment scripts for Misskey instances, featuring multi-instance management via a unified YAML configuration, robust error handling, health checks, log rotation, and Discord/Misskey notifications.

## Features

-   **Unified YAML Configuration**: Manage all instance settings (repository, branch, filters, notifications, health checks, etc.) in a single `deploy_config.yaml` file.
-   **Environment Variable Overrides**: Override any YAML configuration value using environment variables for flexible deployment scenarios.
-   **Selective Deployment**: Filter deployments based on changed paths in the Git repository (include/exclude specific files or directories).
-   **Automated Health Checks**: Perform post-deployment health checks for each instance and send notifications on success or failure.
-   **Enhanced Error Notifications**: Receive detailed error messages on Discord and Misskey, including the script name, function, and line number where the error occurred.
-   **Built-in Log Rotation**: Automatic log rotation based on file size and number of retained files, configurable globally.
-   **ShellCheck Integration**: CI workflow includes `shellcheck` for static analysis of shell scripts.
-   **Comprehensive Logging**: Per-instance log files with timestamps (e.g., `logs/INSTANCE_NAME/INSTANCE_NAME-deploy.log`).
-   **Dependency Checks**: Verifies required tools (`git`, `docker`, `curl`, `jq`, `yq`, `bc`) during initialization.
-   **Misskey & Discord Notifications**: Real-time deployment status updates.

## Directory Structure

```
misskey-deploy-scripts/
├── .github/
│   └── workflows/
│       └── test_deploy_script.yml  # GitHub Actions CI workflow
├── scripts/
│   ├── configs/
│   │   └── deploy_config.yaml.example # Example YAML configuration
│   ├── lib/
│   │   ├── logging.sh
│   │   └── notifications.sh
│   ├── config.sh                   # Global constants and dependency checks
│   ├── config_parser.sh            # YAML parser and environment override logic
│   ├── deploy_functions.sh         # Core deployment functions
│   └── deploy.sh                   # Main deployment script
├── logs/                           # Log files will be created here (e.g., logs/my_instance/my_instance-deploy.log)
├── README.md
└── LICENSE
```

## Setup Instructions

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/lqvp-hosted/misskey-deploy-scripts.git
    cd misskey-deploy-scripts
    ```

2.  **Install Dependencies**:
    Ensure you have the following command-line tools installed:
    *   `git`
    *   `docker`
    *   `curl`
    *   `jq`
    *   `yq` (version 4.x or compatible, for parsing YAML)
    *   `bc` (for log rotation calculations)
    The script will check for these dependencies upon execution.

3.  **Prepare Configuration File**:
    Copy the example configuration file:
    ```bash
    cp scripts/configs/deploy_config.yaml.example scripts/configs/deploy_config.yaml
    ```

4.  **Edit Configuration File (`scripts/configs/deploy_config.yaml`)**:
    Modify `scripts/configs/deploy_config.yaml` to suit your needs. This file contains global settings and a list of instances to manage.
    Key sections to configure:
    *   `global_settings`:
        *   `discord_webhook_url`: Default Discord webhook URL.
        *   `misskey_notification`: Default Misskey notification settings.
        *   `deploy_filters`: Global path exclusion rules.
        *   `log_rotation`: Settings for log rotation (`enabled`, `max_size_mb`, `max_files`).
    *   `instances`: An array of Misskey instances. Each instance can have:
        *   `name`: A unique name for the instance (used for logging and identification).
        *   `enabled`: `true` or `false` to enable/disable deployment for this instance.
        *   `repo_dir`: Absolute path to the local Misskey repository.
        *   `repo_url`: Git repository URL.
        *   `branch`: Git branch to track.
        *   `discord_webhook_url`: Instance-specific Discord webhook.
        *   `misskey_notification`: Instance-specific Misskey notification settings.
        *   `deploy_filters`: Instance-specific include/exclude path rules.
        *   `health_check`: Settings for post-deployment health checks (`enabled`, `url`, `timeout_seconds`, `retries`, etc.).

    **Note on Migrating from `.conf` files**: If you were using a previous version of these scripts with `.conf` files (e.g., `misskey.conf`, `misskey-temp.conf`), you should migrate your settings from those files into the `scripts/configs/deploy_config.yaml` under the appropriate instance. Once migrated, the old `.conf` files in `scripts/configs/` are no longer needed and can be deleted.

5.  **Make Scripts Executable (if necessary)**:
    Ensure the main deployment script is executable:
    ```bash
    chmod +x scripts/deploy.sh
    ```
    Other scripts sourced by `deploy.sh` do not need to be directly executable.

6.  **Test Deployment**:
    Run the deployment script for a specific instance defined in your `deploy_config.yaml`:
    ```bash
    ./scripts/deploy.sh <instance_name>
    ```
    Replace `<instance_name>` with the `name` you configured for an instance in `deploy_config.yaml` (e.g., `misskey_live`).

## Environment Variable Overrides

You can override any setting from `deploy_config.yaml` using environment variables. The environment variable name is constructed by:
1.  Prefixing with `CONFIG_OVERRIDE_`.
2.  Converting the YAML path to uppercase.
3.  Replacing dots (`.`) and hyphens (`-`) with underscores (`_`).
4.  For array elements, use `_INDEX_<n>` (0-indexed).

Examples:
*   To override `global_settings.discord_webhook_url`:
    ```bash
    export CONFIG_OVERRIDE_GLOBAL_SETTINGS_DISCORD_WEBHOOK_URL="your_new_webhook_url"
    ```
*   To override the `repo_dir` for the first instance (`instances[0].repo_dir`):
    ```bash
    export CONFIG_OVERRIDE_INSTANCES_INDEX_0_REPO_DIR="/another/path/to/repo"
    ```
*   To disable health check for the second instance (`instances[1].health_check.enabled`):
    ```bash
    export CONFIG_OVERRIDE_INSTANCES_INDEX_1_HEALTH_CHECK_ENABLED="false"
    ```

## Cron Job Configuration

To automate deployments, you can set up cron jobs. Edit your crontab using `crontab -e` and add entries like the following:

```bash
# Check 'misskey_live' instance every 5 minutes
*/5 * * * * /path/to/misskey-deploy-scripts/scripts/deploy.sh misskey_live >> /path/to/misskey-deploy-scripts/logs/cron.log 2>&1

# Check 'misskey_dev' instance every 10 minutes
*/10 * * * * /path/to/misskey-deploy-scripts/scripts/deploy.sh misskey_dev >> /path/to/misskey-deploy-scripts/logs/cron.log 2>&1
```
Remember to replace `/path/to/misskey-deploy-scripts/` with the actual absolute path to your script directory and adjust instance names and schedules as needed. It's recommended to pipe cron output to a log file.

## Obsolete Scripts

The following wrapper scripts are now obsolete and can be removed from your repository if they exist:
*   `scripts/deploy_misskey.sh`
*   `scripts/deploy_temp.sh`
Use `scripts/deploy.sh <instance_name>` instead.

## Requirements

-   Bash 4.0+
-   Git 2.20+
-   Docker 20.10+
-   jq 1.6+
-   yq 4.x+ (for YAML parsing)
-   bc (GNU bc for calculations)
-   cURL 7.68+

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
