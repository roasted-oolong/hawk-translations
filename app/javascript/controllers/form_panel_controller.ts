// form_panel_controller.ts
//
// Generic open/close controller for form <dialog> elements.
//
// HTML contract:
//   data-controller="form-panel" on the wrapper element
//   data-form-panel-target="dialog"  → the <dialog> element
//
//   data-action="click->form-panel#open"         on the trigger button
//   data-action="click->form-panel#close"        on the Cancel button inside the dialog
//   data-action="click->form-panel#backdropClose" on the <dialog> element itself
//     (closes when user clicks the backdrop outside the panel)

import { Controller } from "@hotwired/stimulus"

export default class FormPanelController extends Controller {
  static targets = ["dialog"]

  declare dialogTarget: HTMLDialogElement

  open(): void {
    this.dialogTarget.showModal()
  }

  close(): void {
    this.dialogTarget.close()
  }

  backdropClose(event: MouseEvent): void {
    if (event.target === this.dialogTarget) {
      this.dialogTarget.close()
    }
  }
}
