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