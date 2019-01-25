Param (
    [string]$XpandFolder=(Get-Item "$PSScriptRoot\..\..").FullName,
    [string]$DXVersion="0.0.0.0"
)
. "$PSScriptRoot\Utils.ps1"
Push-Location "$XpandFolder"
if ($DXVersion -eq "0.0.0.0"){
    $DXVersion=Get-XpandVersion "$XpandFolder"
}


$installerFolder="$XpandFolder\Build\Installer"
if (test-path $installerFolder){
    Remove-Item $installerFolder -Force -Recurse
}
New-Item -ItemType Directory $installerFolder -Force
$packageFolder ="$XpandFolder\Build\_Package\$DXVersion\"
New-Item -ItemType Directory $packageFolder -Force

#Create Xpand.DLL
New-Item -ItemType Directory -Path "$installerFolder\Xpand.DLL" -Force
Copy-Item -Path ".\Xpand.DLL\Xpand.ExpressApp.ModelEditor.exe" -Destination "$installerFolder\Xpand.DLL\Xpand.ExpressApp.ModelEditor.exe"
Get-ChildItem -Path ".\Xpand.DLL" -Include "*.*" | Where-Object{
    $fullName=$_.FullName
    (("*.dll","*.exe","*.config","*.pdb"|where{$fullName -like $_}).Length -gt 0) -and ($fullName -notlike "*\Plugins\*")
} | 
Copy-Item -Destination "$installerFolder\Xpand.DLL\" -Force
Compress-XFiles -DestinationPath $packageFolder\Xpand-lib-$DXVersion.zip -Path $installerFolder\Xpand.DLL

Copy-Item "$XpandFolder\Xpand.DLL\Plugins\Xpand.VSIX.vsix" "$packageFolder\Xpand.VSIX-$DXVersion.vsix"

$sourceFolder="$installerFolder\Source\"
Get-ChildItem $XpandFolder -recurse -Include "*.*" |where{
    $fullName=$_.FullName
    (("*\Build\Installer*","*\Build\_Package*", "*\.git\*",'*\$RECYCLE.BIN\*',"*\System Volume Information\*","*\packages\*",
    "*\dxbuildgenerator\packages\*","*\_Resharper\*","*\ScreenCapture\*","*.log","*web_view.html","win_view.html",
    "web_view.jpeg","win_view.jpeg","*\Xpand.DLL\*","*.user","*\.vs\*","*.suo","*\bin\*","*\obj\*","*.docstates","*teamcity*","*.gitattributes","*.gitmodules","*.gitignore"|
    where{$fullName -like $_}).Length -eq 0)
} | foreach {CloneItem $_ -TargetDir $sourceFolder -SourceDir $XpandFolder  }
Remove-Item "$sourceFolder\build" -Recurse -Force 
Compress-XFiles -DestinationPath "$installerFolder\Source.zip" -path $sourceFolder 
Remove-Item $sourceFolder -Force -Recurse


Copy-Item "$installerFolder\Source.zip" -Destination "$packageFolder\Xpand-Source-$DXVersion.zip"


& "$XpandFolder\Support\Tool\NSIS\makensis.exe" /DXVERSION=$Version $XpandFolder\Support\Build\Xpand.nsi
Move-Item "$XpandFolder\Support\Build\Setup.exe" -Destination "$installerFolder\eXpandFramework-$DXVersion.exe" -Force
Pop-Location


