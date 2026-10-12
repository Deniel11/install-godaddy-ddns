# GoDaddy Dynamic DNS

A POSIX shell Dynamic DNS client for GoDaddy-managed DNS zones. It supports multiple zones and multiple A records in one configuration, updates the zone apex (`@`), and automatically creates missing A records.

## Requirements

- FreeBSD, OPNsense, or another POSIX `sh` environment
- `curl`, `jq`, and `grep`
- A GoDaddy Personal Access Token (PAT) with permission to read and modify DNS records
- DNS zones hosted authoritatively by GoDaddy

## Installation

Run as root:

```sh
curl -fsSL https://raw.githubusercontent.com/Deniel11/install-godaddy-ddns/main/install.sh -o /tmp/godaddy-ddns-install.sh
sh /tmp/godaddy-ddns-install.sh
```

The installer validates shell syntax before installation and backs up the previous script. On first installation, it starts the interactive configuration wizard. An existing `/etc/godaddy-ddns.conf` file is preserved.

## Configuration

```sh
/usr/local/sbin/godaddy-ddns.sh --configure
```

The wizard can preserve the existing record list, replace it, or add records. The PAT is entered without displaying its characters in the terminal.

| Zone | Record name | Fully qualified name |
| --- | --- | --- |
| `danielczank.eu` | `vpn` | `vpn.danielczank.eu` |
| `danielczank.eu` | `@` | `danielczank.eu` |
| `danielczank.eu` | `web-games-collection` | `web-games-collection.danielczank.eu` |
| `jackthedog.eu` | `@` | `jackthedog.eu` |

Record names are relative to their DNS zone. Use `@` for the zone apex rather than entering the full domain name. Multiple records across multiple zones can be configured. The PAT must have access to every configured zone.

The configuration file is `/etc/godaddy-ddns.conf` with permissions set to `600`. Records are stored in `RECORDS` as `zone|record-name` pairs separated by semicolons.

## Usage

```sh
/usr/local/sbin/godaddy-ddns.sh --check
/usr/local/sbin/godaddy-ddns.sh --run
/usr/local/sbin/godaddy-ddns.sh --configure
/usr/local/sbin/godaddy-ddns.sh --version
/usr/local/sbin/godaddy-ddns.sh --help
```

- `--check`: retrieves configured DNS records without changing them.
- `--run`: retrieves the public IPv4 address, updates A records that differ, and creates missing A records.
- `--configure`: starts the interactive configuration wizard.
- `--install-action`: installs the OPNsense configd action.
- `--uninstall-action`: removes the configd action.
- `--update`: downloads the script from the GitHub `main` branch, validates its syntax, backs up the installed script, and installs the update.

The `--run` mode leaves records unchanged when they already point to the current public IPv4 address. If multiple A records exist for a configured name, each is checked and any differing records are updated. A CNAME is not automatically converted to an A record; GoDaddy may reject creating an A record for a name that conflicts with a CNAME, and the API error is logged.

## Cron

For example, to run every five minutes, add this to root's crontab:

```cron
*/5 * * * * /usr/local/sbin/godaddy-ddns.sh --run
```

## Logging and security

The default log file is `/var/log/godaddy-ddns.log`. The configuration file is assigned permission `600`, and the installed script is assigned permission `700`. Do not commit the PAT to version control or share it in logs or bug reports.

The script uses GoDaddy's v3 DNS API. It creates missing records with POST and updates existing records with PUT using their `recordId`. The supported TTL range is 600–86400 seconds.

## Local validation

After copying the revised files into the local repository, run:

```sh
sh -n godaddy-ddns.sh
sh -n install.sh
./godaddy-ddns.sh --version
./godaddy-ddns.sh --help
```

Run `--check` first and review its output before using `--run`, which can make real changes to DNS records in GoDaddy.
