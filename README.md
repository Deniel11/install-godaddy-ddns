# GoDaddy DDNS for OPNsense

Egyszerű GoDaddy Dynamic DNS kliens OPNsense / FreeBSD rendszerhez.

A script:
- lekéri a publikus IPv4 címet az `api.ipify.org` szolgáltatásból,
- lekéri a GoDaddy DNS A rekordot,
- csak IP-változás esetén frissít,
- naplóz `/var/log/godaddy-ddns.log` fájlba,
- a konfigurációt külön fájlban tárolja,
- a GitHub-ról érkező scriptfrissítés nem írja felül a konfigurációt vagy a GoDaddy PAT-ot,
- interaktívan felajánlja a meglévő konfiguráció módosítását.

## Könyvtárstruktúra

```text
.
├── README.md
├── install.sh
└── godaddy-ddns.sh
```

## 1. GitHub repo beállítása

Tedd a három fájlt egy GitHub repositoryba.

Példa:

```text
https://github.com/SAJAT-FELHASZNALO/godaddy-ddns-opnsense
```

Az `install.sh` elején állítsd be a repository URL-jét:

```sh
REPO_RAW="https://raw.githubusercontent.com/SAJAT-FELHASZNALO/godaddy-ddns-opnsense/main"
```

## 2. Telepítés OPNsense-en

Az OPNsense shellből:

```sh
fetch -qo /tmp/godaddy-ddns-install.sh https://raw.githubusercontent.com/SAJAT-FELHASZNALO/godaddy-ddns-opnsense/main/install.sh
chmod 700 /tmp/godaddy-ddns-install.sh
/tmp/godaddy-ddns-install.sh
```

A telepítő:
1. letölti a `godaddy-ddns.sh` aktuális verzióját,
2. telepíti `/usr/local/sbin/godaddy-ddns.sh` alá,
3. létrehozza a konfigurációt, ha még nincs,
4. interaktívan bekéri az adatokat.

## 3. Alapértelmezett értékek

Első konfiguráláskor:

```text
DOMAIN = your.domain
HOST   = vpn
TTL    = 600
```

A GoDaddy Personal Access Token (PAT) kötelező.

## 4. Újrakonfigurálás

Ha már van konfiguráció:

```sh
/usr/local/sbin/godaddy-ddns.sh --configure
```

A korábbi értékeket felajánlja, így például csak Entert kell nyomni, ha meg akarod tartani őket.

## 5. Kézi futtatás

```sh
/usr/local/sbin/godaddy-ddns.sh
```

## 6. GitHub-ról frissítés

A telepített script frissíthető:

```sh
/usr/local/sbin/godaddy-ddns.sh --update
```

A frissítés csak a programfájlt cseréli le.

A konfiguráció:

```text
/etc/godaddy-ddns.conf
```

megmarad.

A GoDaddy PAT tehát nincs benne a GitHub repositoryban.

## 7. Verzió lekérdezése

```sh
/usr/local/sbin/godaddy-ddns.sh --version
```

## 8. Tesztelés

```sh
/usr/local/sbin/godaddy-ddns.sh --check
```

A `--check` nem módosítja a DNS rekordot. Csak ellenőrzi:
- publikus IP,
- GoDaddy API elérés,
- jelenlegi A rekord.

## 9. Automatikus futtatás OPNsense-en

A legegyszerűbb megoldás az OPNsense cron használata.

Javasolt például 5 percenként:

```text
*/5 * * * * /usr/local/sbin/godaddy-ddns.sh
```

A script ettől nem fog feleslegesen DNS rekordot módosítani: ha az IP nem változott, csak logol és kilép.

## Biztonság

A konfigurációs fájl jogosultsága:

```text
600
```

A program:

```text
700
```

A PAT soha nem kerül a GitHub repositoryba.

**Ne commitold a `/etc/godaddy-ddns.conf` tartalmát.**

## GoDaddy PAT

A GoDaddy Personal Access Token-t a GoDaddy fiókodban kell létrehozni, megfelelő DNS API jogosultsággal.

A tokennek legalább a szükséges domain DNS módosításához szükséges jogosultsággal kell rendelkeznie.

## Megjegyzés OPNsense-ről

A script FreeBSD/OPNsense környezetre készült, és a rendszer `fetch` parancsát használja. A JSON feldolgozásához a következő szükséges:

```text
/usr/local/bin/jq
```

Ha nincs telepítve, telepítsd az OPNsense plugin/package kezelésén keresztül.

## Licenc

MIT
