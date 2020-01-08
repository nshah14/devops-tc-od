# gets the name of the current git branch and set octopus defaults
$branch = git rev-parse --abbrev-ref HEAD
$octopusChannel = ""
$octopusDeployTo = ""

Write-Host "Branch: $branch"

# get previous git commit's tag
Function GetPreviousGitTag {
  [string] $commitInfo = git log --decorate=full --simplify-by-decoration --pretty=oneline HEAD | select-string -pattern "tag: \d*\.\d*\.\d*-api"
  [string] $previousBuildTag = [regex]::match($commitInfo, "\d*\.\d*\.\d*-api")
  [string] $previousBuildNumber = $previousBuildTag.split('-')[0]
  return $previousBuildNumber
}

# increment build number patch
Function IncrementBuildNumberPatch {
  param ([Parameter(Mandatory = $true)] [string] $previousBuildNumber)

  [int[]] $previousBuildNumbers = $previousBuildNumber.split('.')
  [int] $previousBuildMajor = $previousBuildNumbers[0]
  [int] $previousBuildMinor = $previousBuildNumbers[1]
  [int] $previousBuildPatch = $previousBuildNumbers[2] + 1
  return "$previousBuildMajor.$previousBuildMinor.$previousBuildPatch"
}

# get a valid authorisation header for teamcity api interaction
Function BuildTeamCityAuthHeaders {
  $user = '%system.TeamCityUsername%'
  $pass = '%system.TeamCityPassword%'

  $pair = "$($user):$($pass)"
  $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
  $basicAuthValue = "Basic $encodedCreds"
  $Headers = @{
    Authorization = $basicAuthValue
  }
  return $Headers
}

# submit parameter update request to teamcity api
Function UpdateTeamCityParameter {
  param ([Parameter(Mandatory = $true)] [string] $parameterName, [Parameter(Mandatory = $true)] $parameter)
  $Headers = BuildTeamCityAuthHeaders
  Invoke-WebRequest "http://vvctteamcity1.thisisglobal.com/httpAuth/app/rest/buildTypes/id:%system.teamcity.buildType.id%/parameters/$parameterName" -Headers $Headers -Method PUT -ContentType "application/json" -Body "{ ""name"":""$parameterName"", ""value"":""$parameter"" }"
}

if ($branch -eq "master") {
  # increment minor version number
  $buildNumber = "%system.MajorVersion%.%system.MinorVersion%.0"
  UpdateTeamCityParameter "system.MinorVersion" ([int] "%system.MinorVersion%" + 1)
  $octopusDeployTo = "%OctopusFirstEnv%"
}
elseif ($branch.StartsWith('feature/')) {
  # use teamcity auto-incremented build number for feature branches
  $buildNumber = "%system.MajorVersion%.%system.MinorVersion%.0.%build.counter%-beta"
  $octopusChannel = "Feature"
  $octopusDeployTo = "%OctopusFirstEnv%"
}
elseif ($branch.StartsWith('release/^[0-9]*\.[0-9]*\.[0-9]$')) {
  # increment patch version number of previous git tag
  #[string] $previousBuildNumber = GetPreviousGitTag
  #$buildNumber = IncrementBuildNumberPatch $previousBuildNumber
  #$octopusDeployTo = "%OctopusFirstEnv%"
  $buildNumber = "%system.MajorVersion%.%system.MinorVersion%.0"
    UpdateTeamCityParameter "system.MinorVersion" ([int] "%system.MinorVersion%" + 1)
    $octopusChannel = "Release Channel"
    $octopusDeployTo = "%OctopusFirstEnv%"
}
elseif ($branch.StartsWith('release/hotfix/^[0-9]*\.[0-9]*\.[0-9]$')) {
  # increment hotfix version number
  [string] $previousBuildNumber = GetPreviousGitTag
  $buildNumber = "${previousBuildNumber}.%system.HotfixVersion%-hotfix"
  UpdateTeamCityParameter "system.HotfixVersion" ([int] "%system.HotfixVersion%" + 1)
  $octopusChannel = "%OctopusHotfixChannel%"
  $octopusDeployTo = "%OctopusUAT%"
}
else {
  ##teamcity[buildStop comment='Branch does not have required prefix of: master, feature, release, or hotfix' readdToQueue='false']
}

# this deploys Release and Master to all environments. Feature is only in int/dev. Bufix goes in UAT.
Write-Host "##teamcity[buildNumber '$buildNumber']"
Write-Host "##teamcity[setParameter name='system.buildNumber' value='$buildNumber']"
Write-Host "buildNumber: $buildNumber"

# update deployment settings
Write-Host "##teamcity[setParameter name='system.Octopus.DeployTo' value='$octopusDeployTo']"
Write-Host "##teamcity[setParameter name='system.Octopus.Channel' value='$octopusChannel']"

# update assembly infos
Write-Host "Updating assembly infos to $buildNumber" 

$fileVersionPattern = 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
$fileVersion = 'AssemblyFileVersion("' + $buildNumber + '")'

$assemblyInformationalVersionPattern = 'AssemblyInformationalVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)'
$assemblyInformationalVersion = 'AssemblyInformationalVersion("' + $buildNumber + '")';

# add new attribute to any files that need it
$files = Get-ChildItem .\* -Recurse -Include AssemblyInfo.cs
$files | 
  where { 
    !((Get-Content $_.FullName) -Match "AssemblyInformationalVersion") 
  } | 
  foreach { 
    Write-Host "Adding AssemblyInformationalVersion to - $_.FullName" 
    ((Get-Content $_.FullName) + "`r`n[assembly:$assemblyInformationalVersion]") | 
      Set-Content -Encoding UTF8 $_.FullName
  }

# edit all files
$files | 
  foreach {
    Write-Host "Updating - $_.FullName"

    (Get-Content $_.FullName) | 
      foreach {
        % { $_ -replace $assemblyInformationalVersionPattern, $assemblyInformationalVersion } |
          % { $_ -replace $fileVersionPattern, $fileVersion }
      } | Set-Content -Encoding UTF8 $_.fullname
  }


$files = Get-ChildItem .\* -Recurse -Include SolutionInformation.cs

$files | 
  foreach {
    Write-Host "Updating - $_.FullName"

    (Get-Content $_.FullName) | 
      foreach {
        % { $_ -replace $fileVersionPattern, $fileVersion }
      } | Set-Content -Encoding UTF8 $_.fullname
  }
