@{
    # Verweist auf die Code-Datei des Moduls
    RootModule        = 'M365CertGuard.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b1e6f0a2-7c44-4d9e-8a3b-2f5c9d10e7a4'
    Author            = 'Yosef AL Fadili'
    CompanyName       = 'YosefLab'
    Copyright         = '(c) 2026 Yosef AL Fadili'
    Description       = 'Ueberwacht ablaufende App-/SSO-Zertifikate und Client-Secrets in Microsoft Entra ueber Microsoft Graph und alarmiert per Webhook (z.B. an n8n).'
    PowerShellVersion = '5.1'

    # Nur diese drei Funktionen sind oeffentlich (Helper bleibt privat)
    FunctionsToExport = @('Connect-CertGuard', 'Get-AppCredentialExpiry', 'Send-CertExpiryWebhook')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags        = @('Microsoft365', 'Entra', 'Graph', 'Certificates', 'Automation', 'MSP')
            ProjectName = 'ristl.IT M365 Onboarding & Alerting Automation'
        }
    }
}
