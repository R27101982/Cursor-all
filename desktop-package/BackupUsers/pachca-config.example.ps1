# Copy this file next to the scripts as:
#   C:\Users\admin\Desktop\BackupUsers\pachca-config.ps1
# Do NOT commit the real URL to git.
#
# In Pachca: create a bot -> Incoming webhook -> copy URL
# Add the bot to the target chat/channel.

$PachcaWebhookUrl = 'https://api.pachca.com/hooks/XXXXXXXX'

# Optional: mention who to ping (plain text is fine)
$PachcaNotifyPrefix = 'LS1 backup'
