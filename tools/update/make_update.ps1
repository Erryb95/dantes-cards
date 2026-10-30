# Builds a release with in-game updates (docs/BUILD.md, "Updates"). Run it from the main checkout (it needs
# config/online.local.cfg, which every build ships) after bumping the version in project.godot and in the Android
# preset (version/name, version/code). It never publishes anything: it prints the `gh release create` line.
#
#   powershell -ExecutionPolicy Bypass -File tools/update/make_update.ps1 [-Bases 0.9.4,0.9.5] [-FullRequired -Reason "..."]
#       [-SkipExport] [-AllowRisky] [-Key C:/Servers/dantes_update_key.pem]
#
# 1. Exports the full Windows exe (release) and Android APK (debug), unless -SkipExport (then the ones in build/ are used).
# 2. Keeps them as this version's base in build/update_bases/<version>/ (exe, apk, android.pck made from the APK,
#    base.json with the commit and engine), so later releases can patch over it. Back this folder up: without a
#    version's base, its players are offered the full download instead of a patch.
# 3. For every earlier base (-Bases, or all of build/update_bases/): exports a patch per platform with only the files
#    that changed since it (godot --export-patch), unless the engine changed or project.godot / export_presets.cfg /
#    the update boot / the update key changed in more than the version lines (those need a full download; -AllowRisky
#    patches anyway). Each patch is cumulative: one download takes a player from that base to this version.
# 4. Writes build/release/<version>/: the two full downloads, the patches and update.json (signed with -Key, checked
#    with the committed public key).
param(
	[string[]]$Bases = @(),
	[switch]$FullRequired,
	[string]$Reason = "",
	[switch]$SkipExport,
	[switch]$AllowRisky,
	[string]$Key = "C:/Servers/dantes_update_key.pem",
	[string]$Godot = "C:/Progetti/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot/../..").Path
Set-Location $root

function Invoke-Godot([string]$GodotArgs, [int]$TimeoutSec, [string]$Log) {
	# Every Godot run has a timeout; on one, only this process (by its PID) is stopped.
	$p = Start-Process -FilePath $Godot -ArgumentList $GodotArgs -NoNewWindow -PassThru `
		-RedirectStandardOutput $Log -RedirectStandardError "$Log.err"
	$null = $p.Handle # makes ExitCode readable after the wait
	if (-not $p.WaitForExit($TimeoutSec * 1000)) {
		Stop-Process -Id $p.Id -Force
		throw "Godot timed out after $TimeoutSec s: $GodotArgs (log: $Log)"
	}
	if ($p.ExitCode -ne 0) { throw "Godot failed ($($p.ExitCode)): $GodotArgs (log: $Log, $Log.err)" }
}

function Invoke-Tool([string]$ToolArgs, [string]$Log) {
	Invoke-Godot "--headless --path . -s res://tools/update/update_tool.gd -- $ToolArgs" 600 $Log
	Get-Content $Log | Where-Object { $_ -match '^(apk-base|check|manifest|verify|pck-list|  )' } | ForEach-Object { Write-Host $_ }
}

# --- what is being released
$version = (Select-String -Path project.godot -Pattern 'config/version="([^"]+)"').Matches[0].Groups[1].Value
$code = (Select-String -Path export_presets.cfg -Pattern 'version/code=(\d+)').Matches[0].Groups[1].Value
$apkName = (Select-String -Path export_presets.cfg -Pattern 'version/name="([^"]+)"').Matches[0].Groups[1].Value
if ($apkName -ne $version) { throw "export_presets.cfg version/name is $apkName, project.godot says $version" }
if (-not (Test-Path config/online.local.cfg)) { throw "config/online.local.cfg is missing: build from the checkout that has it (a patch without it would delete it from the players' game)" }
if (-not (Test-Path config/update_public_key.pem)) { throw "config/update_public_key.pem is missing" }
if (-not (Test-Path $Key)) { throw "the signing key is not at $Key" }
$engine = ((& $Godot --version) -split '\.')[0..2] -join '.'
$commit = (git rev-parse HEAD).Trim()
if (git status --porcelain --untracked-files=no) { Write-Warning "uncommitted changes: they ship, but base.json records $commit" }
$logs = "build/update_logs"
New-Item -ItemType Directory -Force $logs, build/windows, build/android | Out-Null
Write-Host "Release $version (Android code $code), engine $engine, commit $commit"

# --- 1. the full builds
$exe = "build/windows/DantesInfernoCards.exe"
$apk = "build/android/DantesInfernoCards.apk"
if (-not $SkipExport) {
	Invoke-Godot "--headless --path . --import" 1200 "$logs/import.log"
	Invoke-Godot "--headless --path . --export-release `"Windows Desktop`" $exe" 1200 "$logs/export_win.log"
	Invoke-Godot "--headless --path . --export-debug `"Android`" $apk" 1200 "$logs/export_android.log"
}
foreach ($f in $exe, $apk) { if (-not (Test-Path $f)) { throw "$f is missing" } }

# --- 2. this version's base
$mine = "build/update_bases/$version"
New-Item -ItemType Directory -Force $mine | Out-Null
Copy-Item $exe "$mine/DantesInfernoCards.exe" -Force
Copy-Item $apk "$mine/DantesInfernoCards.apk" -Force
Invoke-Tool "apk-base --apk=$mine/DantesInfernoCards.apk --out=$mine/android.pck" "$logs/apk_base_$version.log"
@{ version = $version; engine = $engine; commit = $commit; code = [int]$code } | ConvertTo-Json | Set-Content "$mine/base.json" -Encoding utf8

# --- 3. the patches
$rel = "build/release/$version"
if (Test-Path $rel) { Remove-Item -Recurse -Force $rel }
New-Item -ItemType Directory -Force $rel | Out-Null
if ($Bases.Count -eq 0) {
	$Bases = Get-ChildItem build/update_bases -Directory | Where-Object { $_.Name -ne $version } | ForEach-Object { $_.Name }
}
$guarded = @("project.godot", "export_presets.cfg", "scripts/core/update_boot.gd", "config/update_public_key.pem")
$versionLine = '^[+-]\s*(config/version|version/code|version/name|application/file_version|application/product_version|application/short_version|application/version)='
$made = 0
if (-not $FullRequired) {
	foreach ($b in $Bases) {
		$bd = "build/update_bases/$b"
		if (-not (Test-Path "$bd/base.json")) { Write-Warning "no base for $b in $($bd): skipped"; continue }
		$info = Get-Content "$bd/base.json" -Raw | ConvertFrom-Json
		if ($info.engine -ne $engine) { Write-Warning "$b was built with Godot $($info.engine): its players need the full download"; continue }
		$diff = git diff $info.commit -- $guarded | Where-Object { $_ -match '^[+-]' -and $_ -notmatch '^(\+\+\+|---)' -and $_ -notmatch $versionLine }
		if ($diff -and -not $AllowRisky) {
			Write-Warning "since $b these changed and need a full download (-AllowRisky to patch anyway):"
			$diff | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" }
			continue
		}
		foreach ($t in @(@("Windows Desktop", "windows", "$bd/DantesInfernoCards.exe"), @("Android", "android", "$bd/android.pck"))) {
			if (-not (Test-Path $t[2])) { Write-Warning "$($t[2]) is missing: no $($t[1]) patch over $b"; continue }
			$out = "$rel/patch-$b-to-$version-$($t[1]).pck"
			Invoke-Godot "--headless --path . --export-patch `"$($t[0])`" $out --patches $($t[2])" 1200 "$logs/patch_$($b)_$($t[1]).log"
			Invoke-Tool "check --pck=$out" "$logs/check_$($b)_$($t[1]).log"
			$made++
		}
	}
}

# --- 4. the release folder and its signed manifest
Compress-Archive -Path $exe -DestinationPath "$rel/DantesInfernoCards-win.zip" -Force
Copy-Item $apk "$rel/DantesInfernoCards-android.apk"
$full = if ($FullRequired) { " --full-required --reason=`"$Reason`"" } else { "" }
Invoke-Tool "manifest --dir=$rel --version=$version --code=$code --key=$Key$full" "$logs/manifest.log"
Invoke-Tool "verify --in=$rel/update.json" "$logs/verify.log"

Write-Host ""
Write-Host "Release folder: $rel ($made patches)"
Get-ChildItem $rel | ForEach-Object { Write-Host ("  {0,10:N1} MB  {1}" -f ($_.Length / 1MB), $_.Name) }
Write-Host ""
Write-Host "To publish (update.json must be in every release, the game reads the latest one):"
$files = (Get-ChildItem $rel | ForEach-Object { "$rel/$($_.Name)" }) -join " "
Write-Host "  gh release create v$version $files --title `"v$version`" --notes `"...`""
