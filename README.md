# Event grid Lab - PowerShell (Enterprise Best Practices)

This repository demonstrates how to set up and exercise Azure Event Grid using practices consistent with enterprise best practices. All infrastructure provisioning and configuration steps use **PowerShell** (instead of Bash) for repeatability and automation. Application code is kept minimal, but structured as if for production. This guide can be followed to repeat the setup or adapt it for your own organization.

---

## Product Description

This project delivers a minimal enterprise-grade event-driven system using Azure services:

- **Azure Function (.NET):** An HTTP-triggered function that receives POST requests.
- **Event Grid:** Used by the Function to publish events/messages.
- **Azure Storage Queue:** Subscribes to the Event Grid topic and receives the events, acting as a durable backend for further processing.

**Operational Flow:**
1. External systems or users POST content to the Azure Function endpoint.
2. The Azure Function publishes an event to Event Grid.
3. Event Grid delivers the event to the configured Azure Storage Queue.
4. Downstream systems/processes can consume messages from the queue.

This pattern is highly adaptable for real-world enterprise workloads, ensuring scalability, durability, and maintainability.

---

## Testing Method

Follow this sequence to validate the system:

1. **Provision Azure Storage Queue**
    - Create a storage account and queue using Azure CLI.

2. **Create Event Grid Topic and Subscription**
    - Use Azure CLI to create the Event Grid topic and subscribe the queue to it.

3. **Deploy and Configure Azure Function**
    - Build and publish the .NET Azure Function to Azure.
    - Ensure the function publishes events to the Event Grid topic (not directly to the queue).

4. **POST to the Function Endpoint**
    - Use PowerShell Invoke-RestMethod, `curl`, Postman, or similar tools to send data to the Function’s HTTP endpoint.

5. **Verify Message Delivery**
    - Check the Azure Storage Queue using Azure CLI, Azure Storage Explorer, or code to confirm the message exists. Messages should be delivered by Event Grid.

---

## Table of Contents

- [Product Description](#product-description)
- [Testing Method](#testing-method)
- [Project Overview](#project-overview)
- [Technology Stack](#technology-stack)
- [Pre-requisites](#pre-requisites)
- [Azure CLI Setup](#azure-cli-setup)
- [Resource Provisioning](#resource-provisioning)
- [Application Setup](#application-setup)
- [Event Grid Exercise](#event-grid-exercise)
- [Enterprise Practices](#enterprise-practices)
- [Local Development (IDE)](#local-development-ide)
- [Cleanup](#cleanup)
- [References](#references)
- [Next Steps](#next-steps)

---

## Project Overview

This project provisions Azure resources and exercises Event Grid with a minimal, repeatable workflow. It is suitable as a template for enterprise event-driven architectures and can be expanded for real-world products.

---

## Technology Stack

- **Infrastructure as Code:** Azure CLI scripts (demonstrated using PowerShell; can be migrated to Bicep/Terraform)
- **Application:** .NET 8 (C#) for publisher/subscriber (replaceable with Java/Python/Node)
- **Event Grid Topic:** Custom topic
- **Authentication:** Azure AD (Service Principal recommended for automation)
- **Local Development:** Visual Studio Code (cross-platform), with recommended extensions

---

## Pre-requisites

- Azure subscription (with permissions to create resources)
- Azure CLI installed ([Install guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli))
- .NET 8 SDK ([Download](https://dotnet.microsoft.com/en-us/download/dotnet/8.0))
- Visual Studio Code ([Download](https://code.visualstudio.com/)) or preferred IDE
- jq (for scripting convenience, optional)

---

## Azure CLI Setup

1. **Login**
   ```powershell
   az login
   ```

2. **Set Default Subscription**
   ```powershell
   az account set --subscription "<your-subscription-id>"
   ```

3. **(Optional) Create Service Principal**
   For CI/CD or automation:
   ```powershell
   az ad sp create-for-rbac --name "<your-app-name>" --role contributor
   ```

---

## Resource Provisioning (Best Practice: Modular Scripts and Sourcing Variables)

Use modular **`.ps1`** files for each step, loading a common `source.ps1` file for variables. This approach ensures consistency, repeatability, and easy maintenance.

### 1. Create a `source.ps1` file for shared variables

```powershell name=source.ps1
# source.ps1

$RG_NAME      = "az-204-eventgrid-lab-rg"
$LOCATION     = "westus"
$STORAGE_NAME = "eventgridstorage0714am"
$QUEUE_NAME   = "eventgridqueue"
$TOPIC_NAME   = "topic-eventgrid-demo"

# Try to get subscription ID from environment variable, otherwise fetch from Azure CLI
if ($env:AZURE_SUBSCRIPTION_ID) {
    $SUBSCRIPTION_ID = $env:AZURE_SUBSCRIPTION_ID
} else {
    $SUBSCRIPTION_ID = (az account show --query id -o tsv)
}

Write-Host "Resource Group: $RG_NAME"
Write-Host "Location: $LOCATION"
Write-Host "Storage Account: $STORAGE_NAME"
Write-Host "Queue Name: $QUEUE_NAME"
Write-Host "Topic Name: $TOPIC_NAME"
Write-Host "Subscription ID: $SUBSCRIPTION_ID"
```

### 2. Provision resources (`setup-eventgrid.ps1`)

```powershell name=setup-eventgrid.ps1
# setup-eventgrid.ps1
. .\source.ps1  # Dot-source the variables file

az group create --name $RG_NAME --location $LOCATION

az storage account create --name $STORAGE_NAME --resource-group $RG_NAME --location $LOCATION --sku Standard_LRS

az storage queue create --name $QUEUE_NAME --account-name $STORAGE_NAME
```

### 3. Create Event Grid Topic and Subscription (`setup-eventgrid-topic.ps1`)

```powershell name=setup-eventgrid-topic.ps1
# setup-eventgrid-topic.ps1
. .\source.ps1

az eventgrid topic create --name $TOPIC_NAME --resource-group $RG_NAME --location $LOCATION

$SOURCE_RESOURCE_ID = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.EventGrid/topics/$TOPIC_NAME"

az eventgrid event-subscription create `
  --name "demoSubscription" `
  --source-resource-id $SOURCE_RESOURCE_ID `
  --endpoint-type storagequeue `
  --endpoint "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.Storage/storageAccounts/$STORAGE_NAME/queueServices/default/queues/$QUEUE_NAME"
```

---

## Application Setup

### 1. Scaffold a new Azure Function (.NET) with HTTP Trigger (`init-function.ps1`)

```powershell name=init-function.ps1
# init-function.ps1
func init EventGridFunctionProj --worker-runtime dotnet --target-framework net8.0

$originalDir = Get-Location
try {
    Set-Location "$PSScriptRoot\EventGridFunctionProj"
    func new --name EventPublisherFunction --template "HTTP trigger"
}
catch {
    Write-Error "Script failed: $_"
}
finally {
    Set-Location $originalDir
}
```

### 2. Add packages for Event Grid publishing (`add-packages.ps1`)

```powershell name=add-packages.ps1
# add-packages.ps1
$originalDir = Get-Location
try {
    Set-Location "$PSScriptRoot\EventGridFunctionProj"
    dotnet add package Azure.Messaging.EventGrid
}
catch {
    Write-Error "Script failed: $_"
}
finally {
    Set-Location $originalDir
}
```

### 3. Implement Function logic (.NET) to POST events to Event Grid Topic

Create `EventPublisherFunction.cs` in your Azure Function project:

```csharp name=EventPublisherFunction.cs
using Azure;
using Azure.Messaging.EventGrid;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Extensions.Logging;
using System;
using System.IO;
using System.Threading.Tasks;

public static class EventPublisherFunction
{
    [FunctionName("EventPublisherFunction")]
    public static async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
        ILogger log)
    {
        log.LogInformation("Processing HTTP request for Event Grid publishing.");

        string requestBody = await new StreamReader(req.Body).ReadToEndAsync();

        // Get Event Grid endpoint and key from environment variables
        string topicEndpoint = Environment.GetEnvironmentVariable("EventGridTopicEndpoint");
        string topicKey = Environment.GetEnvironmentVariable("EventGridTopicKey");

        var client = new EventGridPublisherClient(
            new Uri(topicEndpoint),
            new AzureKeyCredential(topicKey));

        var eventGridEvent = new EventGridEvent(
            subject: "EventPublisherFunction",
            eventType: "SampleEvent",
            dataVersion: "1.0",
            data: new { message = requestBody }
        );

        await client.SendEventAsync(eventGridEvent);

        return new OkObjectResult("Event published to Event Grid Topic.");
    }
}
```

#### Update `local.settings.json` with Event Grid info

```json name=local.settings.json
{
  "IsEncrypted": false,
  "Values": {
    "EventGridTopicEndpoint": "https://topic-eventgrid-demo.westus-1.eventgrid.azure.net/api/events",
    "EventGridTopicKey": "<your_event_grid_topic_key>"
  }
}
```
Get your topic key from Azure Portal → Event Grid Topic → Access Keys.

---

## Event Grid Exercise (Test Locally and in Cloud)

**Note:** These tests can be performed after the topic/subscription step.

#### Send a POST Request to the Azure Function

```powershell
# Example using PowerShell's Invoke-RestMethod
Invoke-RestMethod -Uri "<function-endpoint-url>" -Method POST -ContentType "application/json" -Body '{"data":"sample"}'
```

#### Function publishes event to Event Grid.

#### Event Grid delivers event to the Storage Queue.

#### Check the Storage Queue

```powershell

# check-storage-queue.ps1
. .\source.ps1

# Peek up to 6 messages
$messages = az storage message peek --queue-name $QUEUE_NAME --account-name $STORAGE_NAME --num-messages 6 --output json

# Parse and decode
$messagesObj = $messages | ConvertFrom-Json
foreach ($msg in $messagesObj) {
    $base64 = $msg.content
    $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
    Write-Host "Decoded message:"
    Write-Host $json
    Write-Host "------------------------"
}
```

---

## Enterprise Practices

- **Automation:** All steps scripted with Azure CLI; can be converted to CI/CD or IaC templates.
- **Security:** Use Azure AD Service Principal for automation and RBAC for resource control.
- **Naming Conventions:** Use consistent, discoverable resource names.
- **Separation of Concerns:** Separate publisher, topic, and subscriber logic.
- **Monitoring:** Enable diagnostics on Event Grid topic and endpoints.

---

## Local Development (IDE)

1. **Open Solution in VS Code**
   ```powershell
   code .
   ```

2. **Recommended Extensions**
   - C# (OmniSharp)
   - Azure Tools
   - Azure CLI Tools

3. **Debug/Run**
   - Use built-in VS Code terminal for CLI commands.
   - Use VS Code debugger for .NET app.

---

## Cleanup

To remove all resources:
```powershell
az group delete --name $RG_NAME --yes
```

---

## References

- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/eventgrid)
- [Enterprise Patterns for Event Grid](https://learn.microsoft.com/en-us/azure/architecture/guide/architecture-styles/event-driven)
- [.NET Event Grid SDK](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/eventgrid)

---

## Next Steps

- Expand publisher/subscriber code for real scenarios
- Integrate with CI/CD pipeline
- Implement more secure authentication flows
