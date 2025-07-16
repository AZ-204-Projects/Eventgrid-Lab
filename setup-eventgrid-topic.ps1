# setup-eventgrid-topic.ps1
. .\source.ps1

az eventgrid topic create --name $TOPIC_NAME --resource-group $RG_NAME --location $LOCATION

$SOURCE_RESOURCE_ID = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.EventGrid/topics/$TOPIC_NAME"

az eventgrid event-subscription create `
  --name "demoSubscription" `
  --source-resource-id $SOURCE_RESOURCE_ID `
  --endpoint-type storagequeue `
  --endpoint "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.Storage/storageAccounts/$STORAGE_NAME/queueServices/default/queues/$QUEUE_NAME"