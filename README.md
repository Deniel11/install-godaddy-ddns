# GoDaddy DDNS for OPNsense

A lightweight Dynamic DNS client for **OPNsense / FreeBSD** that keeps a GoDaddy DNS `A` record synchronized with the current public IPv4 address.

## Features

- Detects the current public IPv4 address using `api.ipify.org`
- Reads the existing GoDaddy `A` record
- Updates DNS only when the public IP changes
- Interactive configuration with existing values offered as defaults
- Default values:
  - `DOMAIN`: `your.domain`
  - `HOST`: `vpn`
  - `TTL`: `600`
- Stores the GoDaddy Personal Access Token outside the Git repository
- Can update itself directly from this GitHub repository
- Preserves the local configuration during script updates
- Logs activity to `/var/log/godaddy-ddns.log`
- Includes a read-only `--check` mode

## Repository

https://github.com/Deniel11/install-godaddy-ddns

Repository layout:

```text
.
├── README.md
├── install.sh
└── godaddy-ddns.sh
```

## Requirements

The target system must provide:

- OPNsense / FreeBSD
- `curl`
- `jq`

The script is intended to run as `root`.

## Installation

Run the following commands from the OPNsense shell:

```sh
curl -fsSL -o /tmp/godaddy-ddns-install.sh \
  https://raw.githubusercontent.com/Deniel11/install-godaddy-ddns/main/install.sh

chmod 700 /tmp/godaddy-ddns-install.sh
/tmp/godaddy-ddns-install.sh
```

The installer:

1. Downloads the latest `godaddy-ddns.sh`
2. Installs it as `/usr/local/sbin/godaddy-ddns.sh`
3. Creates a backup of an existing installation
4. Starts configuration on first installation
5. Preserves an existing configuration during upgrades

## Configuration

Run:

```sh
/usr/local/sbin/godaddy-ddns.sh --configure
```

The script asks for:

```text
Domain [your.domain]:
Host [vpn]:
TTL [600]:
GoDaddy Personal Access Token:
```

When a configuration already exists, the current values are offered as defaults. Press `Enter` to keep the existing value.

The configuration is stored locally in:

```text
/etc/godaddy-ddns.conf
```

The file is created with permissions `600`.

Example:

```text
DOMAIN='example.com'
HOST='vpn'
TTL='600'
GODADDY_PAT='YOUR_PERSONAL_ACCESS_TOKEN'
```

**Do not commit this file to GitHub.**

## GoDaddy Personal Access Token

Create a GoDaddy Personal Access Token with the DNS permissions required for the domain.

The script sends the token using the GoDaddy API authentication format:

```text
Authorization: sso-key <API_KEY>:<API_SECRET>
```

If your GoDaddy account provides a Personal Access Token as a single credential, use the credential format required by the current GoDaddy API documentation.

## Usage

### Update DNS

```sh
/usr/local/sbin/godaddy-ddns.sh
```

The script:

1. Gets the current public IPv4 address.
2. Reads the current GoDaddy `A` record.
3. Compares the addresses.
4. Exits without changing DNS when they match.
5. Updates the record when they differ.

### Check status without changing DNS

```sh
/usr/local/sbin/godaddy-ddns.sh --check
```

`--check` does not modify DNS.

### Reconfigure

```sh
/usr/local/sbin/godaddy-ddns.sh --configure
```

### Update the installed script

```sh
/usr/local/sbin/godaddy-ddns.sh --update
```

The update downloads:

```text
https://raw.githubusercontent.com/Deniel11/install-godaddy-ddns/main/godaddy-ddns.sh
```

The local configuration at `/etc/godaddy-ddns.conf` is not modified.

The previous installed script is backed up as:

```text
/usr/local/sbin/godaddy-ddns.sh.bak
```

### Show version

```sh
/usr/local/sbin/godaddy-ddns.sh --version
```

### Show help

```sh
/usr/local/sbin/godaddy-ddns.sh --help
```

## Automatic execution

Run the script periodically using the OPNsense cron facility.

For example, every 5 minutes:

```text
*/5 * * * * /usr/local/sbin/godaddy-ddns.sh
```

Running the script frequently is safe because it only performs a DNS update when the public IP has changed.

## Logging

Log file:

```text
/var/log/godaddy-ddns.log
```

## File permissions

Installed script:

```text
700
```

Configuration file:

```text
600
```

The configuration file contains the GoDaddy credential and must therefore remain readable only by the appropriate system account.

## Security

Never:

- commit `/etc/godaddy-ddns.conf`
- put credentials in `README.md`
- hard-code credentials in `godaddy-ddns.sh`
- publish credentials in GitHub issues, pull requests, or discussions

The GitHub repository contains only the application code. Credentials remain local to the OPNsense system.

## License

MIT
