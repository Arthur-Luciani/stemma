# Funções compartilhadas pelo instalador (setup.ps1), install.ps1, update.ps1 e start.ps1
# (ADRs 0007 e 0014). Compatível com o Windows PowerShell 5.1. Salvo com BOM (acentos).
#
# O código fica nos StemmaDeploy.<Assunto>.ps1 desta pasta, um por assunto, carregados aqui
# por dot-source: rodam no escopo do módulo (as variáveis $script: são as mesmas e os testes
# usam Mock -ModuleName StemmaDeploy). Parte nova entra nesta lista; o instalador
# (installer/stemma.iss) e o pacote (scripts/package.sh) já levam todos os StemmaDeploy.*.ps1.

Set-StrictMode -Version Latest

foreach ($part in 'Core', 'Config', 'Releases', 'Python', 'Service', 'Tools', 'UvCache', 'Network', 'Flows', 'YtDlp', 'AppUpdate') {
    . (Join-Path $PSScriptRoot "StemmaDeploy.$part.ps1")
}

Export-ModuleMember -Function *-*