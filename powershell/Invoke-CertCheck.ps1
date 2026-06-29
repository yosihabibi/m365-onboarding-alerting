<#
======================================================================
 Invoke-CertCheck.ps1  -  Runner fuer das Modul M365CertGuard
----------------------------------------------------------------------
 Was es tut:
   1. Laedt das Modul M365CertGuard (liegt im Unterordner daneben).
   2. Fragt das Client-Secret sicher ab (SecureString, nie im Code).
   3. Meldet die App per OAuth2 Client-Credentials an.
   4. Listet bald ablaufende Zertifikate/Secrets als Tabelle.
   5. Optional: schickt die Treffer per -WebhookUrl an n8n.

 Beispiele:
   .\Invoke-CertCheck.ps1
   .\Invoke-CertCheck.ps1 -WarningDays 800           # zeigt auch laenger gueltige (Demo)
   .\Invoke-CertCheck.ps1 -IncludeServicePrincipals  # auch SSO-Zertifikate
   .\Invoke-CertCheck.ps1 -WebhookUrl "https://<n8n>/webhook/cert-alert"

 Setup: Tenant- und Client-ID kommen aus Umgebungsvariablen
   $env:GRAPH_TENANT_ID = "<your-tenant-id>"
   $env:GRAPH_CLIENT_ID = "<your-client-id>"
======================================================================
#>
[CmdletBinding()]
param(
    [int]    $WarningDays = 14,
    [string] $WebhookUrl,
    [switch] $IncludeServicePrincipals
)

# TLS 1.2 erzwingen (manche Windows-PowerShell-5.1-Setups nutzen sonst zu alte Protokolle)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- App-IDs aus Umgebungsvariablen (nicht geheim, aber so bleibt das Repo mandantenfaehig) ---
$TenantId = $env:GRAPH_TENANT_ID
$ClientId = $env:GRAPH_CLIENT_ID
if (-not $TenantId -or -not $ClientId) {
    throw "Bitte Umgebungsvariablen GRAPH_TENANT_ID und GRAPH_CLIENT_ID setzen (siehe README)."
}

# --- OneDrive-Falle umgehen: echten "Dokumente"-Modulpfad in PSModulePath aufnehmen ---
#     OneDrive leitet "Dokumente" um (z.B. ...\OneDrive\Dokumente). Dann liegen die per
#     Install-Module -Scope CurrentUser installierten Module dort, aber PowerShell sucht im
#     nicht-umgeleiteten ...\Documents -> "Modul nicht gefunden". Diese Zeilen heilen das.
$docsModules = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
if ((Test-Path $docsModules) -and (($env:PSModulePath -split ';') -notcontains $docsModules)) {
    $env:PSModulePath = "$docsModules;$env:PSModulePath"
}

# --- Module laden (klare Fehlermeldung, falls etwas fehlt) ---
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Applications   -ErrorAction Stop
Import-Module "$PSScriptRoot\M365CertGuard\M365CertGuard.psd1" -Force -ErrorAction Stop

# --- Client-Secret sicher abfragen (bleibt SecureString) ---
Write-Host "Client-Secret einfuegen + Enter (Eingabe bleibt unsichtbar):" -ForegroundColor Cyan
$Secret = Read-Host -AsSecureString

try {
    Connect-CertGuard -TenantId $TenantId -ClientId $ClientId -ClientSecret $Secret -Verbose

    # @(...) erzwingt ein Array -> .Count stimmt auch bei nur 1 Treffer (PS-5.1-Falle)
    $findings = @(Get-AppCredentialExpiry -WarningDays $WarningDays `
                    -IncludeServicePrincipals:$IncludeServicePrincipals -Verbose)

    if ($findings.Count -eq 0) {
        Write-Host "`n[OK] Nichts laeuft in den naechsten $WarningDays Tagen ab. Alles gruen." -ForegroundColor Green
    }
    else {
        Write-Host "`n[!] $($findings.Count) ablaufende(s) Credential(s) gefunden:" -ForegroundColor Yellow
        $findings | Format-Table App, Typ, Credential, Name, EndetAm, TageRestlich, Status -AutoSize

        if ($WebhookUrl) {
            Send-CertExpiryWebhook -WebhookUrl $WebhookUrl -Findings $findings -Verbose
            Write-Host "[OK] Alarm an Webhook gesendet." -ForegroundColor Green
        }
        else {
            Write-Host "(Kein -WebhookUrl angegeben -> nur Anzeige, kein Alarm verschickt.)" -ForegroundColor DarkGray
        }
    }
}
catch {
    Write-Host "`n[FEHLER] $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor Yellow }
    Write-Host "Haeufige Ursachen: falsches/abgelaufenes Secret, Tippfehler bei IDs, oder fehlender Consent." -ForegroundColor Yellow
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    $Secret = $null
}
