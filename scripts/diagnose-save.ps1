<#
.SYNOPSIS
    Diagnose Last Epoch offline character save files.
    Run this when character import fails to get ground-truth data independent of LEB.

.USAGE
    .\diagnose-save.ps1              # List all characters
    .\diagnose-save.ps1 8            # Show details for slot 8
    .\diagnose-save.ps1 -All         # Show details for all slots
#>

param(
    [Parameter(Position=0)] [string] $Slot = "",
    [switch] $All
)

$SaveDir = "$env:USERPROFILE\AppData\LocalLow\Eleventh Hour Games\Last Epoch\Saves"

$ClassNames = @("Primalist", "Mage", "Sentinel", "Acolyte", "Rogue")

$ContainerSlots = @{
    2  = "Helmet"
    3  = "Body Armor"
    4  = "Weapon 1"
    5  = "Weapon 2"
    6  = "Gloves"
    7  = "Belt"
    8  = "Boots"
    9  = "Ring 1"
    10 = "Ring 2"
    11 = "Amulet"
    12 = "Relic"
    29 = "Idol"
    33 = "Fall of the Outcasts"
    34 = "The Stolen Lance"
    35 = "The Black Sun"
    36 = "Blood, Frost, and Death"
    37 = "Ending the Storm"
    38 = "Fall of the Empire"
    39 = "Reign of Dragons"
    43 = "The Last Ruin"
    44 = "The Age of Winter"
    45 = "Spirits of Fire"
    123 = "Idol Altar"
}

$RarityNames = @{
    7 = "Unique"
    8 = "Set"
    9 = "Legendary"
}

$BaseTypeNames = @{
    0  = "Helmet"; 1  = "Body Armor"; 2  = "Belt"; 3  = "Boots"; 4  = "Gloves"
    5  = "1H Axe"; 6  = "Dagger"; 7  = "1H Mace"; 8  = "Sceptre"; 9  = "1H Sword"
    10 = "Wand"; 12 = "2H Axe"; 13 = "2H Mace"; 14 = "2H Spear"; 15 = "2H Staff"
    16 = "2H Sword"; 17 = "Quiver"; 18 = "Shield"; 19 = "Catalyst"; 20 = "Amulet"
    21 = "Ring"; 22 = "Relic"; 23 = "Bow"; 34 = "Blessing"; 41 = "Altar"
}

function Parse-SaveFile($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    # Skip 5-byte "EPOCH" header
    $jsonBytes = $bytes[5..($bytes.Length - 1)]
    $json = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
    return $json | ConvertFrom-Json
}

function Get-RarityLabel($rarity, $data) {
    if ($RarityNames.ContainsKey([int]$rarity)) {
        return $RarityNames[[int]$rarity]
    }
    # Determine by affix count / tier
    $affixCount = 0
    $maxTier = 0
    for ($i = 0; $i -lt 5; $i++) {
        $off = 13 + $i * 3
        if ($data.Count -gt ($off + 1)) {
            $byte0 = $data[$off]
            $byte1 = $data[$off + 1]
            $affixId = $byte1 + ($byte0 % 16) * 256
            if ($affixId -gt 0) {
                $affixCount++
                $tier = [math]::Floor($byte0 / 16)
                if ($tier -gt $maxTier) { $maxTier = $tier }
            }
        }
    }
    if ($maxTier -ge 5) { return "Exalted" }
    if ($affixCount -ge 3) { return "Rare" }
    if ($affixCount -ge 1) { return "Magic" }
    return "Normal"
}

function Show-CharSummary($save, $verbose) {
    $slotNum = [regex]::Match($save.Name, '_(\d+)$').Groups[1].Value
    try {
        $char = Parse-SaveFile $save.FullName
    } catch {
        Write-Host "  [ERROR] Slot $slotNum : Failed to parse: $_" -ForegroundColor Red
        return
    }

    $className  = if ($char.characterClass -ne $null -and $ClassNames[[int]$char.characterClass]) { $ClassNames[[int]$char.characterClass] } else { "Unknown($($char.characterClass))" }
    $league     = if ($char.cycle -gt 0) { "Cycle $($char.cycle)" } else { "Legacy" }
    $lastPlayed = if ($char.lastPlayed) { ([datetime]$char.lastPlayed).ToString("yyyy-MM-dd") } else { "?" }

    Write-Host ""
    Write-Host "=== Slot $slotNum : $($char.characterName) ===" -ForegroundColor Cyan
    Write-Host "  Class   : $className  |  Level: $($char.level)  |  League: $league  |  Last played: $lastPlayed"

    if (-not $verbose) { return }

    # Skills
    Write-Host ""
    Write-Host "  [Skills]" -ForegroundColor Yellow
    if ($char.abilityBar) {
        Write-Host "    Skill bar: $($char.abilityBar -join ', ')"
    }
    if ($char.savedSkillTrees) {
        foreach ($tree in $char.savedSkillTrees) {
            $nodeCount = if ($tree.nodeIDs) { $tree.nodeIDs.Count } else { 0 }
            $totalPts  = if ($tree.nodePoints) { ($tree.nodePoints | Measure-Object -Sum).Sum } else { 0 }
            Write-Host "    $($tree.treeID) : $nodeCount nodes, $totalPts points spent"
        }
    }

    # Passive tree
    if ($char.savedCharacterTree -and $char.savedCharacterTree.nodeIDs) {
        $passivePts = ($char.savedCharacterTree.nodePoints | Measure-Object -Sum).Sum
        Write-Host "    Passive tree: $($char.savedCharacterTree.nodeIDs.Count) nodes, $passivePts points"
    }

    # Equipment
    Write-Host ""
    Write-Host "  [Equipment]" -ForegroundColor Yellow
    $equippedSlots = @{}
    $parseErrors   = 0
    $idolCount     = 0
    $blessingCount = 0

    foreach ($itemEntry in $char.savedItems) {
        $cid  = [int]$itemEntry.containerID
        $data = $itemEntry.data

        if (-not $data) { continue }

        $baseTypeID = [int]$data[3]   # 0-indexed in PS (data[4] in Lua 1-indexed)
        $subTypeID  = [int]$data[4]
        $rarity     = [int]$data[5]

        $slotLabel = if ($ContainerSlots.ContainsKey($cid)) { $ContainerSlots[$cid] } else { "cid=$cid" }
        $baseLabel = if ($BaseTypeNames.ContainsKey($baseTypeID)) { $BaseTypeNames[$baseTypeID] } else { "baseType=$baseTypeID" }

        if ($cid -ge 33 -and $cid -le 45) {
            # Blessing slot
            $blessingCount++
            continue
        }

        if ($cid -eq 29) {
            # Idol
            $idolCount++
            continue
        }

        if ($cid -ge 2 -and $cid -le 12) {
            $rarityLabel = Get-RarityLabel $rarity $data

            if ($rarity -ge 7 -and $rarity -le 9) {
                # Unique/Set/Legendary: read uniqueID
                $uniqueHigh = [int]$data[10]  # data[11] in Lua
                $uniqueLow  = [int]$data[11]  # data[12] in Lua
                $uniqueID   = $uniqueHigh * 256 + $uniqueLow
                $equippedSlots[$slotLabel] = "$rarityLabel  base=$baseLabel  uniqueID=$uniqueID  (baseTypeID=$baseTypeID subTypeID=$subTypeID)"
            } else {
                $equippedSlots[$slotLabel] = "$rarityLabel  base=$baseLabel  (baseTypeID=$baseTypeID subTypeID=$subTypeID)"
            }
        }

        if ($cid -eq 123) {
            $altarSubTypeNames = @("Twisted","Jagged","Skyward","Spire","Carcinised","Visage","Lunar","Ocular","Archaic","Impervious","Prophesied","Pyramidal","Auric")
            $altarName = if ($subTypeID -lt $altarSubTypeNames.Count) { $altarSubTypeNames[$subTypeID] } else { "Unknown($subTypeID)" }
            $equippedSlots["Idol Altar"] = "$altarName Altar"
        }
    }

    foreach ($key in ($equippedSlots.Keys | Sort-Object)) {
        $flag = if ($equippedSlots[$key] -match "baseType=") { " !!UNKNOWN_BASE" } else { "" }
        $color = if ($flag) { "Red" } else { "White" }
        Write-Host ("    {0,-20} : {1}{2}" -f $key, $equippedSlots[$key], $flag) -ForegroundColor $color
    }

    Write-Host "    Idols equipped : $idolCount"
    Write-Host "    Blessings      : $blessingCount"

    # Blessings detail
    if ($blessingCount -gt 0) {
        Write-Host ""
        Write-Host "  [Blessings]" -ForegroundColor Yellow
        foreach ($itemEntry in $char.savedItems) {
            $cid = [int]$itemEntry.containerID
            if ($cid -ge 33 -and $cid -le 45) {
                $slotLabel = if ($ContainerSlots.ContainsKey($cid)) { $ContainerSlots[$cid] } else { "cid=$cid" }
                $d = $itemEntry.data
                if ($d -and $d.Count -ge 8) {
                    $rollByte = [int]$d[7]  # data[8] in Lua = implicitRollByte0
                    $rollFrac = [math]::Round($rollByte / 255.0, 3)
                    Write-Host ("    {0,-30} roll={1}" -f $slotLabel, $rollFrac)
                }
            }
        }
    }

    Write-Host ""
}

# ---- Main ----

if (-not (Test-Path $SaveDir)) {
    Write-Host "Save directory not found: $SaveDir" -ForegroundColor Red
    exit 1
}

$saveFiles = Get-ChildItem "$SaveDir\1CHARACTERSLOT_BETA_*" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '\.bak$' } |
    Sort-Object { [int]([regex]::Match($_.Name, '_(\d+)$').Groups[1].Value) }

if ($saveFiles.Count -eq 0) {
    Write-Host "No save files found in $SaveDir" -ForegroundColor Yellow
    exit 0
}

if ($Slot -ne "") {
    $target = $saveFiles | Where-Object { $_.Name -match "_${Slot}$" }
    if (-not $target) {
        Write-Host "Slot $Slot not found. Available slots:" -ForegroundColor Red
        foreach ($f in $saveFiles) {
            $n = [regex]::Match($f.Name, '_(\d+)$').Groups[1].Value
            Write-Host "  Slot $n : $($f.Name)"
        }
        exit 1
    }
    Show-CharSummary $target $true
} elseif ($All) {
    foreach ($f in $saveFiles) { Show-CharSummary $f $true }
} else {
    # List mode: show one-liner per character
    Write-Host ""
    Write-Host "Last Epoch Save Files - $SaveDir" -ForegroundColor Cyan
    Write-Host ("-" * 70)
    Write-Host ("  {0,-6} {1,-24} {2,-5} {3,-12} {4}" -f "Slot", "Name", "Level", "Class", "League")
    Write-Host ("-" * 70)
    foreach ($f in $saveFiles) {
        $slotNum = [regex]::Match($f.Name, '_(\d+)$').Groups[1].Value
        try {
            $char = Parse-SaveFile $f.FullName
            $className = if ($char.characterClass -ne $null -and $ClassNames[[int]$char.characterClass]) { $ClassNames[[int]$char.characterClass] } else { "Unknown" }
            $league    = if ($char.cycle -gt 0) { "Cycle $($char.cycle)" } else { "Legacy" }
            Write-Host ("  {0,-6} {1,-24} {2,-5} {3,-12} {4}" -f $slotNum, $char.characterName, $char.level, $className, $league)
        } catch {
            Write-Host ("  {0,-6} [PARSE ERROR: $_]" -f $slotNum) -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "  Usage: .\diagnose-save.ps1 <slot>   (e.g. .\diagnose-save.ps1 8)"
    Write-Host "         .\diagnose-save.ps1 -All      (show all details)"
    Write-Host ""
}
