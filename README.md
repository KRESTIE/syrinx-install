# Syrinx - install

Your own music streaming service, for the music you already own (ripped CDs, vinyl, years of MP3s).
Your files stay on a small server at home; Syrinx gives you the app on your phone, in your car
(Android Auto) and in your browser. No ads, no tracking.

## Install

On a NAS, a Raspberry Pi or a Linux PC with Docker:

```sh
curl -fsSL https://raw.githubusercontent.com/KRESTIE/syrinx-install/main/install.sh | sh
```

The script asks one question (where your music is), writes `compose.yml` and `.env` into a `syrinx`
folder, starts Navidrome and the Syrinx server, then prints the address where you finish the setup in
your browser (name, password, phone). Your music is mounted read-only and nothing is opened to the
internet.

Update: `cd syrinx && docker compose pull && docker compose up -d`

### Windows 10 and 11

In PowerShell (Start menu › PowerShell), no admin rights needed:

```powershell
irm https://raw.githubusercontent.com/KRESTIE/syrinx-install/main/install.ps1 | iex
```

The script installs Docker Desktop if it's missing (then restart the PC, open Docker Desktop once and run the
command again), lets you pick your music folder in a window, writes `compose.yml` and `.env` into
`%USERPROFILE%\Syrinx`, allows your private network in the firewall (one Windows confirmation), starts Syrinx,
adds a "Syrinx" shortcut to the desktop and opens the setup in your browser. Syrinx runs while Docker Desktop is
open (it starts with Windows by default).

Update: `cd ~\Syrinx ; docker compose pull ; docker compose up -d`

If Docker needs admin rights (`sudo`), download the script first so it can read your answers:

```sh
curl -fsSL https://raw.githubusercontent.com/KRESTIE/syrinx-install/main/install.sh -o install.sh
sudo sh install.sh
```

Options: `--music <folder>`, `--dir <folder>`, `--port <n>`, `--yes` (no questions).

---

## Installation (français)

Ton propre service de streaming, pour la musique que tu as déjà (CD numérisés, vinyles, années de MP3).
Tes fichiers restent sur un petit serveur chez toi ; Syrinx te donne l'app sur ton téléphone, dans ta
voiture (Android Auto) et dans ton navigateur. Sans pub, sans pistage.

Sur un NAS, un Raspberry Pi ou un PC Linux avec Docker :

```sh
curl -fsSL https://raw.githubusercontent.com/KRESTIE/syrinx-install/main/install.sh | sh
```

Une seule question (où est ta musique), puis l'adresse où finir l'installation dans ton navigateur.

Si Docker demande les droits administrateur (`sudo`), télécharge d'abord le script pour qu'il puisse lire
tes réponses :

```sh
curl -fsSL https://raw.githubusercontent.com/KRESTIE/syrinx-install/main/install.sh -o install.sh
sudo sh install.sh
```

## License and security

© 2026 Syrinx. All rights reserved: you may read and run these scripts, not redistribute or resell them.
Found a security issue? Write to security@syrinx.li (see also https://syrinx.li/.well-known/security.txt).
Other questions: support@syrinx.li
