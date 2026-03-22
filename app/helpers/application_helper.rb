module ApplicationHelper
  # Renders a button_to wrapped in a modal_controller div so clicking the
  # button opens the shared confirmation dialog instead of submitting immediately.
  #
  # Usage (drop-in replacement for button_to with turbo_confirm):
  #
  #   <%= modal_button_to "Remove", novel_path(@novel),
  #         method: :delete,
  #         message: "Remove \"#{@novel.title}\"? This cannot be undone.",
  #         confirm_label: "Remove",
  #         button_class: "btn btn--danger btn--sm" %>
  #
  # Options:
  #   message:       (required) Confirmation message shown in the dialog body.
  #   confirm_label: Label for the confirm button. Defaults to "Confirm".
  #   danger:        Whether the confirm button uses the danger style. Default true.
  #   button_class:  CSS class(es) for the inner <button>. Default "btn btn--danger btn--sm".
  #
  # All remaining options are forwarded to button_to.
  def modal_button_to(label, url, message:, confirm_label: "Confirm", danger: true, button_class: "btn btn--danger btn--sm", **options)
    controller_attrs = {
      data: {
        controller:                    "modal",
        modal_message_value:           message,
        modal_confirm_label_value:     confirm_label,
        modal_danger_value:            danger.to_s,
      }
    }

    button_options = options.merge(
      class: button_class,
      data:  (options[:data] || {}).merge(action: "click->modal#open")
    )

    content_tag(:div, **controller_attrs) do
      button_to(label, url, **button_options)
    end
  end
end
