import { Controller } from "@hotwired/stimulus"

export default class BibleTabsController extends Controller {
  static targets = ["panel", "btn"]

  declare panelTargets: HTMLElement[]
  declare btnTargets: HTMLButtonElement[]

  show({ params: { panel } }: { params: { panel: string } }) {
    this.panelTargets.forEach(p => { p.hidden = p.dataset.bibleTabsPanel !== panel })
    this.btnTargets.forEach(b => {
      b.classList.toggle("bible-tabs__btn--active", b.dataset.bibleTabsPanelParam === panel)
    })
  }
}
