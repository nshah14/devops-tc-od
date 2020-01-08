echo "system date"
echo $start
echo "set time "
$TargetTime=$OctopusParameters["Octopus.Action[Approval Required Tech team].Output.Manual.Notes"]
echo $TargetTime
if($TargetTime -match '\d{2}-\d{2}-\d{4} \d{2}:\d{2}')
{
   Write-Host " Timed deployment" 
  do{
     #echo "wait"
     $start = Get-Date -format "dd-MM-yyyy HH:mm"
  }until($start -eq $TargetTime)
}
else
{
  echo "Deploying now"   
}




