# copy-public.ps1 - interactive copy of local public/ to a Kubernetes front pod.
# Usage:
#   .\copy-public.ps1
# Optional fast path:
#   .\copy-public.ps1 -SourceDir school -Namespace a1n

param(
    [string]$SourceDir,
    [string]$Namespace,
    [string]$Kubeconfig = ""
)

$ErrorActionPreference = "Stop"

function Abort($Message) {
    Write-Host "`nABORT: $Message" -ForegroundColor Red
    exit 1
}

function Resolve-ExistingDirectory($Path, $Label) {
    if (-not $Path) {
        Abort "$Label не указан."
    }

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Abort "$Label не найден: $Path"
    }

    $item = Get-Item -LiteralPath $resolved.Path
    if (-not $item.PSIsContainer) {
        Abort "$Label не папка: $Path"
    }

    return $item.FullName
}

function Select-FromList($Title, $Items) {
    if (-not $Items -or $Items.Count -eq 0) {
        Abort "Нет вариантов для выбора: $Title"
    }

    Write-Host "`n  ${Title}:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ("  [{0,2}] {1}" -f ($i + 1), $Items[$i])
    }

    Write-Host ""
    $raw = Read-Host "Выбери номер"
    $idx = 0
    if (-not [int]::TryParse($raw, [ref]$idx)) {
        Abort "Неверный номер."
    }

    $idx = $idx - 1
    if ($idx -lt 0 -or $idx -ge $Items.Count) {
        Abort "Неверный номер."
    }

    return $Items[$idx]
}

function Confirm-Step($Message) {
    $answer = Read-Host "$Message [y/N]"
    return $answer -match '^(y|yes|д|да)$'
}

if (-not (Test-Path -LiteralPath $Kubeconfig)) {
    Abort "Kubeconfig не найден: $Kubeconfig"
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`nCOPY PUBLIC TO FRONT" -ForegroundColor Green
Write-Host "Скрипт скопирует выбранную папку public в /usr/src/public выбранного front pod." -ForegroundColor Gray

if (-not $SourceDir) {
    $publicDirs = Get-ChildItem -LiteralPath $repoRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "public") } |
        Select-Object -ExpandProperty Name
    $SourceDir = Select-FromList "Что копируем: папки с public" $publicDirs
} else {
    Write-Host "`nSourceDir задан параметром: $SourceDir" -ForegroundColor Gray
}

if ([System.IO.Path]::IsPathRooted($SourceDir)) {
    $sourceRoot = Resolve-ExistingDirectory $SourceDir "SourceDir"
} else {
    $sourceRoot = Resolve-ExistingDirectory (Join-Path $repoRoot $SourceDir) "SourceDir"
}

$publicDir = Join-Path $sourceRoot "public"
if (-not (Test-Path -LiteralPath $publicDir)) {
    Abort "В SourceDir нет public: $publicDir"
}

if (-not $Namespace) {
    Write-Host "`nПолучаю namespace'ы..." -ForegroundColor Cyan
    $nsRaw = kubectl --kubeconfig $Kubeconfig get namespaces -o jsonpath='{.items[*].metadata.name}' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Abort "kubectl недоступен: $nsRaw"
    }

    $namespaces = ($nsRaw -split ' ') |
        Where-Object { $_ -ne '' -and $_ -notmatch '^kube-' -and $_ -ne 'default' } |
        Sort-Object
    $Namespace = Select-FromList "Куда копируем: namespace / куб" $namespaces
} else {
    Write-Host "`nNamespace задан параметром: $Namespace" -ForegroundColor Gray
}

Write-Host "`n[1/4] Ищу front-* pod в $Namespace..." -ForegroundColor Cyan
$frontPodsRaw = kubectl --kubeconfig $Kubeconfig get pods -n $Namespace -o name 2>&1

if ($LASTEXITCODE -ne 0) {
    Abort "Не удалось получить pod'ы namespace ${Namespace}: $frontPodsRaw"
}

$frontPods = @($frontPodsRaw |
    Where-Object { $_ -match '^pod/front-' } |
    ForEach-Object { $_ -replace '^pod/', '' })

if (-not $frontPods) {
    Abort "Нет front-* pod в namespace $Namespace."
}

$frontPodName = if ($frontPods.Count -eq 1) {
    $frontPods[0]
} else {
    Select-FromList "Front pod'ы" $frontPods
}

Write-Host "OK: $frontPodName" -ForegroundColor Green

Write-Host "`nПроверь выбор:" -ForegroundColor Yellow
Write-Host "  Source    : $sourceRoot\public"
Write-Host "  Namespace : $Namespace"
Write-Host "  Front pod : $frontPodName"
if (-not (Confirm-Step "Копировать?")) {
    Abort "Отменено пользователем."
}

$tarPath = Join-Path ([System.IO.Path]::GetTempPath()) ("mojo-public-{0}-{1}.tar" -f $Namespace, ([guid]::NewGuid().ToString("N")))

try {
    Write-Host "`n[2/4] Упаковываю $publicDir..." -ForegroundColor Cyan
    Push-Location $sourceRoot
    try {
        tar -czf $tarPath --exclude="public/storage" public
        if ($LASTEXITCODE -ne 0) {
            Abort "tar завершился с ошибкой."
        }
    } finally {
        Pop-Location
    }
    Write-Host "OK: $tarPath" -ForegroundColor Green

    Write-Host "`n[3/4] Копирую public в $Namespace/${frontPodName}:/usr/src/public..." -ForegroundColor Cyan
    $kubectl = (Get-Command kubectl -ErrorAction SilentlyContinue).Source
    if (-not $kubectl) {
        Abort "kubectl не найден в PATH."
    }

    $remoteCommand = "tar xzf - -C /usr/src/ --overwrite && echo OK"
    $cmdLine = "`"$kubectl`" --kubeconfig `"$Kubeconfig`" exec -n `"$Namespace`" `"$frontPodName`" -i -- sh -c `"$remoteCommand`" < `"$tarPath`""
    cmd.exe /d /s /c $cmdLine
    if ($LASTEXITCODE -ne 0) {
        Abort "Копирование в pod завершилось с ошибкой."
    }

    Write-Host "`n[4/4] Проверяю public в pod..." -ForegroundColor Cyan
    $check = kubectl --kubeconfig $Kubeconfig exec -n $Namespace $frontPodName -- sh -c "test -d /usr/src/public && find /usr/src/public -maxdepth 1 | wc -l" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Abort "Не удалось проверить /usr/src/public: $check"
    }

    Write-Host "OK: элементов на верхнем уровне /usr/src/public: $($check.Trim())" -ForegroundColor Green
    Write-Host "`nPUBLIC COPY OK" -ForegroundColor Green
    Write-Host " Source    : $sourceRoot\public"
    Write-Host " Namespace : $Namespace"
    Write-Host " Front pod : $frontPodName"
} finally {
    if (Test-Path -LiteralPath $tarPath) {
        Remove-Item -LiteralPath $tarPath -Force
    }
}
