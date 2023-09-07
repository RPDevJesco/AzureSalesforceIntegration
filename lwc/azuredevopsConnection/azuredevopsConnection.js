import { LightningElement, api, track } from 'lwc';
import getDetailedWorkItems from '@salesforce/apex/AzureConnection.getDetailedWorkItems';

export default class AzureDevOpsConnection extends LightningElement {
    @api setOrganizationName;
    @api setProjectName;
    @api setUserName;
    @api setPersonalAccessToken;
    @track workItems = [];
    @track error;

    columns = [
        { label: 'ID', fieldName: 'Id', type: 'number' },
        { label: 'Title', fieldName: 'Title', type: 'text' },
        { label: 'Description', fieldName: 'Description', type: 'text' },
        { label: 'State', fieldName: 'State', type: 'text' },
        { label: 'WorkItemType', fieldName: 'WorkItemType', type: 'text' },
        { label: 'Tags', fieldName: 'Tags', type: 'text' }
    ];

    connectedCallback() {
        getDetailedWorkItems({
            setOrganizationName: this.setOrganizationName,
            setProjectName: this.setProjectName,
            setUserName: this.setUserName,
            setPersonalAccessToken: this.setPersonalAccessToken
        })
            .then(result => {
                this.workItems = result;
                console.log(result);
            })
            .catch(error => {
                console.error('Error fetching work items', error);
            });
    }
}