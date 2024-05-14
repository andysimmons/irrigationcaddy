[CmdletBinding()]
param (
    [string]
    $hostname = "sprinklers",

    [int]
    [ValidateRange(1,4)]
    $Program = 1,

    [switch]
    $StopSystem,

    [switch]
    $CheckStatus
)

<#
1 - (seems like a broken port)
2 15 (raised beds)
3 24 (north and east back lawn)
4 26 (southwest back lawn)
5 25 (west side of house lawn)
6 0 (garden hose near door)
7 24 (garden hose by box)
8 - (broken brown wire front box - formerly west front lawn)
9 30 (center front lawn)
10 25 (west front lawn and flower beds)

program.htm?doProgram=1&runNow=1&pgmNum=1

&z1durHr=0&z1durMin=0
&z2durHr=0&z2durMin=15
&z3durHr=0&z3durMin=24
&z4durHr=0&z4durMin=26
&z5durHr=0&z5durMin=25
&z6durHr=0&z6durMin=0
&z7durHr=0&z7durMin=24
&z8durHr=0&z8durMin=0
&z9durHr=0&z9durMin=30


&runNow=1&pgmNum=4
#>
#region Functions
Function Start-Countdown {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [Int] $Seconds = 10,

        [string] $Activity = "Countdown",
        
        [String] $Message = "Zone complete!"
    )
    
    $stopwatch = [system.diagnostics.stopwatch]::StartNew()
    $escKey = 27
    $abort = $false

    $origActivity = $Activity 
    $Activity = "$Activity (ESC to abort)"
    
    while ($stopwatch.Elapsed.TotalSeconds -lt $Seconds) {
        if ($host.ui.RawUi.KeyAvailable) {
            $key = $host.ui.RawUI.ReadKey("NoEcho,IncludeKeyUp")

            if ($key.VirtualKeyCode -eq $escKey) {
                # ESC pressed, abort countdown
                $abort = $true
                $Seconds = 0
                continue
            }
        }
    
        $percent = ($stopwatch.Elapsed.TotalSeconds / $Seconds) * 100
         
        # abort logic messes with percent calculation in some cases
        if ($percent -gt 100) { $percent = 100 }
        if ($percent -lt 0) { $percent = 0}

        $secRemaining = [math]::Max(($Seconds - $stopwatch.Elapsed.TotalSeconds), 0)
        Write-Progress -Activity $Activity -SecondsRemaining $secRemaining -Status "Time Remaining" -PercentComplete $percent
        Start-Sleep -Seconds 1
    }
    
    Write-Progress -Completed -Activity $Activity
    
    if ($Abort) {
        Write-Warning "$origActivity aborted!"
    }
}

function Get-Status {
    (Invoke-WebRequest -Uri http://${hostname}/status.json -Method GET).Content | ConvertFrom-Json
}

function Stop-Sprinklers {
    [CmdletBinding()]
    param ()

    Write-Verbose "Turning sprinkler system OFF"
    $postParams = @{ stop = 'off' }
    Invoke-WebRequest -Uri http://${hostname}/stopSprinklers.htm -Method POST -body $postParams | Out-String | Write-Verbose
}

function Start-Sprinklers {
    [CmdletBinding()]
    param ()

    Write-Verbose "Turning sprinkler system ON"
    $postParams = @{ run = 'run' }
    Invoke-WebRequest -Uri http://${hostname}/runSprinklers.htm -Method POST -body $postParams | Out-String | Write-Verbose
}

function Start-Program {
    [CmdletBinding()]
    param (
        [ValidateRange(1, 4)]
        [int] $Program = 1
    )

    Write-Verbose "Starting program $Program"
    $postParams = @{
        doProgram = 1
        runNow    = 1
        pgmNum    = $Program
    }
    Invoke-WebRequest -Uri http://${hostname}/program.htm -Method POST -Body $postParams
}
#endregion Functions

#region init
if ($CheckStatus) { 
    Get-Status
    exit 0
}

if ($StopSystem) {
    Stop-Sprinklers
    Get-Status
    exit 0
}

# Reset sprinklers
Stop-Sprinklers
Start-Sprinklers
#endregion init

#region main
# Start the program
Start-Program -Program $Program

$status = Get-Status

if (!$status.Running) {
    Write-Warning "Nothing is running... do you have any zones enabled in program $Program?"
    $status | Out-String | Write-Warning
}

# as long as we have a zone running, handle timekeeping and advance to next zone on schedule
while ($status.running) {
    Write-Output "*** STATUS: $(Get-Date) ***"
    Write-Output $status

    # Irrigation Caddy timer is busted, we'll use the computer clock for zone timeout
    $zoneSecLeft = $status.ZoneSecLeft
    
    Start-Countdown -Seconds $zoneSecLeft -Activity "Zone $($status.zoneNumber)"
    $postParams = @{ stop = 'active' }
    Invoke-WebRequest -Uri http://${hostname}/stopSprinklers.htm -Method POST -Body $postParams | Out-String | Write-Verbose

    # give it a sec to update status internally
    Start-Sleep -Seconds 1
    $status = Get-Status
}
#endregion main
