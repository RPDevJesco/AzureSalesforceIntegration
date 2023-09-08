/**
 * Created by jglov on 9/7/2023.
 */

public with sharing class AzureConnection {
    private static String ORGANIZATION;
    private static String PROJECT;
    private static String USERNAME;
    private static String PAT;

    // Initialize HttpRequest
    private static HttpRequest initializeHttpRequest(String endpoint, String method) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        return req;
    }

    // Set Authentication
    private static void setAuthentication(HttpRequest req) {
        // For Basic Authentication
        String credentials = USERNAME + ':' + PAT;
        Blob headerValue = Blob.valueOf(credentials);
        String authorizationHeader = 'Basic ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
    }

    // Execute Callout
    private static HttpResponse executeCallout(HttpRequest req) {
        Http http = new Http();
        HttpResponse res;

        try {
            res = http.send(req);
        } catch (System.CalloutException e) {
            System.debug('Callout error: ' + e);
            throw e;  // re-throw the exception if necessary
        }

        return res;
    }

    // Main Function to Coordinate the Callout
    public static HttpResponse makeCallout(String endpoint, String method) {
        HttpRequest req = initializeHttpRequest(endpoint, method);
        setAuthentication(req);
        HttpResponse res = executeCallout(req);
        return res;
    }

    // Validate and Sanitize value for Callout
    public static String sanitizeAssignedToValue(String input) {
        if (input == null) {
            return null;
        }

        // Basic validation: Check for allowed patterns, length, etc.
        // For example: Check if the string is of reasonable length
        if (input.length() > 255) {
            System.debug('AssignedTo value is too long.');
        }

        // Basic validation: Ensure it doesn't contain semicolons, double quotes, etc.
        Pattern disallowedChars = Pattern.compile('[;"]'); // Add other characters as needed
        if (disallowedChars.matcher(input).find()) {
            System.debug('Invalid characters in AssignedTo value.');
        }

        // Escape single quotes
        return String.escapeSingleQuotes(input);
    }

    @AuraEnabled(Cacheable=true)
    public static List<WorkItem> getDetailedWorkItems(String setOrganizationName, String setProjectName, String setUserName, String setPersonalAccessToken) {
        ORGANIZATION = setOrganizationName;
        PROJECT = setProjectName;
        USERNAME = setUserName;
        PAT = setPersonalAccessToken;
        List<WorkItem> workItems = new List<WorkItem>();

        String endpoint = 'https://dev.azure.com/' + ORGANIZATION +'/' + PROJECT + '/_apis/wit/wiql?api-version=6.0';
        HttpRequest req = initializeHttpRequest(endpoint, 'GET');
        setAuthentication(req);
        //String wiqlQuery = '{"query": "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.AssignedTo], [System.State], [System.Tags] \n' +
        //'FROM workitems \n' +
        //'WHERE [System.TeamProject] = @project\n' +
        //'ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [System.CreatedDate] DESC"}';

        String wiqlQuery = '{"query": "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.AssignedTo], [System.State], [System.Tags] ' +
                'FROM workitems ' +
                'WHERE [System.TeamProject] = @project ' +
                'AND [System.AssignedTo] = \'' + sanitizeAssignedToValue(USERNAME) + '\' ' +
                'ORDER BY [Microsoft.VSTS.Common.Priority] ASC, [System.CreatedDate] DESC"}';
        req.setBody(wiqlQuery);
        HttpResponse initialResponse = executeCallout(req);

        Map<String, Object> parsedResponse = (Map<String, Object>) JSON.deserializeUntyped(initialResponse.getBody());
        List<Object> workItemsData = (List<Object>) parsedResponse.get('workItems');

        // Collecting the IDs from the initial response
        List<Integer> ids = new List<Integer>();
        for (Object itemData : workItemsData) {
            Map<String, Object> itemMap = (Map<String, Object>) itemData;
            Integer id = (Integer) itemMap.get('id');
            ids.add(id);
        }

        // Make a batch call with the collected IDs
        String batchEndpoint = 'https://dev.azure.com/' + ORGANIZATION +'/' + PROJECT + '/_apis/wit/workitems?ids=' + String.join(ids, ',') + '&api-version=6.0';
        HttpResponse batchResponse = makeCallout(batchEndpoint, 'GET');
        Map<String, Object> batchResponseData = (Map<String, Object>) JSON.deserializeUntyped(batchResponse.getBody());
        List<Object> detailedWorkItems = (List<Object>) batchResponseData.get('value');

        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(batchResponse.getBody());
        //System.debug('response map: ' + responseMap);
        List<Object> workItemsList = (List<Object>) responseMap.get('value');

        for (Object obj : workItemsList) {
            Map<String, Object> workItemDetails = (Map<String, Object>) obj;
            Map<String, Object> fields = (Map<String, Object>) workItemDetails.get('fields');

            WorkItem workItem = new WorkItem();
            workItem.Id = (Integer) workItemDetails.get('id');
            workItem.Title = (String) fields.get('System.Title');
            // Fetch the Description and remove <div> and </div> tags
            String description = (String) fields.get('System.Description');
            if(description != null) {
                description = description.replace('<div>', '').replace('</div>', '').replace('<br>', '');
                workItem.Description = description.trim();  // Trim to remove any leading or trailing spaces
            }
            workItem.State = (String) fields.get('System.State');
            workItem.WorkItemType = (String) fields.get('System.WorkItemType');

            if(fields.containsKey('System.Tags')) {
                workItem.Tags = (String) fields.get('System.Tags');
            } else {
                workItem.Tags = null;
            }

            workItems.add(workItem);
        }

        return workItems;
    }

    @AuraEnabled(Cacheable=true)
    public static List<String> getWorkItemComments(String setOrganizationName, String setProjectName, String setUserName, String setPersonalAccessToken, Integer workItemId) {
        ORGANIZATION = setOrganizationName;
        PROJECT = setProjectName;
        USERNAME = setUserName;
        PAT = setPersonalAccessToken;
        List<String> comments = new List<String>();
        String endpoint = 'https://dev.azure.com/' + ORGANIZATION + '/' + PROJECT + '/_apis/wit/workitems/' + workItemId + '/comments?api-version=6.0-preview';
        HttpRequest req = initializeHttpRequest(endpoint, 'GET');
        setAuthentication(req);
        HttpResponse res = executeCallout(req);
        if (res.getStatusCode() != 200) {
            // You can log the error or throw an exception with the response body to get more details about the failure
            System.debug('Callout failed with status: ' + res.getStatusCode() + '. Response: ' + res.getBody());
            System.debug('Failed to fetch comments for work item: ' + workItemId);
        }

        Map<String, Object> parsedResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> commentsData = (List<Object>) parsedResponse.get('comments');
        for (Object commentData : commentsData) {
            Map<String, Object> commentMap = (Map<String, Object>) commentData;
            comments.add((String) commentMap.get('text'));
        }
        return comments;
    }

    @AuraEnabled(Cacheable=true)
    public static void updateWorkItemState(String setOrganizationName, String setProjectName, String setUserName, String setPersonalAccessToken, Integer workItemId, String newState) {
        HttpRequest req = new HttpRequest();
        HttpResponse res = new HttpResponse();
        Http http = new Http();

        ORGANIZATION = setOrganizationName;
        PROJECT = setProjectName;
        USERNAME = setUserName;
        PAT = setPersonalAccessToken;

        req.setEndpoint('https://dev.azure.com/' + ORGANIZATION + '/' + PROJECT + '/_apis/wit/workitems/' + workItemId + '?api-version=6.0');
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(':' + PAT)));
        req.setHeader('Content-Type', 'application/json-patch+json');

        // Construct the JSON body for the update
        String body = '[{"op": "add", "path": "/fields/System.State", "value": "' + newState + '"}]';
        req.setBody(body);

        res = http.send(req);
        // Handle the response as required
    }

    @AuraEnabled(Cacheable=true)
    public static void addWorkItemComment(String setOrganizationName, String setProjectName, String setUserName, String setPersonalAccessToken,Integer workItemId, String commentText) {
        ORGANIZATION = setOrganizationName;
        PROJECT = setProjectName;
        USERNAME = setUserName;
        PAT = setPersonalAccessToken;
        String endpoint = 'https://dev.azure.com/' + ORGANIZATION + '/' + PROJECT + '/_apis/wit/workitems/' + workItemId + '/comments?api-version=6.0-preview';
        HttpRequest req = initializeHttpRequest(endpoint, 'POST');
        setAuthentication(req);

        Map<String, String> requestBody = new Map<String, String>{
                'text' => commentText
        };
        req.setBody(JSON.serialize(requestBody));

        HttpResponse res = executeCallout(req);
        // Handle the response if necessary
    }
}