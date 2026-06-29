<#
======================================================================
 Test-GraphToken.ps1
 Erster Funktionstest der App-Registrierung (Client-Credentials).

 Was macht das Skript?
   1. Holt ein OAuth-2.0-Access-Token (Client-Credentials-Flow) von Entra.
   2. Ruft damit die Microsoft Graph API auf (Org-Infos + Benutzerliste).
   -> Beweist, dass Client-ID, Tenant-ID, Secret, Berechtigungen
      und Admin-Consent korrekt zusammenspielen.

 Sicherheit:
   - Client-ID & Tenant-ID sind KEINE Geheimnisse, kommen hier aber aus
     Umgebungsvariablen (GRAPH_TENANT_ID / GRAPH_CLIENT_ID) -> mandantenfaehig.
   - Das Client-Secret wird NICHT gespeichert, sondern zur Laufzeit
     sicher abgefragt (Read-Host -AsSecureString) und am Ende geleert.
======================================================================
#>

# TLS 1.2 erzwingen (manche Windows-PowerShell-5.1-Setups nutzen sonst zu alte Protokolle)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- App-IDs aus Umgebungsvariablen (nicht geheim, aber mandantenfaehig) ---
$TenantId = $env:GRAPH_TENANT_ID
$ClientId = $env:GRAPH_CLIENT_ID
if (-not $TenantId -or -not $ClientId) {
    throw "Bitte Umgebungsvariablen GRAPH_TENANT_ID und GRAPH_CLIENT_ID setzen (siehe README)."
}

# --- Client-Secret sicher zur Laufzeit abfragen (landet NICHT im Code) ---
Write-Host "Bitte das Client-Secret einfuegen und Enter (Eingabe bleibt unsichtbar):" -ForegroundColor Cyan
$SecureSecret = Read-Host -AsSecureString
$ClientSecret = [System.Net.NetworkCredential]::new("", $SecureSecret).Password

try {
    # === 1) Access-Token holen (OAuth 2.0 Client-Credentials) ===
    $TokenBody = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"   # alle erteilten App-Rechte
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }
    $Token = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $TokenBody

    Write-Host "`n[OK] Access-Token erhalten (gueltig $($Token.expires_in) Sekunden, ~1 Stunde)." -ForegroundColor Green

    # Dieser Header wird bei JEDEM Graph-Aufruf mitgeschickt ("Bearer"-Token)
    $Headers = @{ Authorization = "Bearer $($Token.access_token)" }

    # === 2a) Test-Aufruf: Organisation lesen (nutzt Organization.Read.All) ===
    $Org = Invoke-RestMethod -Method Get -Headers $Headers `
        -Uri "https://graph.microsoft.com/v1.0/organization"
    Write-Host "[OK] Graph erreichbar. Deine Organisation:" -ForegroundColor Green
    $Org.value | Select-Object displayName, @{n='Land';e={$_.countryLetterCode}}, id | Format-List

    # === 2b) Test-Aufruf: Benutzer auflisten (nutzt User.ReadWrite.All) ===
    $Users = Invoke-RestMethod -Method Get -Headers $Headers `
        -Uri "https://graph.microsoft.com/v1.0/users"
    Write-Host "[OK] Benutzer im Tenant: $($Users.value.Count)" -ForegroundColor Green
    $Users.value | Select-Object displayName, userPrincipalName | Format-Table -AutoSize

    Write-Host "`n*** ALLES FUNKTIONIERT! Die App kann sich anmelden und Graph nutzen. ***`n" -ForegroundColor Green
}
catch {
    Write-Host "`n[FEHLER] Etwas hat nicht geklappt:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor Yellow }
    Write-Host "`nHaeufige Ursachen: falsches/abgelaufenes Secret, Tippfehler bei IDs, oder Consent fehlt." -ForegroundColor Yellow
}
finally {
    # Secret aus dem Speicher raeumen
    $ClientSecret = $null
    $TokenBody    = $null
}
