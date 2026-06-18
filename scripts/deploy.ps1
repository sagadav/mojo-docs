# deploy.ps1 — интерактивный деплой ветки в k8s namespace
# Использование: .\deploy.ps1

$KUBECONFIG  = ""
$SCHOOL_DIR  = ""

function Abort($msg) {
    Write-Host "`nABORT: $msg" -ForegroundColor Red
    exit 1
}

# ── 1. Выбор namespace ──────────────────────────────────────────────────────

Write-Host "`nПолучаю namespace'ы..." -ForegroundColor Cyan
$nsRaw = kubectl --kubeconfig $KUBECONFIG get namespaces -o jsonpath='{.items[*].metadata.name}' 2>&1
if ($LASTEXITCODE -ne 0) { Abort "kubectl недоступен: $nsRaw" }

$namespaces = ($nsRaw -split ' ') |
    Where-Object { $_ -ne '' -and $_ -notmatch '^kube-' -and $_ -ne 'default' } |
    Sort-Object

if (-not $namespaces) { Abort "Нет доступных namespace'ов." }

Write-Host "`n  Namespace'ы:" -ForegroundColor Yellow
for ($i = 0; $i -lt $namespaces.Count; $i++) {
    Write-Host ("  [{0,2}] {1}" -f ($i + 1), $namespaces[$i])
}
Write-Host ""
$raw = Read-Host "Выбери namespace (номер)"
$idx = [int]$raw - 1
if ($idx -lt 0 -or $idx -ge $namespaces.Count) { Abort "Неверный номер." }
$ns = $namespaces[$idx]

# ── 2. Выбор ветки ──────────────────────────────────────────────────────────

Write-Host "`nПолучаю ветки..." -ForegroundColor Cyan
$branchRaw = git -C $SCHOOL_DIR branch -r --sort=-committerdate 2>&1
if ($LASTEXITCODE -ne 0) { Abort "git недоступен: $branchRaw" }

$currentBranch = (git -C $SCHOOL_DIR rev-parse --abbrev-ref HEAD 2>&1).Trim()

$branches = ($branchRaw -split "`n") |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -ne '' -and $_ -notmatch 'HEAD' } |
    ForEach-Object { $_ -replace '^origin/', '' } |
    Select-Object -Unique -First 40

Write-Host "`n  Ветки (по дате коммита):" -ForegroundColor Yellow
for ($i = 0; $i -lt $branches.Count; $i++) {
    $marker = if ($branches[$i] -eq $currentBranch) { "  <-- текущая" } else { "" }
    Write-Host ("  [{0,2}] {1}{2}" -f ($i + 1), $branches[$i], $marker)
}
Write-Host ""
$raw = Read-Host "Выбери ветку (номер)"
$idx = [int]$raw - 1
if ($idx -lt 0 -or $idx -ge $branches.Count) { Abort "Неверный номер." }
$branch = $branches[$idx]

Write-Host "`n>>> $branch  ->  $ns" -ForegroundColor Green

# ── 3. Preflight: ветка запушена? ───────────────────────────────────────────

Write-Host "`n[1/5] Проверяю origin..." -ForegroundColor Cyan
$remoteHash = (git -C $SCHOOL_DIR ls-remote origin $branch 2>&1) -split '\s+' | Select-Object -First 1
$localHash  = (git -C $SCHOOL_DIR rev-parse $branch 2>&1).Trim()

if (-not $remoteHash) { Abort "$branch не найдена на origin. Запушь сначала." }
if ($remoteHash -ne $localHash) { Abort "Локальная $branch != origin/$branch. Запушь или rebase." }
Write-Host "OK" -ForegroundColor Green

# ── 4. Находим core pod ─────────────────────────────────────────────────────

Write-Host "`n[2/5] Ищу core-* pod в $ns..." -ForegroundColor Cyan
$corePod = (kubectl --kubeconfig $KUBECONFIG get pods -n $ns -o name 2>&1) |
    Where-Object { $_ -match '^pod/core-' } |
    Select-Object -First 1

if (-not $corePod) { Abort "Нет core-* pod в namespace $ns." }
$podName = $corePod -replace '^pod/', ''
Write-Host "OK: $podName" -ForegroundColor Green

# ── 5. Preflight: конфликты на поде ─────────────────────────────────────────

Write-Host "`n[3/5] Проверяю изменения на поде..." -ForegroundColor Cyan

$touchedFiles = (git -C $SCHOOL_DIR log "origin/main..$branch" --name-only --pretty=format: 2>&1) |
    Where-Object { $_ -ne '' } | Sort-Object -Unique

$podStatusRaw = kubectl --kubeconfig $KUBECONFIG exec -n $ns $podName `
    -- sh -c "cd /usr/src && git status --porcelain" 2>&1
$podModified = ($podStatusRaw -split "`n") |
    Where-Object { $_ -ne '' } |
    ForEach-Object { ($_.Trim() -split '\s+')[-1] }

$conflicts = $podModified | Where-Object { $touchedFiles -contains $_ }
if ($conflicts) {
    Write-Host "ABORT: конфликт — файлы изменены на поде и затрагиваются веткой:" -ForegroundColor Red
    $conflicts | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Abort "Разреши вручную — stash/force не делаю."
}

$podBranch = (kubectl --kubeconfig $KUBECONFIG exec -n $ns $podName `
    -- sh -c "cd /usr/src && git rev-parse --abbrev-ref HEAD" 2>&1).Trim()
$podHead = (kubectl --kubeconfig $KUBECONFIG exec -n $ns $podName `
    -- sh -c "cd /usr/src && git log -1 --oneline" 2>&1).Trim()
Write-Host "Под сейчас: $podBranch  ($podHead)" -ForegroundColor Gray

# ── 6. Переключаем ветку ────────────────────────────────────────────────────

Write-Host "`n[4/5] Переключаю ветку..." -ForegroundColor Cyan
kubectl --kubeconfig $KUBECONFIG exec -n $ns $podName `
    -- sh -c "cd /usr/src && git fetch origin $branch" 2>&1 | Out-Null

$checkoutOut = kubectl --kubeconfig $KUBECONFIG exec -n $ns $podName `
    -- sh -c "cd /usr/src && git checkout $branch" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host $checkoutOut -ForegroundColor Red
    Abort "git checkout завершился с ошибкой."
}
Write-Host "OK" -ForegroundColor Green

# ── 7. view:clear ───────────────────────────────────────────────────────────

Write-Host "`n[5/5] view:clear..." -ForegroundColor Cyan
$clearOut = kubectl --kubeconfig $KUBECONFIG exec -n $ns $podName `
    -- sh -c "php /usr/src/artisan view:clear" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARN: view:clear упал (деплой ОК, очисти вручную):" -ForegroundColor Yellow
    Write-Host $clearOut
} else {
    Write-Host "OK" -ForegroundColor Green
}

# ── 8. Финальный отчёт ──────────────────────────────────────────────────────

$finalBranch = (kubectl --kubeconfig $KUBECONFIG exec -n $ns $podName `
    -- sh -c "cd /usr/src && git rev-parse --abbrev-ref HEAD" 2>&1).Trim()
$finalHead   = (kubectl --kubeconfig $KUBECONFIG exec -n $ns $podName `
    -- sh -c "cd /usr/src && git log -1 --oneline" 2>&1).Trim()
$finalStatus = (kubectl --kubeconfig $KUBECONFIG exec -n $ns $podName `
    -- sh -c "cd /usr/src && git status -s" 2>&1) |
    Where-Object { $_ -ne '' }

Write-Host "`n============================================" -ForegroundColor Green
Write-Host " DEPLOY OK" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host " Namespace : $ns"
Write-Host " Pod       : $podName"
Write-Host " Branch    : $finalBranch"
Write-Host " HEAD      : $finalHead"

if ($finalStatus) {
    Write-Host "`n Под-локальные изменения (сохранены):" -ForegroundColor Yellow
    $finalStatus | ForEach-Object { Write-Host "  $_" }
}

$nonViewFiles = $touchedFiles | Where-Object { $_ -notmatch '^resources/views/' -and $_ -notmatch '^public/' }
if ($nonViewFiles) {
    Write-Host "`n WARN: ветка меняет файлы вне views/public — worker/queue могут потребовать ручного рестарта:" -ForegroundColor Yellow
    $nonViewFiles | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
}
Write-Host ""
