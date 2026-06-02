Add-Type -AssemblyName System.Windows.Forms

# Function to convert Windows path to POSIX path
function Get-UnixPath {
    param([string]$Path)
    $posixPath = $Path -replace '\\', '/'
    $posixPath = $posixPath -replace '^([A-Z]):/', '/$1/'
    $posixPath
}

$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = $args[0]
$dialog.Multiselect = $false

$dialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)

$result = $dialog.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    # Convert the Windows path to POSIX path
    $posixPath = Get-UnixPath -Path $dialog.FileName
    Write-Output $posixPath
}
