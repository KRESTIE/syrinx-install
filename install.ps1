# Syrinx — installation en une commande sur un PC Windows 10 ou 11, avec Docker Desktop.
#
#   irm <adresse de ce fichier> | iex
#
# À coller dans PowerShell (menu Démarrer › PowerShell), sans droits administrateur. Ce que fait ce script :
#   1. vérifie Docker Desktop ; s'il manque, propose de l'installer (winget), puis demande de relancer la commande ;
#      s'il est installé mais arrêté, le démarre ;
#   2. fait choisir le dossier de ta musique (fenêtre de choix de dossier, avec une proposition) ;
#   3. écrit compose.yml et .env dans %USERPROFILE%\Syrinx (Navidrome + le serveur Syrinx) ;
#   4. autorise les appareils de ton réseau privé a joindre Syrinx (une confirmation Windows) ;
#   5. lance les conteneurs, crée un raccourci « Syrinx » sur le bureau et ouvre l'assistant dans le navigateur.
# Il ne touche pas a ta musique (lecture seule, sauf le sous-dossier Imports où vont les fichiers ajoutés depuis
# Syrinx) et n'ouvre rien sur Internet. Même installation que install.sh (Linux), adaptée à Windows :
#   - les données (base de Navidrome, réglages de Syrinx) sont dans des volumes Docker et pas dans un dossier
#     Windows : SQLite n'aime pas les dossiers partagés entre Windows et la machine virtuelle de Docker ;
#   - un petit conteneur « init » donne ces volumes au compte 1000 avant le démarrage (les serveurs ne tournent
#     jamais en root).
#
# Options (si le script est enregistré : .\install.ps1 -Music D:\Musique -Yes) :
#   -Music <dossier>   dossier de la musique (sinon : fenêtre de choix)
#   -Dir <dossier>     où ranger compose.yml et .env ; défaut : %USERPROFILE%\Syrinx
#   -Port <n>          port de Syrinx web ; défaut : 8090, ou le suivant libre
#   -Yes               aucune question : les propositions sont prises telles quelles
#   -DryRun            écrit les fichiers mais ne lance rien (tests, marche aussi sous Linux avec pwsh)
# Variable : SYRINX_IMAGE (image du serveur).
param(
    [string]$Music = "",
    [string]$Dir = "",
    [int]$Port = 0,
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
# Compatible Windows PowerShell 5.1 (celui de Windows) : pas de ?? ni de ternaire
$Image = $env:SYRINX_IMAGE
if (-not $Image) { $Image = "ghcr.io/krestie/syrinx:public" }
$FR = (Get-Culture).TwoLetterISOLanguageName -eq "fr"
$OnWindows = ($env:OS -eq "Windows_NT")
if ($DryRun) { $Yes = [switch]$true }

function Say([string]$fr, [string]$en) { if ($FR) { Write-Host $fr } else { Write-Host $en } }
function T([string]$fr, [string]$en) { if ($FR) { return $fr } else { return $en } }
function Fail([string]$fr, [string]$en) {
    Write-Host ""
    if ($FR) { Write-Host "Erreur : $fr" -ForegroundColor Red } else { Write-Host "Error: $en" -ForegroundColor Red }
    # Avec « irm | iex », exit fermerait la fenêtre PowerShell : on s'arrête sans la fermer
    throw "Syrinx"
}
function Ask([string]$question, [string]$proposal) {
    if ($Yes) { return $proposal }
    $a = Read-Host "$question [$proposal]"
    if ($a) { return $a.Trim().Trim('"') } else { return $proposal }
}
# Commande Docker sans affichage. Windows PowerShell 5.1 transforme la sortie d'erreur d'un programme redirigée en
# exception quand ErrorActionPreference vaut Stop : on la coupe le temps de l'appel. Rend le code de sortie.
function Quiet([scriptblock]$cmd) {
    $old = $ErrorActionPreference; $ErrorActionPreference = "SilentlyContinue"
    $code = 1
    try { & $cmd *> $null; $code = $LASTEXITCODE } catch { $code = 1 } finally { $ErrorActionPreference = $old }
    return $code
}
function DockerOk { return ((Quiet { docker info }) -eq 0) }

try {
Write-Host ""
Say "Syrinx — installation" "Syrinx — installation"
Write-Host "======================"

# ---------------------------------------------------------------- 1. Docker Desktop
if (-not $DryRun) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Say "Docker Desktop n'est pas installé. Syrinx tourne dedans (comme sur un NAS)." `
            "Docker Desktop isn't installed. Syrinx runs inside it (like on a NAS)."
        $ok = Ask (T "L'installer maintenant ? (o/n)" "Install it now? (y/n)") (T "o" "y")
        if ($ok -notmatch "^[oOyY]") { Fail "Docker Desktop est nécessaire : https://www.docker.com/products/docker-desktop/" `
                                            "Docker Desktop is required: https://www.docker.com/products/docker-desktop/" }
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Fail "winget est introuvable. Installe Docker Desktop depuis https://www.docker.com/products/docker-desktop/ puis relance cette commande." `
                 "winget not found. Install Docker Desktop from https://www.docker.com/products/docker-desktop/ then run this command again."
        }
        Say "Installation de Docker Desktop (Windows va demander une confirmation)…" "Installing Docker Desktop (Windows will ask for confirmation)..."
        $ErrorActionPreference = "Continue"
        winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
        Write-Host ""
        Say "Docker Desktop est installé. Il reste deux choses :" "Docker Desktop is installed. Two things left:"
        Say "  1. redémarre le PC (Docker a besoin de WSL, activé à l'installation) ;" "  1. restart the PC (Docker needs WSL, enabled during setup);"
        Say "  2. ouvre Docker Desktop une fois, accepte ses conditions, puis relance cette commande." `
            "  2. open Docker Desktop once, accept its terms, then run this command again."
        return
    }
    if (-not (DockerOk)) {
        $exe = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
        if (Test-Path $exe) {
            Say "Démarrage de Docker Desktop…" "Starting Docker Desktop..."
            Start-Process $exe
            $t = 0
            while (-not (DockerOk) -and $t -lt 150) { Start-Sleep -Seconds 3; $t += 3 }
        }
        if (-not (DockerOk)) {
            Fail "Docker Desktop ne répond pas. Ouvre-le (accepte ses conditions la première fois), attends qu'il soit prêt, puis relance cette commande." `
                 "Docker Desktop isn't responding. Open it (accept its terms the first time), wait until it's ready, then run this command again."
        }
    }
    if ((Quiet { docker compose version }) -ne 0) { Fail "« docker compose » est introuvable : mets Docker Desktop à jour." "`"docker compose`" not found: update Docker Desktop." }
}

# ---------------------------------------------------------------- 2. Musique
if (-not $Music) {
    $guess = Join-Path $HOME "Music"
    foreach ($d in @((Join-Path $HOME "Musique"), (Join-Path $HOME "Music"), "D:\Musique", "D:\Music")) {
        if (Test-Path $d -PathType Container) { $guess = $d; break }
    }
    if ($OnWindows -and -not $Yes) {
        # Fenêtre de choix de dossier ; si elle ne peut pas s'ouvrir (PowerShell 7 sans STA…), question au clavier
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = T "Choisis le dossier de ta musique (Syrinx le lit sans jamais le modifier)" "Choose your music folder (Syrinx reads it, never changes it)"
            $dlg.SelectedPath = $guess
            $dlg.ShowNewFolderButton = $true
            $top = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
            Say "Choisis le dossier de ta musique dans la fenêtre qui s'ouvre…" "Choose your music folder in the window that opens..."
            if ($dlg.ShowDialog($top) -eq [System.Windows.Forms.DialogResult]::OK) { $Music = $dlg.SelectedPath }
            $top.Dispose()
        } catch { $Music = "" }
    }
    if (-not $Music) { $Music = Ask (T "Dossier de ta musique ?" "Where is your music?") $guess }
}
$Music = [System.IO.Path]::GetFullPath(($Music -replace "^~", $HOME)).TrimEnd("\", "/")
if (-not (Test-Path $Music -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $Music | Out-Null
    Say "Dossier créé : $Music (copie ta musique dedans)." "Folder created: $Music (copy your music into it)."
}

# ---------------------------------------------------------------- 3. Dossier de Syrinx, port
if (-not $Dir) { $Dir = Join-Path $HOME "Syrinx" }
$Dir = [System.IO.Path]::GetFullPath($Dir).TrimEnd("\", "/")

function PortBusy([int]$p) {
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        return [bool](Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue)
    }
    return $false
}
if ($Port -eq 0) {
    $Port = 8090
    while ((PortBusy $Port) -and $Port -lt 8100) { $Port++ }
}

$Tz = "UTC"
try {
    # Fuseau Windows (« W. Europe Standard Time ») → nom IANA (« Europe/Zurich ») pour les conteneurs
    $win = (Get-TimeZone).Id
    $iana = $null
    if ([System.TimeZoneInfo] | Get-Member -Static -Name TryConvertWindowsIdToIanaId) {   # .NET 6+ (PowerShell 7)
        if ([System.TimeZoneInfo]::TryConvertWindowsIdToIanaId($win, [ref]$iana)) { $Tz = $iana }
    } elseif ($win -match "/") { $Tz = $win }
    elseif ($win -in @("W. Europe Standard Time", "Romance Standard Time", "Central Europe Standard Time")) { $Tz = "Europe/Zurich" }
} catch { }

Write-Host ""
Say "  Musique : $Music (lecture seule)" "  Music:   $Music (read-only)"
Say "  Syrinx  : $Dir" "  Syrinx:  $Dir"
Say "  Port    : $Port" "  Port:    $Port"
$ok = Ask (T "On installe ? (o/n)" "Install? (y/n)") (T "o" "y")
if ($ok -notmatch "^[oOyY]") { Say "Rien n'a été changé." "Nothing was changed."; return }

New-Item -ItemType Directory -Force -Path $Dir, (Join-Path $Music "Imports") | Out-Null

# ---------------------------------------------------------------- 4. Fichiers
# Docker Desktop comprend les chemins Windows avec des / (C:/Users/…)
$musicPath = $Music.Replace("\", "/")
$utf8 = New-Object System.Text.UTF8Encoding($false)   # sans BOM : docker compose lit le .env tel quel
$envText = @"
# Réglages de Syrinx (écrits par install.ps1). Après un changement : docker compose up -d
MUSIC_PATH='$musicPath'
PORT=$Port
PUID=1000
PGID=1000
TZ=$Tz
SYRINX_IMAGE=$Image
"@
[System.IO.File]::WriteAllText((Join-Path $Dir ".env"), $envText.Replace("`r`n", "`n") + "`n", $utf8)

$compose = @'
# Syrinx (écrit par install.ps1, pour Docker Desktop sous Windows). Réglages : .env, à côté.
# Mise à jour :  docker compose pull ; docker compose up -d
name: syrinx

services:
  # Donne les volumes de données au compte des serveurs (1000), puis s'arrete
  init:
    image: busybox:1.36
    command: ["sh", "-c", "chown -R ${PUID}:${PGID} /navidrome /syrinx"]
    volumes:
      - navidrome-data:/navidrome
      - syrinx-data:/syrinx

  navidrome:
    image: deluan/navidrome:0.64.2
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    depends_on:
      init:
        condition: service_completed_successfully
    # Aucun port ouvert : seul Syrinx parle à Navidrome (son compte est créé par l'assistant de Syrinx)
    environment:
      ND_SCANSCHEDULE: "1h"
      ND_SESSIONTIMEOUT: "168h"
      ND_ENABLETRANSCODINGCONFIG: "true"
      ND_SCANNER_PURGEMISSING: "full"
      TZ: "${TZ}"
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://127.0.0.1:4533/ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 1m
    volumes:
      - navidrome-data:/data
      - "${MUSIC_PATH}:/music:ro"
    logging: &logging
      driver: json-file
      options: {max-size: "10m", max-file: "3"}

  syrinx:
    image: "${SYRINX_IMAGE}"
    restart: unless-stopped
    depends_on:
      navidrome:
        condition: service_healthy
    ports:
      - "${PORT}:8090"
    environment:
      PUID: "${PUID}"
      PGID: "${PGID}"
      TZ: "${TZ}"
      NAVIDROME_URL: http://navidrome:4533
      NAVIDROME_DB: /navidrome/navidrome.db
      MUSIC_LABEL: "${MUSIC_PATH}"
    # Données rendues à PUID au démarrage, puis le serveur tourne avec ce compte (jamais root)
    command: ["sh", "-c", "chown $${PUID}:$${PGID} /data /music/Imports; exec setpriv --reuid=$${PUID} --regid=$${PGID} --clear-groups python web.py"]
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/healthz', timeout=10)"]
      interval: 1m
      timeout: 15s
      retries: 3
      start_period: 2m
    volumes:
      - "${MUSIC_PATH}:/music:ro"
      # « Ajouter des fichiers » (achats, CD numérisés) : le seul dossier où Syrinx peut écrire
      - "${MUSIC_PATH}/Imports:/music/Imports"
      - syrinx-data:/data
      - navidrome-data:/navidrome
    logging: *logging

volumes:
  navidrome-data:
  syrinx-data:
'@
[System.IO.File]::WriteAllText((Join-Path $Dir "compose.yml"), $compose.Replace("`r`n", "`n") + "`n", $utf8)

Write-Host ""
Say "Fichiers écrits dans $Dir." "Files written to $Dir."
if ($DryRun) { return }

# ---------------------------------------------------------------- 5. Pare-feu (réseau privé seulement)
# Sans cette règle, Windows peut bloquer le téléphone. Une seule confirmation Windows ; refusée, on continue.
if ($OnWindows -and -not (Get-NetFirewallRule -DisplayName "Syrinx" -ErrorAction SilentlyContinue)) {
    Say "Autorisation des appareils de ton réseau privé (Windows va demander une confirmation)…" `
        "Allowing devices on your private network (Windows will ask for confirmation)..."
    $rule = "New-NetFirewallRule -DisplayName 'Syrinx' -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private | Out-Null"
    try { Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList "-NoProfile", "-Command", $rule }
    catch { Say "  Refusé : Syrinx marchera sur ce PC ; pour le téléphone, relance la commande et accepte." `
                "  Declined: Syrinx will work on this PC; for your phone, run the command again and accept." }
}

# ---------------------------------------------------------------- 6. Lancement
Say "Téléchargement et démarrage (quelques minutes la première fois)…" "Downloading and starting (a few minutes the first time)..."
Push-Location $Dir
try {
    $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"   # docker écrit sa progression sur stderr
    docker compose up -d
    $ErrorActionPreference = $old
    if ($LASTEXITCODE -ne 0) { Fail "le démarrage a échoué (détails ci-dessus)." "startup failed (details above)." }
    $t = 0
    while ($t -lt 180) {
        if ((Quiet { docker compose exec -T syrinx python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/healthz', timeout=5)" }) -eq 0) { break }
        Start-Sleep -Seconds 2; $t += 2
    }
} finally { Pop-Location }

$ip = $null
try {
    $ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } |
           Select-Object -First 1).IPv4Address.IPAddress
} catch { }
$local = "http://localhost:$Port/app/"

# Raccourci « Syrinx » sur le bureau
try {
    $desk = [Environment]::GetFolderPath("Desktop")
    [System.IO.File]::WriteAllText((Join-Path $desk "Syrinx.url"), "[InternetShortcut]`r`nURL=$local`r`n")
} catch { }

Write-Host ""
Say "C'est installé. L'assistant s'ouvre dans ton navigateur (prénom, mot de passe, téléphone)." `
    "Installed. The setup assistant opens in your browser (name, password, phone)."
Write-Host ""
Write-Host "    Sur ce PC : $local"
if ($ip) { Say "    Depuis ton réseau : http://${ip}:$Port/app/" "    From your network: http://${ip}:$Port/app/" }
Write-Host ""
Say "Syrinx tourne tant que Docker Desktop est ouvert : laisse « Démarrer Docker Desktop à l'ouverture de session » coché dans ses réglages." `
    "Syrinx runs while Docker Desktop is open: keep `"Start Docker Desktop when you sign in`" checked in its settings."
Start-Process $local
} catch {
    if ("$_" -ne "Syrinx") { Write-Host ""; Write-Host "$_" -ForegroundColor Red }
}
