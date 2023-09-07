/**
 * Created by jglov on 9/7/2023.
 */

public class WorkItem {
    @AuraEnabled
    public Integer Id;
    @AuraEnabled
    public String State;
    @AuraEnabled
    public String Title;
    @AuraEnabled
    public String WorkItemType;
    @AuraEnabled
    public String Tags;
    @AuraEnabled
    public String Description;
}