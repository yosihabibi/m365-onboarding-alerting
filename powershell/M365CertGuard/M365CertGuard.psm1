<#
======================================================================
 M365CertGuard.psm1  -  PowerShell-Modul "Zertifikats-Waechter"
----------------------------------------------------------------------
 Zweck:
   Findet ablaufende App-/SSO-Zertifikate UND Client-Secrets in
   Microsoft Entra (ueber Microsoft Graph) und meldet sie - optional
   per Webhook an n8n (-> Teams-/E-Mail-Alarm).

 Erfuellt CV-Punkt 2: "Modulares PowerShell-Skript (Microsoft Graph SDK),
   das taeglich ablaufende SSO-/App-Zertifikate prueft und 14 Tage vor
   Ablauf per Webhook alarmiert."

 Oeffentliche Funktionen:
   Connect-CertGuard        - meldet die App per OAuth2 Client-Credentials an
   Get-AppCredentialExpiry  - liefert bald ablaufende Zertifikate/Secrets
   Send-CertExpiryWebhook   - schickt die Treffer als JSON an einen Webhook

 Sicherheit (wichtig fuer einen ISO-27001-MSP):
   - Kein Secret im Code. Es kommt als SecureString herein und bleibt das
     auch (kein Klartext im Speicher).
   - Least Privilege: kommt mit reinen *Read*-Rechten aus (Application.Read.All).
======================================================================
#>

# ---------------------------------------------------------------------
# PRIVAT (nicht exportiert): wandelt ein App-/ServicePrincipal-Objekt in
#   flache Eintraege um - ein Eintrag pro Zertifikat (keyCredentials) und
#   pro Secret (passwordCredentials).
#   DRY: einmal geschrieben, fuer beide Objekt-Arten genutzt.
# ---------------------------------------------------------------------
function ConvertTo-CredentialFinding {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string]   $ObjectType,
        [Parameter(Mandatory)] [datetime] $Now
    )

    # Beide Credential-Arten gleich behandeln: Zertifikat + Secret
    $sets = @(
        [pscustomobject]@{ Items = $Object.KeyCredentials;      Kind = 'Zertifikat' }
        [pscustomobject]@{ Items = $Object.PasswordCredentials; Kind = 'Secret'     }
    )

    foreach ($set in $sets) {
        foreach ($cred in $set.Items) {
            if (-not $cred.EndDateTime) { continue }   # ohne Ablaufdatum ueberspringen

            $end  = ([datetime]$cred.EndDateTime).ToUniversalTime()
            $days = [int][math]::Floor(($end - $Now).TotalDays)

            [pscustomobject]@{
                App          = $Object.DisplayName
                Typ          = $ObjectType
                Credential   = $set.Kind
                Name         = $cred.DisplayName
                EndetAm      = $end.ToString('yyyy-MM-dd')
                TageRestlich = $days
                AppId        = $Object.AppId
                KeyId        = $cred.KeyId
            }
        }
    }
}

# ---------------------------------------------------------------------
# Anmeldung: App-only via OAuth 2.0 Client-Credentials.
#   Das Secret bleibt SecureString -> nie als Klartext sichtbar.
# ---------------------------------------------------------------------
function Connect-CertGuard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]       $TenantId,
        [Parameter(Mandatory)] [string]       $ClientId,
        [Parameter(Mandatory)] [securestring] $ClientSecret
    )
    # PSCredential = Benutzername (ClientId) + Passwort (Secret als SecureString)
    $cred = [System.Management.Automation.PSCredential]::new($ClientId, $ClientSecret)
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $cred -NoWelcome
    Write-Verbose "Verbunden mit Tenant $TenantId als App $ClientId."
}

# ---------------------------------------------------------------------
# Kern: bald ablaufende (oder schon abgelaufene) Zertifikate/Secrets finden.
# ---------------------------------------------------------------------
function Get-AppCredentialExpiry {
    [CmdletBinding()]
    param(
        [int]    $WarningDays = 14,            # Schwelle: so viele Tage vorher warnen
        [switch] $IncludeServicePrincipals     # auch SSO-Zertifikate der Enterprise-Apps
    )

    $now = (Get-Date).ToUniversalTime()
    $all = New-Object System.Collections.Generic.List[object]

    # 1) App-Registrierungen (App-Zertifikate + Client-Secrets)
    Write-Verbose "Lese App-Registrierungen ..."
    foreach ($app in (Get-MgApplication -All)) {
        foreach ($f in (ConvertTo-CredentialFinding -Object $app -ObjectType 'App-Registrierung' -Now $now)) {
            $all.Add($f)
        }
    }

    # 2) Optional: Service-Principals - hier sitzen die SSO-/SAML-Zertifikate
    if ($IncludeServicePrincipals) {
        Write-Verbose "Lese Service-Principals (SSO) ..."
        foreach ($sp in (Get-MgServicePrincipal -All)) {
            foreach ($f in (ConvertTo-CredentialFinding -Object $sp -ObjectType 'Service-Principal' -Now $now)) {
                $all.Add($f)
            }
        }
    }

    # 3) Auf die Warnschwelle filtern (abgelaufene = negative Tage zaehlen mit),
    #    Status setzen, dringendste zuerst.
    $all |
        Where-Object { $_.TageRestlich -le $WarningDays } |
        ForEach-Object {
            $status = if ($_.TageRestlich -lt 0) { 'ABGELAUFEN' } else { 'LAEUFT-BALD-AB' }
            $_ | Add-Member -NotePropertyName Status -NotePropertyValue $status -PassThru
        } |
        Sort-Object TageRestlich
}

# ---------------------------------------------------------------------
# Alarm: Treffer als JSON an einen Webhook schicken (z.B. n8n).
# ---------------------------------------------------------------------
function Send-CertExpiryWebhook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WebhookUrl,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Findings
    )
    $items = @($Findings)
    if ($items.Count -eq 0) {
        Write-Verbose "Keine ablaufenden Credentials -> kein Webhook gesendet."
        return
    }

    # PS-5.1-Quirk: ConvertTo-Json macht aus einem 1-Element-Array ein Einzelobjekt.
    # Darum 'items' separat serialisieren und bei genau 1 Treffer das [] erzwingen,
    # damit die Gegenstelle (n8n) IMMER eine Liste bekommt.
    $itemsJson = if ($items.Count -eq 1) {
        '[' + ($items[0] | ConvertTo-Json -Depth 6) + ']'
    } else {
        $items | ConvertTo-Json -Depth 6
    }

    $payload = @"
{
  "source": "M365CertGuard",
  "checkedAt": "$((Get-Date).ToString('s'))",
  "count": $($items.Count),
  "items": $itemsJson
}
"@

    Invoke-RestMethod -Method Post -Uri $WebhookUrl `
        -ContentType 'application/json; charset=utf-8' -Body $payload | Out-Null
    Write-Verbose "Webhook gesendet: $($items.Count) Eintrag/Eintraege."
}

Export-ModuleMember -Function Connect-CertGuard, Get-AppCredentialExpiry, Send-CertExpiryWebhook
