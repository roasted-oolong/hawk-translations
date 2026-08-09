# ---------------------------------------------------------------------------
# RenderingRulesController
#
# CRUD for one novel's rendering-rule *overrides* (rendering_rules rows with
# novel_id set) — never the global defaults (novel_id: nil), which are
# seed-managed only (see db/seeds.rb, docs/DECISIONS.md 2026-08-09).
#
# Actions are keyed by rule_key, not id: the resolver (RenderingRule
# .effective_for) and the doc writer both think in rule_key, and a novel's
# index page shows the *effective* set — some rows its own overrides, some
# inherited defaults — so "edit" has to work uniformly on a rule_key whether
# or not this novel has overridden it yet. Editing an inherited default
# builds a fresh override in memory (see #edit); it never mutates the
# shared default row.
#
# Every mutation that can change this novel's effective rule set
# (create/update/destroy) re-renders bible/rendering_guide.md from the
# fresh resolved set afterward, so the file can never drift from the DB —
# mirrors RenderingRuleDocWriter#write's own "always fully rewrite" contract.
# ---------------------------------------------------------------------------
class RenderingRulesController < ApplicationController
  before_action :set_novel

  def index
    @rules = RenderingRule.effective_for(@novel)
    # Lets the view tell "override of a default" (revertible) apart from
    # "pure novel-specific addition" (only removable) without an N+1 lookup.
    @default_rule_keys = RenderingRule.defaults.pluck(:rule_key).to_set
  end

  # A blank form for a pure novel-specific addition (a rule_key with no
  # matching default). Overriding an existing default happens via #edit
  # instead, keyed by that default's rule_key.
  def new
    @rule = @novel.rendering_rules.build
  end

  def create
    @rule = @novel.rendering_rules.build(create_params)
    if @rule.save
      regenerate_guide
      redirect_to novel_rendering_rules_path(@novel), notice: "Rendering rule added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @rule = find_override(params[:rule_key]) || build_override_from_default(params[:rule_key])
    head :not_found and return unless @rule
  end

  def update
    @rule = find_override(params[:rule_key]) || @novel.rendering_rules.build(rule_key: params[:rule_key])
    if @rule.update(update_params)
      regenerate_guide
      redirect_to novel_rendering_rules_path(@novel), notice: "Rendering rule saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Removing an override reverts the novel to the default (if the rule_key
  # matches one) or drops a pure addition entirely — either way, letting
  # .effective_for resolve it fresh is simpler than special-casing which.
  def destroy
    find_override!(params[:rule_key]).destroy
    regenerate_guide
    redirect_to novel_rendering_rules_path(@novel), notice: "Override removed."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def find_override(rule_key)
    @novel.rendering_rules.find_by(rule_key: rule_key)
  end

  def find_override!(rule_key)
    @novel.rendering_rules.find_by!(rule_key: rule_key)
  end

  def build_override_from_default(rule_key)
    default = RenderingRule.defaults.find_by(rule_key: rule_key)
    return nil unless default

    @novel.rendering_rules.build(
      default.attributes.slice("rule_key", "name", "guidance", "example_input", "example_output", "position")
    )
  end

  def create_params
    params.require(:rendering_rule).permit(:rule_key, :name, :guidance, :example_input, :example_output, :position)
  end

  # rule_key is locked to the URL segment on update — it's the identity
  # .effective_for matches an override against a default by, so letting the
  # form body change it would silently detach an override from its default.
  def update_params
    create_params.except(:rule_key)
  end

  def novel_dir
    root = ENV.fetch("HAWK_PROJECT_ROOT", "")
    return "" if root.blank?
    File.join(root, @novel.directory_name)
  end

  def regenerate_guide
    RenderingRuleDocWriter.new(novel_dir).write(RenderingRule.effective_for(@novel))
  end
end
