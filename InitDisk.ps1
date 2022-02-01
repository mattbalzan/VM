$driveletter = [char]"F"

Get-Disk | Where-Object partitionstyle -eq raw |
    Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -DriveLetter $driveletter -UseMaximumSize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "WSUS" -Confirm:$false
