import { LightningElement, api } from 'lwc';

export default class Modal extends LightningElement {
    // Public property to control modal's open/close state
    @api isOpen = false;
    @api comments = [];

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}