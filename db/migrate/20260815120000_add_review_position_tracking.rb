class AddReviewPositionTracking < ActiveRecord::Migration[8.1]
  def change
    # Fraction (0.0..1.0) of how far down the review pane the reviewer had
    # scrolled in this chapter, last time they left it — lets chapter_review
    # silently reopen a chapter exactly where the reviewer stopped instead of
    # at the top, the same way an editor restores cursor position per file.
    add_column :chapters, :last_scroll_position, :float, null: false, default: 0.0

    # Which chapter chapter_review's slideshow should open on — without this,
    # the review page always starts at the first untouched chapter, and a
    # reviewer who spends several days on one chapter has to click back to it
    # by hand every time they return.
    add_reference :novels, :last_reviewed_chapter, foreign_key: { to_table: :chapters }
  end
end
