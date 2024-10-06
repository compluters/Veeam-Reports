# Veeam Backup and Replication  API Information
$veeamRestServer = "localhost"
$veeamRestPort = "9419" # Adjusted Port for VBR API
$veeamUsername = "yourusername"
$veeamPassword = "youpassword"



# CSV Output File - Specify where to save the CSV output
$outputCsv = "MorningReport.csv"  # This is the file where the CSV data will be stored

# Base64 encode the credentials for Basic Authentication (used for login)
$authString = "$($veeamUsername):$($veeamPassword)"
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($authString))

# Authentication URL for OAuth2 token retrieval
$loginUrl = "https://$($veeamRestServer):$($veeamRestPort)/api/oauth2/token"

# Body data for the authentication request (using password grant type)
$bodyData = "grant_type=password&username=$veeamUsername&password=$veeamPassword"

# Try to authenticate with the Veeam API to get an access token
try {
    $response = Invoke-RestMethod -Uri $loginUrl -Method Post -Headers @{
        "x-api-version" = "1.1-rev2"  # API version used in the request
        "Accept" = "application/json"  # Expecting a JSON response
        "Content-Type" = "application/x-www-form-urlencoded"  # Sending URL-encoded form data
    } -Body $bodyData
} catch {
    Write-Host "Failed to authenticate with the Veeam API: $_" -ForegroundColor Red
    exit  # Exit the script if authentication fails
}

# Extract the access token from the API response
$token = $response.access_token
# Construct the Bearer token for future API requests
$Bearer = "Bearer $token"

# Define how many hours back you want to filter (e.g., last 24 hours)
$hoursBack = 24  # Set the number of hours to look back
$utcNow = (Get-Date).ToUniversalTime()  # Get the current time in UTC for accurate filtering
$startDate = $utcNow.AddHours(-$hoursBack)  # Calculate the start time based on the hours back

# Prepare CSV headers (define the columns for the CSV output)
"BackupJob,Type,StartTime,EndTime,Duration,Status,Info" | Out-File -FilePath $outputCsv -Force

# Backup sessions URL to fetch session data (this is the API endpoint for fetching sessions)
$backupSessionsUrl = "https://$($veeamRestServer):$($veeamRestPort)/api/v1/sessions"

# Try to fetch the backup job sessions data from Veeam API
try {
    $backupSessions = Invoke-RestMethod -Uri $backupSessionsUrl -Headers @{
        "Authorization" = $Bearer  # Using the Bearer token for authorization
        "x-api-version" = "1.1-rev2"  # API version for Veeam
        "Accept" = "application/json"  # Expecting JSON data
    } -Method Get -ContentType "application/json"
} catch {
    Write-Host "Error fetching backup sessions: $_" -ForegroundColor Red
    exit  # Exit if the request fails
}

# Loop through each session in the API response and filter based on the last X hours in UTC
foreach ($session in $backupSessions.data) {
    $startTimeUTC = [datetime]::Parse($session.creationTime).ToUniversalTime()

    # Check if the session start time is within the specified range (last X hours)
    if ($startTimeUTC -ge $startDate) {
        $jobName = $session.name  # Backup job name
        $type = $session.sessionType  # Type of job or session information

        # Only process sessions where the type is "BackupJob"
        if ($type -eq $type) {
            # Check if the endTime exists and is valid before attempting to parse it
            if ($session.endTime) {
                try {
                    $endTime = [datetime]::Parse($session.endTime).ToUniversalTime()  # Parse the end time and convert to UTC
                } catch {
                    Write-Host "Error parsing endTime for job $jobName $_" -ForegroundColor Yellow
                    $endTime = "Invalid"  # Handle the invalid endTime
                }
            } else {
                $endTime = "N/A"  # Handle missing endTime
            }

            # Calculate the duration of the backup job (from start to end time, if valid)
            if ($endTime -ne "Invalid" -and $endTime -ne "N/A") {
                $duration = ($endTime - $startTimeUTC).ToString("hh\:mm")  # Format the duration as hours and minutes
            } else {
                $duration = "N/A"  # No valid duration if endTime is missing or invalid
            }

            $status = $session.result  # Job status (e.g., Success, Warning, Failed)
            $info = $session.result.message  # Additional information about the job

            # Adjust the status and progress based on the result
            switch ($status) {
                "Success" {
                    $status = "Success"
                    $progress = "100%"  # Job completed successfully
                    $info = $session.result.message
                }
                "Warning" {
                    $status = "Warning"
                    $progress = "100%"  # Job completed but with warnings
                    $info = $session.result.message
                }
                "Failed" {
                    $status = "Failed"
                    $progress = "100%"  # Job failed
                    $info = $session.result.message  # Include the failure message
                }
                default {
                    $status = "Unknown"
                    $progress = "N/A"  # Unknown progress
                    $info = "Unknown job status"
                }
            }

            # Format the CSV row and append it to the CSV file
            "$jobName,$type,$startTimeUTC,$endTime,$duration,$status,$progress,$info" | Out-File -Append -FilePath $outputCsv
        }
    }
}

# Output the location of the generated CSV
Write-Host "Morning Backup Report CSV generated at: $outputCsv" -ForegroundColor Green


