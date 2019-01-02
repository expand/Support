Param (
    [string]$XpandFolder=(Get-Item "$PSScriptRoot\..\..").FullName,
    [string]$DXVersion="0.0.0.0"
)
. "$PSScriptRoot\Utils.ps1"
Import-module "$PSScriptRoot\XpandPosh.psm1" -force
Push-Location "$XpandFolder"
if ($DXVersion -eq "0.0.0.0"){
    $DXVersion=Get-XpandVersion "$XpandFolder"
}

Remove-Item "$XpandFolder\Build\" -Recurse -Force
$installerFolder="$XpandFolder\Build\Installer"
New-Item -ItemType Directory $installerFolder
$packageFolder ="$XpandFolder\Build\_Package\$DXVersion\"
New-Item -ItemType Directory $packageFolder

#Create Xpand.DLL
New-Item -ItemType Directory -Path "$installerFolder\Xpand.DLL" -ErrorAction Ignore
Get-ChildItem -Path ".\Xpand.DLL" -Include "*.*" | 
Where-Object{
    $fullName=$_.FullName
    (("*.dll","*.exe","*.config","*.pdb"|where{$fullName -like $_}).Length -gt 0) -and ($fullName -notlike "*\Plugins\*")
} | 
Copy-Item -Destination "$installerFolder\Xpand.DLL\" -Force
Start-Zip $packageFolder\Xpand-lib-$DXVersion.zip $installerFolder\Xpand.DLL
#Copy ModelEditor 
Copy-Item -Path ".\Xpand.DLL\Xpand.ExpressApp.ModelEditor.exe" -Destination "$installerFolder\Xpand.DLL\Xpand.ExpressApp.ModelEditor.exe"
#Copy vsix
Copy-Item "$XpandFolder\Xpand.DLL\Xpand.VSIX.vsix" "$installerFolder\Xpand.VSIX-$DXVersion.vsix"
Copy-Item "$XpandFolder\Xpand.DLL\Xpand.VSIX.vsix" "$packageFolder\Xpand.VSIX-$DXVersion.vsix"

#CreateSourceZip
$sourceFolder="$installerFolder\Source\"
Get-ChildItem $XpandFolder -recurse -Include "*.*" |where{
    $fullName=$_.FullName
    ("*\Build\Installer*","*\Build\_Package*", "*\.git\*",'*\$RECYCLE.BIN\*',"*\System Volume Information\*","*\packages\*",
    "*\dxbuildgenerator\packages\*","*\_Resharper\*","*\ScreenCapture\*","*.log","*web_view.html","win_view.html",
    "web_view.jpeg","win_view.jpeg","*\Xpand.DLL\*","*.user","*\.vs\*","*.suo","*\bin\*","*\obj\*","*.docstates","*teamcity*","*.gitattributes","*.gitmodules","*.gitignore"|
    where{$fullName -like $_}).Length -eq 0
} | foreach {CloneItem $_ -TargetDir $sourceFolder -SourceDir $XpandFolder  }

Start-Zip "$installerFolder\Source.zip" $sourceFolder 
# Remove-Item $sourceFolder -Force -Recurse
Copy-Item "$installerFolder\Source.zip" -Destination "$packageFolder\Xpand-Source-$DXVersion.zip"

#Create installer
& "$XpandFolder\Support\Tool\NSIS\makensis.exe" /DXVERSION=$Version $XpandFolder\Support\Build\Xpand.nsi
Move-Item "$XpandFolder\Support\Build\Setup.exe" -Destination "$packageFolder\eXpandFramework-$DXVersion.exe" -Force

#Copy source



Pop-Location


