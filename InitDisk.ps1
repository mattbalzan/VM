$disks = Get-Disk | Where partitionstyle -eq 'raw' | sort number

$disk | Initialize-Disk -PartitionStyle MBR -PassThru |
        New-Partition -UseMaximumSize -DriveLetter F |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel "WSUS" -Confirm:$false -Force
