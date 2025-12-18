<#
.SYNOPSIS
Shared module for creating backup archives with configurable compression

.DESCRIPTION
Provides reusable function for creating zip archives that include hidden files,
preserve folder structure (including empty directories), and support configurable compression.

.PARAMETER SourcePath
Path to the directory to archive

.PARAMETER ArchivePath
Full path where the archive should be created

.PARAMETER CompressionLevel
Compression level: NoCompression, Fastest, or Optimal

.EXAMPLE
Import-Module "$PSScriptRoot\BackupArchive.psm1" -Force
New-BackupArchive -SourcePath $persistDir -ArchivePath $archivePath -CompressionLevel "NoCompression"
#>

function New-BackupArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [string]$ArchivePath,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("NoCompression", "Fastest", "Optimal")]
        [string]$CompressionLevel
    )
    
    # Load compression classes (order matters - load Compression first)
    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    
    # Map compression level string to CompressionLevel enum
    $compressionEnum = switch ($CompressionLevel) {
        "NoCompression" { [System.IO.Compression.CompressionLevel]::NoCompression }
        "Fastest" { [System.IO.Compression.CompressionLevel]::Fastest }
        "Optimal" { [System.IO.Compression.CompressionLevel]::Optimal }
        default { [System.IO.Compression.CompressionLevel]::Optimal }
    }
    
    # Get parent directory to preserve folder structure
    $parentDir = Split-Path -Parent $SourcePath
    $parentDirLength = $parentDir.Length
    
    # Remove existing archive if it exists
    if (Test-Path $ArchivePath) {
        Remove-Item $ArchivePath -Force
    }
    
    # Create zip archive
    $zip = [System.IO.Compression.ZipFile]::Open($ArchivePath, [System.IO.Compression.ZipArchiveMode]::Create)
    
    try {
        # Get all files and directories including hidden ones
        $allFiles = Get-ChildItem -Path $SourcePath -Recurse -Force -File -ErrorAction SilentlyContinue
        $allDirs = Get-ChildItem -Path $SourcePath -Recurse -Force -Directory -ErrorAction SilentlyContinue
        
        if ($null -eq $allFiles) { $allFiles = @() }
        if ($null -eq $allDirs) { $allDirs = @() }
        
        if ($allFiles.Count -eq 0 -and $allDirs.Count -eq 0) {
            Write-Host "[*] No files or folders found to archive."
            return @{ FileCount = 0; DirCount = 0 }
        }
        
        $fileCount = 0
        $dirCount = 0
        
        # Add all directories first (including empty ones) to preserve structure
        foreach ($dir in $allDirs) {
            $relativePath = $dir.FullName.Substring($parentDirLength + 1)
            $entryName = ($relativePath -replace '\\', '/') + '/'
            $null = $zip.CreateEntry($entryName, $compressionEnum)
            $dirCount++
        }
        
        # Add all files
        foreach ($file in $allFiles) {
            $relativePath = $file.FullName.Substring($parentDirLength + 1)
            $entryName = $relativePath -replace '\\', '/'
            
            $entry = $zip.CreateEntry($entryName, $compressionEnum)
            $entryStream = $entry.Open()
            
            try {
                $fileStream = [System.IO.File]::OpenRead($file.FullName)
                try {
                    $fileStream.CopyTo($entryStream)
                } finally {
                    $fileStream.Close()
                }
            } finally {
                $entryStream.Close()
            }
            
            $fileCount++
        }
        
        return @{
            FileCount = $fileCount
            DirCount = $dirCount
        }
    } finally {
        $zip.Dispose()
    }
}

Export-ModuleMember -Function @(
    'New-BackupArchive'
)
