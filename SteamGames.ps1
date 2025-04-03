# Set Steam installation directory (adjust the path if needed)
$steamDir = "C:\Program Files (x86)\Steam\steamapps"

# Set your SteamGridDB API key here (you need to create an account on SteamGridDB to get an API key)
$steamGridDBApiKey = "12345"  # Replace with your actual API key


#####################################

# Check if Steam directory exists
if (-Not (Test-Path $steamDir)) {
    Write-Host "Steam directory not found. Please check the Steam installation path."
    exit
}

# Path to the 'steamapps' directory
$steamAppsDir = Join-Path $steamDir "steamapps"

# Check if 'steamapps' directory exists
if (-Not (Test-Path $steamAppsDir)) {
    Write-Host "'steamapps' directory not found. Please check the Steam installation path."
    exit
}

# Set the directory where cover art images will be stored
$imageDir = "C:\Program Files\Apollo\images"
if (-Not (Test-Path $imageDir)) {
    New-Item -ItemType Directory -Force -Path $imageDir
}



# Function to fetch cover art from SteamGridDB
function Get-SteamCoverArt($appId) {
    $url = "https://www.steamgriddb.com/api/v2/grids/steam/$appId"
    $headers = @{
        "Authorization" = "Bearer $steamGridDBApiKey"
    }

    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        if ($response.success -and $response.data.Count -gt 0) {
            # Use the first grid image (Steam cover art)
            $imageUrl = $response.data[0].url
            return $imageUrl
        } else {
            Write-Warning "No cover art found for appId ${appId}."
            return $null
        }
    } catch {
        Write-Warning "Failed to fetch cover art for appId ${appId}: $_"
        return $null
    }
}

# Get list of all installed games
$installedGames = Get-ChildItem -Path $steamAppsDir -Recurse -Filter "*.acf"

# Initialize an empty array to store game data
$gamesList = @()

# Flag to check if we need to update the apps.json file
$updateJson = $false

# Loop through each game .acf file and extract game information
foreach ($gameFile in $installedGames) {
    try {
        # Read the content of the .acf file (Steam App Configuration File)
        $gameInfo = Get-Content -Path $gameFile.FullName -ErrorAction Stop

        # Extract AppID (This is the game ID)
        $appIdLine = $gameInfo | Select-String -Pattern '"appid"'
        if ($appIdLine) {
            $appId = $appIdLine.ToString().Split('"')[3]

            # Extract game name (This is found in the "name" field of the .acf file)
            $nameLine = $gameInfo | Select-String -Pattern '"name"'
            if ($nameLine) {
                $gameName = $nameLine.ToString().Split('"')[3]

                # Create a formatted Steam link and add game info to the array
                $steamLink = "steam://rungameid/$appId"

                # Check if an image already exists for this game
                $imageFileName = "$gameName.png" -replace '[\\/:*?"<>|]', '_'
                $imageFilePath = Join-Path $imageDir $imageFileName

                if (-Not (Test-Path $imageFilePath)) {
                    # Get cover art from SteamGridDB if the image does not exist
                    $imageUrl = Get-SteamCoverArt -appId $appId
                    if ($imageUrl) {
                        # Download and save the image locally as PNG
                        Invoke-WebRequest -Uri $imageUrl -OutFile $imageFilePath
                    }
                    $updateJson = $true  # Flag to indicate that the JSON should be updated
                }

                $gamesList += [PSCustomObject]@{
                    Name = $gameName
                    RunCommand = $steamLink
                    ImagePath = $imageFilePath
                }
            }
        }
    } catch {
        Write-Warning "Failed to process $($gameFile.FullName): $_"
    }
}

# Only update the JSON if a new game with no image was found
if ($updateJson) {
    # Build the JSON structure as per the example
    $appJson = @{
        apps = @(
            @{
                "allow-client-commands" = $false
                "image-path" = "desktop.png"
                "name" = "zdesktop"
                "uuid" = [guid]::NewGuid().ToString()
            },
            @{
                "auto-detach" = $true
                "cmd" = "steam://open/bigpicture"
                "image-path" = "steam.png"
                "name" = "zbpm"
                "prep-cmd" = @(
                    @{
                        "do" = ""
                        "elevated" = $false
                        "undo" = "steam://close/bigpicture"
                    }
                )
                "uuid" = [guid]::NewGuid().ToString()
                "wait-all" = $true
            }
        )
        env = @{ }
        version = 2
    }

    # Add each detected game to the JSON structure
    foreach ($game in $gamesList) {
        $appJson.apps += @{
            "allow-client-commands" = $true
            "auto-detach" = $true
            "cmd" = $game.RunCommand
            "image-path" = $game.ImagePath
            "name" = $game.Name
            "uuid" = [guid]::NewGuid().ToString()
            "wait-all" = $true
        }
    }

    # Convert the structure to JSON and save it to a file
    try {
        $appJson | ConvertTo-Json -Depth 5 | Set-Content -Path "C:\Program Files\Apollo\config\apps.json" -Force
        Write-Host "apps.json file has been created successfully."

        # Restart the ApolloService if JSON was updated
        Restart-Service -Name "ApolloService" -Force
        Write-Host "ApolloService has been restarted."

    } catch {
        Write-Host "Error writing to the file or restarting service: $_"
    }
} else {
    Write-Host "No new games were found with missing images. No updates made to apps.json."
}
