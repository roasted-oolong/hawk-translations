// dialog_controller.ts
//
// Manages the shared <dialog id="modal-dialog"> element in the application
// layout. Works in tandem with modal_controller.ts — the modal controller
// opens the dialog and stores itself as the active handler; this controller
// routes confirm/cancel back to it.
//
// The dialog also handles:
//   - Escape key (natively by the browser, no JS needed)
//   - Backdrop click (click on the <dialog> element itself, outside the panel)
//
// Registers itself on the dialog element:
//   <dialog id="modal-dialog" data-controller="dialog" ...>

import { Controller } from "@hotwired/stimulus"

// The shared dialog element carries a reference to the currently active
// ModalController instance so this controller can call back into it.
interface ManagedDialog extends HTMLDialogElement {
  _modalController?: { handleConfirm(): void; handleCancel(): void }
}

export default class DialogController extends Controller {
  declare element: ManagedDialog

  connect(): void {
    // Handle backdrop click: the click target is the <dialog> itself when the
    // user clicks outside the inner panel.
    this.element.addEventListener("click", this.handleBackdropClick.bind(this))
  }

  confirm(): void {
    const handler = this.element._modalController
    this.element.close()
    handler?.handleConfirm()
    this.element._modalController = undefined
  }

  cancel(): void {
    const handler = this.element._modalController
    this.element.close()
    handler?.handleCancel()
    this.element._modalController = undefined
  }

  private handleBackdropClick(event: MouseEvent): void {
    if (event.target === this.element) {
      this.cancel()
    }
  }
}
