Framework "4.6"

properties {
    $version = $null
    $msbuild = $null
    $root = (Get-Item "$PSScriptRoot\..\..").FullName
    $clean=$false
    $configuration=$null
    $verbosity=$null
    $msbuildArgs=$null
    $throttle=1
    $packageSources=$null
    $dxPath=$null
}

Task Release  -depends  Clean,Init,Version,RestoreNuget, CompileModules,CompileDemos,VSIX ,BuildExtras,IndexSources,VSIX, Finalize,Installer

Task Init  {
    InvokeScript{
        "$root\Xpand.dll","$root\Build","$root\Build\Temp","$root\Support\_third_party_assemblies\Packages\" | ForEach-Object{
            New-Item $_ -ItemType Directory -Force |Out-Null
        }
        Get-ChildItem "$root\support\_third_party_assemblies\" -Recurse  | ForEach-Object{
            Copy-Item $_.FullName "$root\Xpand.dll\$($_.FileName)" -Force
        }
    
        $r=New-Command "Nuget" "$root\support\tool\nuget.exe" "restore $root\Support\BuildHelper\BuildHelper.sln -PackagesDirectory $root\Support\_third_party_assemblies\Packages"
        if ($r.ExitCode){
            throw $r.stderr
        }
        $r.stdout
        Start-Build $msbuild (GetBuildArgs "$root\Support\BuildHelper\BuildHelper.sln")
        & $root/Xpand.dll/BuildHelper.exe 
    
        
        Get-ChildItem "$root" "*.csproj" -Recurse|ForEach-Object {
            [xml]$xml=Get-Content $_.FullName
            $xml.Project.PropertyGroup|ForEach-Object{
                if ($_.CodeAnalysisRuleSet){
                    $_.ChildNodes|Where-Object{$_.Name -eq "CodeAnalysisRuleSet"}|ForEach-Object{
                        $_.ParentNode.RemoveChild($_)
                    }
                }
            }
            $xml.Project.Import|ForEach-Object{
                if ("$($_.Project)".EndsWith("Nuget.Targets")){
                    $_.ParentNode.RemoveChild($_)|Out-Null
                }
            }
            
            $xml.Save($_.FullName)
        }    
    }
}

Task Finalize {
    InvokeScript{
        Get-ChildItem "$root\Xpand.dll\" -Include "DevExpress.*" -Recurse | ForEach-Object{
            if (![system.io.path]::GetFileName($_).StartsWith("DevExpress.XAF") ){
                remove-item $_ -Force -Recurse
            }
        }
        Get-ChildItem "$root\Xpand.dll\" -Exclude "*.locked" | ForEach-Object{
            Copy-item $_ "$root\Build\Temp\$($_.FileName)" -Force
        }
        Copy-Item "$root\Xpand.key\Xpand.snk" "$root\build\Xpand.snk"
    } 
}

Task BuildExtras{
    InvokeScript{
        "$root\Support\XpandTestExecutor\XpandTestExecutor.sln","$root\Support\XpandTestExecutor\RDClient\RDClient.csproj" |ForEach-Object{
            Start-Build $msbuild (GetBuildArgs $_)
        }
    }
}

Task VSIX{
    InvokeScript{
        & "$PSScriptRoot\buildVSIX.ps1" "$root" $msbuild $version
    }  
}

Task Version{
    InvokeScript{
        & "$PSScriptRoot\changeversion.ps1" $root $version  
    }
}

Task RestoreNuget{
    InvokeScript {
        & "$PSScriptRoot\Restore-Nuget.ps1" -packageSources $packageSources -version $version -throttle $throttle
    }   
}

Task IndexSources{
    InvokeScript{
        & "$PSScriptRoot\IndexSources.ps1" $version
    }
}
Task EasyTest{
    InvokeScript  {
        $xpandDll="$root\Xpand.Dll"
        $thirdPartPath="$root\Support\_third_party_assemblies\"
        [xml]$xml = get-content "$PSScriptRoot\Xpand.projects"
        $group=$xml.Project.ItemGroup
        . "$PSScriptRoot\Utils.ps1"
        $projects=($group.DemoSolutions|GetProjects)+($group.DemoTesterProjects|GetProjects)
    
        Write-Host "Compiling other projects..." -f "Blue"
        $otherProjects=$projects|Where-Object{!"$_".Contains("Web") -and !"$_".Contains("Win")}
        BuildProjects $otherProjects
    
        Write-Host "Compiling Win projects..." -f "Blue"
        $winProjects=$projects|Where-Object{"$_".Contains("Win")}
        BuildProjects $winProjects

        Write-Host "Compiling Web projects..." -f "Blue"
        $webProjects=$projects|Where-Object{"$_".Contains("Web")}
        BuildProjects $webProjects

        if (Test-path "$PSScriptRoot\easytests.txt"){
            Remove-Item "$PSScriptRoot\easytests.txt" -Force
        }
        
        get-childitem "$root\Demos\" -Filter "*.ets" -Recurse|Select-Object -ExpandProperty FullName |Set-Content  "$xpandDll\easytests.txt"
        $reqs="$xpandDll\Xpand.utils.dll;$xpandDll\Xpand.ExpressApp.EasyTest.WinAdapter.dll;$xpandDll\Xpand.ExpressApp.EasyTest.WebAdapter.dll;$xpandDll\Xpand.EasyTest.dll;$xpandDll\Fasterflect.dll;$xpandDll\Aforge*.dll;"+
        "$xpanddll\Xpand.ExpressApp.EasyTest.WinAdapter.pdb;$xpanddll\Xpand.ExpressApp.EasyTest.WebAdapter.pdb;$xpanddll\Xpand.EasyTest.pdb;$xpanddll\Xpand.utils.pdb;"+
        "$xpandDll\psexec.exe;$xpandDll\CommandLine.dll;$xpandDll\executorwrapper.exe;$xpandDll\RDClient.exe;$(Get-DXPath $version)\Tools\eXpressAppFramework\EasyTest\TestExecutor.v$(Get-DXVersion $version).exe;$(Get-DXPath $version)\Tools\eXpressAppFramework\EasyTest\TestExecutor.v$(Get-DXVersion $version).exe.config;$thirdPartPath\AxInterop.MSTSCLib.dll;$thirdPartPath\Interop.MSTSCLib.dll;"
        $easyTests=[System.IO.File]::ReadLines("$xpandDll\easytests.txt") 
        $easyTests| ForEach-Object {
            $easyTest=$_
            if (Test-path $easyTest -ErrorAction SilentlyContinue){
                $reqs.split(';') |ForEach-Object{
                    $directory=$(Get-Item $easyTest).DirectoryName
                    if ($_){
                        if (Test-Path $_){
                            Copy-Item $_ $directory
                        }
                    }
                }
            }
        }
        Set-Location $xpandDll
        
        $r=New-Command "EasyTest" "$xpandDll\XpandTestExecutor.Win.exe" "$XpandDll\easytests.txt"
        if ($r.ExitCode){
            throw $r.stderr
        }
        get-childitem $root TestsLog.xml -Recurse|foreach{
            $xml=[xml](Get-Content $_.FullName)
            $fails=$xml.SelectNodes("/Tests/Test[@Result='Warning' or @Result='Failed']")|foreach{
                "app=$($_.ApplicationName)"
                "msg=$($_.InnerText)`r`n"
            }
            if ($fails.count -gt 0){
                $fails
                throw 
            }
        }
    }
}

Task Installer{
    InvokeScript{
        & "$PSScriptRoot\Installer.ps1" $root $version
    }
}

Task CompileModules{
    InvokeScript{
        . "$PSScriptRoot\Utils.ps1"
        [xml]$xml = get-content "$PSScriptRoot\Xpand.projects"
        $group=$xml.Project.ItemGroup
        $projects=($group.CoreProjects|GetProjects)+ ($group.ModuleProjects|GetProjects)
        $projects|ForEach-Object{
            $fileName=(Get-Item $_).Name
            write-host "Building $fileName..." -f "Blue"
            Start-Build $msbuild (GetBuildArgs "$_") 
        }
    }
}
task CompileDemos {
    InvokeScript{
        [xml]$xml = get-content "$PSScriptRoot\Xpand.projects"
        . $PSScriptRoot\Utils.ps1
        $group=$xml.Project.ItemGroup
        $projects= ($group.HelperProjects|GetProjects)+
        ($group.VSAddons|GetProjects)+($group.DemoSolutions|GetProjects)+($group.DemoTesterProjects|GetProjects)
        
        Write-Host "Compiling other projects..." -f "Blue"
        $otherProjects=$projects|Where-Object{!"$_".Contains("Web") -and !"$_".Contains("Win")}
        BuildProjects $otherProjects
        
        Write-Host "Compiling Win projects..." -f "Blue"
        $winProjects=$projects|Where-Object{"$_".Contains("Win")}
        BuildProjects $winProjects

        Write-Host "Compiling Web projects..." -f "Blue"
        $webProjects=$projects|Where-Object{"$_".Contains("Web")}
        BuildProjects $webProjects
        
        Write-Host "Compiling Agnostic EasyTest projects..." -f "Blue"
        BuildProjects (($group.EasyTestProjects|GetProjects)|Where-Object{!("$_".Contains("Win"))  -and !("$_".Contains("Web"))})
        
        Write-Host "Compiling Win EasyTest projects..." -f "Blue"
        BuildProjects (($group.EasyTestProjects|GetProjects)|Where-Object{"$_".Contains("Win")})
        
        Write-Host "Compiling Web EasyTest projects..." -f "Blue"
        BuildProjects (($group.EasyTestProjects|GetProjects)|Where-Object{"$_".Contains("Web")})

        & $root/Xpand.dll/BuildHelper.exe --afterbuild 
    }

}

function BuildProjects($projects ){
    $modules=(Get-Module XpandPosh).Path
    $sb={
        param($parameter)
        Push-Location $_.DirectoryName
        $result=New-Command $_ $parameter.msbuild """$_"" $($parameter.msbuildArgs)"
        [PSCustomObject]@{
            result = $result
            project=$_
        } 
    }
    $paramObject = [pscustomobject] @{
        location = $PSScriptRoot
        msbuild=$msbuild
        msbuildArgs=[system.string]::Join(" ",$msbuildArgs)
    }
    $projects|start-rsjob  $sb -argumentlist $paramObject -Throttle $throttle -ModulesToImport $modules -FunctionFilesToImport "$PSScriptRoot\Build.ps1"  |Wait-RSJob -ShowProgress |ForEach-Object{
        $j=Get-RSJob $_  |Receive-RSJob 
        $j.result.stdout
        $j.result.project
        if ($j.result.ExitCode){
            throw "Fail to build $($j.result.CommandTitle)`n`r$($j.result.stdout)" 
        }
        else{
            Write-Host "Project $($j.result.commandTitle) build succefully" -f "Green"
        }
    }
}


function GetBuildArgs($projectPath){
    (@($projectPath,"/p:OutputPath=$root\Xpand.dll\")+$msbuildArgs)
}

task Clean -precondition {return $clean} {
    exec {
        Set-Location $root
        if (Test-path .\Build){
            Remove-Item .\Build -Recurse -Force
        }
        if (Test-path .\Xpand.dll){
            Remove-Item .\Xpand.dll -Recurse -Force
        }
        Clear-ProjectDirectories
    }
}

task ? -Description "Helper to display task info" {
    Write-Documentation
}

function InvokeScript($sb){
    try {
        exec $sb
    }
    catch {
        Write-Warning $_.Exception
        exit 1
    }
}
