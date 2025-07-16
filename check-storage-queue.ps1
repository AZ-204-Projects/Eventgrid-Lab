. .\source.ps1

# Peek up to 6 messages
$messages = az storage message peek --queue-name $QUEUE_NAME --account-name $STORAGE_NAME --num-messages 10 --output json

# Parse and decode
$messagesObj = $messages | ConvertFrom-Json
foreach ($msg in $messagesObj) {
    $base64 = $msg.content
    $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
    Write-Host "Decoded message:"
    Write-Host $json
    Write-Host "------------------------"
}