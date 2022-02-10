# - WSUS + WID db Server Setup.
# - M.Balzan CRSP Consultant (Jan 2022)

# --| If we are running as a 32-bit process on an x64 system, re-launch as a 64-bit process
if ("$env:PROCESSOR_ARCHITEW6432" -ne "ARM64")
{
    if (Test-Path "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe")
    {
        & "$($env:WINDIR)\SysNative\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy bypass -NoProfile -File "$PSCommandPath"
        Exit $lastexitcode
    }
}

$Logfile = "C:\wsus.log"
function LogWrite
{
   Param ([string]$logstring)
   If (Test-Path $Logfile -ErrorAction SilentlyContinue)
   {
   If ((Get-Item $Logfile).Length -gt 2MB)
   {
   Rename-Item $Logfile $Logfile".bak" -Force
   }
   }
   $WriteLine = (Get-Date).ToString() + " | " + $logstring
   Add-content $Logfile -value $WriteLine
   Write-Host $WriteLine
}

# Create the secure SSL channel
Log-Write "Enabling connection over TLS for better compability on servers" -ForegroundColor Green
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

LogWrite "WSUS SETUP"
LogWrite "----------"
LogWrite "."

LogWrite "Downloading dependencies..."

# - Download Report Viewer files.
$url  = "http://go.microsoft.com/fwlink/?LinkID=239644&clcid=0x409"
$download  = "$env:USERPROFILE\Desktop\SQLSysClrTypes.msi"
Invoke-WebRequest -Uri $url -OutFile $download
LogWrite "SQLsysClrTypes downloaded."


$url2 = "https://download.microsoft.com/download/F/B/7/FB728406-A1EE-4AB5-9C56-74EB8BDDF2FF/ReportViewer.msi"
$download2 = "$env:USERPROFILE\Desktop\ReportViewer.msi"
Invoke-WebRequest -Uri $url2 -OutFile $download2
LogWrite "Report Viewer downloaded."

LogWrite "Installing SQLSysClrTypes..."
Start-Process -FilePath msiexec -ArgumentList "/i $download -qn" -Wait

LogWrite "Installing Report Viewer..."
Start-Process -FilePath msiexec -ArgumentList "/i $download2 -qn" -Wait

LogWrite "..."
# - Install WSUS role, services, WID DB, console and content directory.

LogWrite "Installing WSUS for WID (Windows Internal Database)"
Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

LogWrite "..."

# - Initialise disk F for WSUS content.

$driveletter = [char]"F"
LogWrite "Initialising new drive F:"

Get-Disk | Where-Object partitionstyle -eq raw |
    Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -DriveLetter $driveletter -UseMaximumSize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "WSUS" -Confirm:$false

Logwrite "."

LogWrite "Adding new WSUS folder to drive F:"
New-Item -Name WSUS -Type Directory -Path F:\ -Force

Logwrite "."
# - Run WSUS Post Install configuration.
LogWrite "Running Post Install task..."

Set-Location "C:\Program Files\Update Services\Tools"

.\wsusutil.exe postinstall CONTENT_DIR=F:\WSUS

LogWrite "..."
# - Set the Private Memory Limit (KB) for the WSUS Application Pool to 0 (zero).
LogWrite "Applying IIS Web configurations (WSUS Pool Memory & Max Processes)..."
Set-WebConfiguration "/system.applicationHost/applicationPools/add[@name='WsusPool']/recycling/periodicRestart/@privateMemory" -Value 0

# - Set maximum number of worker processes to 0 (unlimited) and reset IIS.
Set-WebConfiguration -Filter "/system.applicationHost/applicationPools/add[@name='WsusPool']/processModel/@maxProcesses" -Value 0

LogWrite "Restarting IIS..."
start-process iisreset

LogWrite "."
# - Set WSUS vars

$WSUS = Get-WsusServer
$WSUSConfig = $wsus.GetConfiguration()

#Set to download updates from Microsoft Updates
LogWrite "Set WSUS to sync from MU."
Set-WsusServerSynchronization -SyncFromMU


# - Set update languages to English and save configuration settings
LogWrite "Set WSUS languages to: English."
$WSUSConfig.AllUpdateLanguagesEnabled = $false           
$WSUSConfig.SetEnabledUpdateLanguages("en")           
$WSUSConfig.Save()

# Create computer target groups
LogWrite "Adding target computer groups..."

$WSUS.CreateComputerTargetGroup("Windows Server 2012 R2") | Out-Null

$WSUS.CreateComputerTargetGroup("Windows Server 2016") | Out-Null

$WSUS.CreateComputerTargetGroup("Windows Server 2019") | Out-Null

$WSUS.CreateComputerTargetGroup("Windows 10") | Out-Null


# - Get WSUS subscription and perform initial synchronization to get latest categories
LogWrite "Syncing categories/products only..."
Logwrite "."



$subscription = $WSUS.GetSubscription()
$subscription.StartSynchronizationForCategoryOnly()



<# While ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {

    if ((Get-ChildItem -Path 'C:\Windows\WID\Data\SUSDB.mdf').length -lt 1GB) 
    
    {$SUSDB = (Get-ChildItem -Path 'C:\Windows\WID\Data\SUSDB.mdf').length/1MB; $size = "MB"} 
    
    else {$SUSDB = (Get-ChildItem -Path 'C:\Windows\WID\Data\SUSDB.mdf').length/1GB; $size = "GB"}

    $SUSDBtrun = [math]::Round($SUSDB)

    Write-Host -NoNewline "`rSync status: $($subscription.GetSynchronizationStatus()) | SUSDB size: $SUSDBtrun $size"
    
    Start-Sleep -seconds 5  

} 

Write-Progress -Activity 


LogWrite "."
LogWrite "Categories sync complete!"
LogWrite "..."


# - Set the Products that we want WSUS to receive updates from.
LogWrite "Setting WSUS Products..."

$prods = @( "Windows Server 2016",
            "Windows Server Manager - Windows Server Update Services (WSUS) Dynamic Installer",
            "Windows Server 2019"
            ) 
        
foreach($prod in $prods) {
        
"Adding product: $prod"

Get-WsusProduct  | Where-Object { $_.Product.Title -eq $prod } | Set-WsusProduct 

} 
""
# - Set the Classifications
LogWrite "Setting WSUS Classifications..."


Get-WsusClassification | Where-Object {

    $_.Classification.Title -in (

    'Security Updates',

    'Critical Updates'
    )

} | Set-WsusClassification

Get-WsusClassification | Where-Object {

    $_.Classification.Title -in (

    'Definition Updates'

    )

} | Set-WsusClassification -Disable

$Classes = ($WSUS.GetSubscription().GetUpdateClassifications()).title

LogWrite "Classifications Set: $Classes"





# - Set synchronizations
LogWrite "Setting WSUS schedule configurations..."
$subscription.SynchronizeAutomatically=$true

# - Set synchronization schedule for midnight each night

$subscription.SynchronizeAutomaticallyTimeOfDay = (New-TimeSpan -Hours 0)
$subscription.NumberOfSynchronizationsPerDay = 1
$subscription.Save()


# - Start the main sync and display sync progress.
$subscription.StartSynchronization()

<#
LogWrite "."
LogWrite "Starting WSUS Sync, be aware this will take some time!" -ForegroundColor Magenta
LogWrite "..."
Start-Sleep -Seconds 20 # Wait for sync to start before monitoring

while ($subscription.GetSynchronizationStatus() -ne 'NotProcessing') {

    if ($wsus.GetSubscription().GetSynchronizationProgress().ProcessedItems -eq 0) { $percent = "" }
    else
    {$per = [math]::Round(($wsus.GetSubscription().GetSynchronizationProgress().ProcessedItems / $wsus.GetSubscription().GetSynchronizationProgress().TotalItems)*100)
    
    $percent = "$per%"
    switch ($per) {
        10  {$bar = "[o---------]   " }
        20  {$bar = "[oo--------]   " }
        30  {$bar = "[ooo-------]   " }
        40  {$bar = "[oooo------]   " }
        50  {$bar = "[ooooo-----]   " }
        60  {$bar = "[oooooo----]   " }
        70  {$bar = "[ooooooo---]   " }
        80  {$bar = "[oooooooo--]   " }
        90  {$bar = "[ooooooooo-]   " }
        100 {$bar = "[oooooooooo]   " }
        
    }
}

    if ((Get-ChildItem -Path 'C:\Windows\WID\Data\SUSDB.mdf').length -lt 1GB) 
    
    {$SUSDB = (Get-ChildItem -Path 'C:\Windows\WID\Data\SUSDB.mdf').length/1MB; $size = "MB"} 
    
    else {$SUSDB = (Get-ChildItem -Path 'C:\Windows\WID\Data\SUSDB.mdf').length/1GB; $size = "GB"}

    $SUSDBtrun = [math]::Round($SUSDB)

    Write-Host -NoNewline "`rSync status: $($subscription.GetSynchronizationStatus()) | SUSDB size: $SUSDBtrun $size | Complete: $percent $bar"
    Start-Sleep -seconds 10  

}

Logwrite "."
LogWrite "WSUS sync completed!" -ForegroundColor Green
LogWrite "."
#>




#$CGS = ($WSUS.GetComputerTargetGroups()).Name
#>

LogWrite "WSUS setup complete! (Log is located at: $Logfile)"
LogWrite "--------------------------------------------------"


<# Report Summary of WSUS setup...

$Products = ($WSUS.GetSubscription().GetUpdateCategories()).title
$Classes  = ($WSUS.GetSubscription().GetUpdateClassifications()).title
$CGS      = ($WSUS.GetComputerTargetGroups()).Name
$TU       = $WSUS.GetUpdateCount()

$ConnectionString = 'server=\\.\pipe\MICROSOFT##WID\tsql\query;database=SUSDB;trusted_connection=true;'
$SQLConnection= New-Object System.Data.SQLClient.SQLConnection($ConnectionString)
$SQLConnection.Open()
$SQLCommand = $SQLConnection.CreateCommand()
$SQLCommand.CommandText = "Select count(*) from PUBLIC_VIEWS.vUpdate where MsrcSeverity='Critical'"
$SqlDataReader = $SQLCommand.ExecuteReader()
$SQLDataResult = New-Object System.Data.DataTable
$SQLDataResult.Load($SqlDataReader)
$SQLConnection.Close()
$SQLDataResult

$PD       = @($Products)
$CL       = @($Classes)
$TG       = @($CGS)
$STATS    = @("Total Updates: $TU","Total Critical: $SQLDataResult","SUSDB Size: $SUSDBtrun")
$CONFIGS  = @("Name: $($wsus.Name)","Port: $($wsus.PortNumber)","Language: $($wsus.PreferredCulture)")


[int]$max = $PD.Count

if ([int]$PD.count) { $max = $CONFIGS.Count; }
 
$Results = for ( $i = 0; $i -lt $max; $i++)
{
    Write-Verbose "$($PD[$i]),$($CL[$i]),$($TG[$i]),$($STATS[$i]),$($CONFIGS[$i])"
    
    [PSCustomObject]@{
        
        Products        = $PD[$i]
        Classes         = $CL[$i]
        "Target Groups" = $TG[$i]
        Statistics      = $STATS[$i]
        Configuration   = $CONFIGS[$i]

 
    }
}

Logwrite $Results | Format-Table *

# - end
#>
