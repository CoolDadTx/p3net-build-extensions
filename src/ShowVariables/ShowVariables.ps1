[CmdletBinding()]
param()

function Display
{
    param(
        [string][Parameter(Mandatory=$true)] $msg
    )
    
    if ($logLevel -eq "Debug") {
        Write-VstsTaskDebug $msg    
    } elseif ($logLevel -eq "Verbose") {
        Write-VstsTaskVerbose $msg
    } else {
        Write-Output $msg
    }
}

Trace-VstsEnteringInvocation $MyInvocation

# Get inputs
$logLevel = Get-VstsInput -Name logLevel -Require
$showEmpty = Get-VstsInput -Name showEmpty -AsBool -Require
$message = Get-VstsInput -Name message
$currentPath = $env:SYSTEM_DEFAULTWORKINGDDIRECTORY

try {
    # Display optional message
    if (-not [String]::IsNullOrEmpty($message)) {
        Display $message
    }

    Write-VstsTaskDebug "logLevel = $logLevel"
    Write-VstsTaskDebug "showEmpty = $showEmpty"

    # Display variables
    $count = 0
    $vars = Get-ChildItem env:
    foreach ($var in $vars) {
        if (-not [String]::IsNullOrEmpty($var.Value) -or $showEmpty) {
            Display "$($var.Name) = $($var.Value)"
        }
        $count++    
    }    

    # Set p3net_environmentVariableCount to the # of variables
    Set-VstsTaskVariable -Name "ps3net_environmentVariableCount" -Value $count
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}