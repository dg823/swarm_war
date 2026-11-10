# SWARM WAR 자체 검증 실행기 (Windows PowerShell 5.1+)
#
# 저장소의 스케치 폴더를 임시 폴더에 복사한 뒤, 복사본의 Config.pde에서 SELFTEST를 true로 바꿔 Processing CLI로 실행한다.
# 저장소 파일은 절대 수정하지 않는다.
#
# 사용 예:
#   .\tools\run_selftest.ps1 -Only part1        # 진화 실험을 뺀 T1~T13
#   .\tools\run_selftest.ps1 -Only part2        # T15~T24 + 렌더 성능
#   .\tools\run_selftest.ps1 -Only evo          # 환경별 진화 실험 (약 8분)
#   .\tools\run_selftest.ps1 -Only perf         # 렌더 성능만 (best-of-5)
#   .\tools\run_selftest.ps1 -Only balance      # 4분 생태계 균형
#   .\tools\run_selftest.ps1                    # 전부 (10분 넘게 걸린다)
#
# -Only 값: part1, part2, evo, noevo, balance, duels, genetics, inv, perf, final, v05, shots, renderprof, dbg
#           (빈 값이면 전체. 스크린샷 shot_*.png 은 임시 폴더에 저장된다)
#
# 주의
#  - 한 번에 10분을 넘기는 명령은 도구에 따라 중단될 수 있으니 part1 / part2 / evo 로 나눠 돌린다.
#  - 같은 -Work 를 쓰는 두 실행을 동시에 돌리지 말 것 (서로의 복사본을 지운다). 병렬로 돌리려면 -Tag 를 다르게 준다.
#  - 경로에 [ ] 같은 문자가 있으면 PowerShell이 와일드카드로 해석하므로 -LiteralPath 를 쓴다 (이 스크립트는 이미 그렇게 한다).

param(
  [string]$Only = "",
  [string]$Tag = "run",
  [string]$Processing = "C:\Program Files\Processing\Processing.exe",
  [string]$Sketch = ((Get-Item -LiteralPath (Join-Path $PSScriptRoot "..")).FullName),
  [string]$WorkRoot = (Join-Path $env:TEMP "swarm_war_selftest")
)

$ErrorActionPreference = "Continue"
if (-not (Test-Path -LiteralPath $Processing)) { throw "Processing 실행 파일을 찾을 수 없습니다: $Processing  (-Processing 로 경로를 지정하세요)" }

# Processing 스케치는 '폴더 이름 = 메인 .pde 이름'이어야 하므로 복사본 폴더 이름도 swarm_war 로 맞춘다.
$work = Join-Path $WorkRoot $Tag
$dst = Join-Path $work "swarm_war"
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force $dst | Out-Null
Get-ChildItem -LiteralPath $Sketch -Filter *.pde | Copy-Item -Destination $dst

$cfg = Join-Path $dst "Config.pde"
$t = [System.IO.File]::ReadAllText($cfg)
$t = $t.Replace("final boolean SELFTEST = false;", "final boolean SELFTEST = true;")
if ($Only -ne "") { $t = $t.Replace('final String SELFTEST_ONLY = "";', 'final String SELFTEST_ONLY = "' + $Only + '";') }
[System.IO.File]::WriteAllText($cfg, $t, (New-Object System.Text.UTF8Encoding($false)))

$out = Join-Path $work "out"
& $Processing cli --sketch="$dst" --output="$out" --force --run 2>&1 |
  Where-Object { $_ -notmatch "NativeCommandError|CategoryInfo|FullyQualifiedErrorId|At line:|^\s*\+|AWT|display count" }

Write-Host ""
Write-Host "스크린샷/로그 폴더: $dst"
Get-ChildItem -LiteralPath $dst -Filter *.png -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
