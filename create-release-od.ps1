$octopusBaseURL = $OctopusBaseUrl

$octopusAPIKey = $OctopusApiKey

$headers = @{ "X-Octopus-ApiKey" = $octopusAPIKey }

$spaceName = $OctopusParameters["Octopus.Space.Name"]
$projectName = $OctopusParameters["Octopus.Project.Name"]

$environmentName = $ReleaseChannelfirstEnvironment

$channelName = $ReleaseChannelName

echo "Going to release"
try {
    # Get space id
    $spaces = Invoke-WebRequest -Uri "$octopusBaseURL/spaces/all"  -UseBasicParsing -Headers $headers -ErrorVariable octoError | ConvertFrom-Json
    $space = $spaces | Where-Object { $_.Name -eq $spaceName }
    Write-Host "Using Space named $($space.Name) with id $($space.Id)"

    # Create space specific url
    $octopusSpaceUrl = "$octopusBaseURL/$($space.Id)"

    # Get project by name
    $projects = Invoke-WebRequest -UseBasicParsing -Uri "$octopusSpaceUrl/projects/all" -Headers $headers -ErrorVariable octoError | ConvertFrom-Json
    $project = $projects | Where-Object { $_.Name -eq $projectName }
    Write-Host "Using Project named $($project.Name) with id $($project.Id)"

    # Get channel by name
    $channels = Invoke-WebRequest -UseBasicParsing -Uri "$octopusSpaceUrl/projects/$($project.Id)/channels" -Headers $headers -ErrorVariable octoError | ConvertFrom-Json
    Write-Host "channels : $channels"
    $channel = $channels | Where-Object { $_.Name -eq $channelName }
    $count = $channels.TotalResults
    
    Write-host " count : $count"
    For ($i=0; $i -lt $channels.TotalResults; $i++) {
     Write-host "Items $i :: $($channels.Items[$i].Name) "
     if( $channels.Items[$i].Name -eq $channelName)
     {
     	$channelID=$channels.Items[$i].Id
        Write-host "Items id $i :: $($channels.Items[$i].Id) "
     }
    }
   
    Write-Host "Using Channel named $($channel.Name) with id $($channel.Id)"

    # Get environment by name
    $environments = Invoke-WebRequest -UseBasicParsing -Uri "$octopusSpaceUrl/environments/all" -Headers $headers -ErrorVariable octoError | ConvertFrom-Json
    Write-Host "environments : $environments"
    $environment = $environments | Where-Object { $_.Name -eq $environmentName }
    Write-Host "Using Environment named $($environment.Name) with id $($environment.Id)"

    # Get the deployment process template
    Write-Host "Fetching deployment process template"
    $template = Invoke-WebRequest -UseBasicParsing -Uri "$octopusSpaceUrl/deploymentprocesses/deploymentprocess-$($project.id)/template?channel=$($channel.Id)" -Headers $headers | ConvertFrom-Json
    $lastReleaseVersion = $template.NextVersionIncrement 
    
    $i =1
    $newReleaseVersion=""
    $lastReleaseVersion.Split(".") | ForEach {
       if($i -eq 3)
       {
         $_=0
         $newReleaseVersion += $_
         $newReleaseVersion=$newReleaseVersion+"-rc"
       }
       else
       {
        $newReleaseVersion += $_
        $newReleaseVersion=$newReleaseVersion+"."
       } 
       $i++
     }
   
    echo "new revision"
    echo $newReleaseVersion
    # Create the release body
    $releaseBody = @{
        ChannelId        = $channelID
        ProjectId        = $project.Id
        Version          = $newReleaseVersion #template.NextVersionIncrement
        SelectedPackages = @()
    }

    # Set the package version to the latest for each package
    # If you have channel rules that dictate what versions can be used, you'll need to account for that
    Write-Host "Getting step package versions"
    $template.Packages | ForEach-Object {
        $uri = "$octopusSpaceUrl/feeds/$($_.FeedId)/packages/versions?packageId=$($_.PackageId)&take=1"
        $version = Invoke-WebRequest  -UseBasicParsing -Uri $uri -Method GET -Headers $headers -Body $releaseBody -ErrorVariable octoError | ConvertFrom-Json
        $version = $version.Items[0].Version

        $releaseBody.SelectedPackages += @{
            ActionName           = $_.ActionName
            PackageReferenceName = $_.PackageReferenceName
            Version              = $version
        }
    }

    #Create release
    $releaseBody = $releaseBody | ConvertTo-Json
    Write-Host "Creating release with these values: $releaseBody"
    $release = Invoke-WebRequest -UseBasicParsing -Uri $octopusSpaceUrl/releases -Method POST -Headers $headers -Body $releaseBody -ErrorVariable octoError  | ConvertFrom-Json

    # Create deployment
   }
catch {
    Write-Host "There was an error during the request: $($octoError.Message)"
    exit
}
