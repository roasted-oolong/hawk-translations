require "rails_helper"

RSpec.describe "RenderingRules", type: :request do
  let(:user)      { create(:user) }
  let(:novel_dir) { Dir.mktmpdir }
  let(:novel)     { create(:novel, directory_name: File.basename(novel_dir)) }
  let(:guide_path) { File.join(novel_dir, "bible", "rendering_guide.md") }

  let!(:default_rule) { create(:rendering_rule, rule_key: "dialogue", name: "Dialogue", guidance: "Use double quotes.") }

  before do
    sign_in(user)
    @orig_root = ENV["HAWK_PROJECT_ROOT"]
    ENV["HAWK_PROJECT_ROOT"] = File.dirname(novel_dir)
  end

  after do
    ENV["HAWK_PROJECT_ROOT"] = @orig_root
    FileUtils.rm_rf(novel_dir)
  end

  describe "GET /novels/:novel_id/rendering_rules" do
    it "returns 200 and lists the resolved (default) rule" do
      get novel_rendering_rules_path(novel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dialogue")
    end
  end

  describe "GET /novels/:novel_id/rendering_rules/new" do
    it "returns 200" do
      get new_novel_rendering_rule_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /novels/:novel_id/rendering_rules" do
    context "with a fresh rule_key (a novel-specific addition)" do
      it "creates the override and regenerates the rendering guide" do
        expect {
          post novel_rendering_rules_path(novel), params: {
            rendering_rule: { rule_key: "em-dash", name: "Em dash", guidance: "Never use it." }
          }
        }.to change(RenderingRule, :count).by(1)

        expect(response).to redirect_to(novel_rendering_rules_path(novel))
        expect(RenderingRule.find_by(novel: novel, rule_key: "em-dash")).to be_present
        expect(File.read(guide_path)).to include("Em dash")
      end
    end

    context "with missing guidance" do
      it "does not create a rule and re-renders new" do
        expect {
          post novel_rendering_rules_path(novel), params: {
            rendering_rule: { rule_key: "em-dash", name: "Em dash", guidance: "" }
          }
        }.not_to change(RenderingRule, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /novels/:novel_id/rendering_rules/:rule_key/edit" do
    it "builds an unsaved override from the default when the novel has none yet" do
      get edit_novel_rendering_rule_path(novel, "dialogue")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Use double quotes.")
    end

    it "returns 404 for a rule_key with no default and no override" do
      get edit_novel_rendering_rule_path(novel, "nonexistent")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /novels/:novel_id/rendering_rules/:rule_key" do
    it "creates the novel's override on first save and regenerates the guide" do
      expect {
        patch novel_rendering_rule_path(novel, "dialogue"), params: {
          rendering_rule: { name: "Dialogue", guidance: "Use single quotes here instead." }
        }
      }.to change { novel.rendering_rules.count }.by(1)

      expect(File.read(guide_path)).to include("Use single quotes here instead.")
      expect(File.read(guide_path)).not_to include("Use double quotes.")
    end

    it "updates an existing override in place rather than duplicating it" do
      create(:rendering_rule, :override, novel: novel, rule_key: "dialogue", name: "Dialogue", guidance: "Old guidance.")

      expect {
        patch novel_rendering_rule_path(novel, "dialogue"), params: {
          rendering_rule: { name: "Dialogue", guidance: "New guidance." }
        }
      }.not_to change { novel.rendering_rules.count }

      expect(File.read(guide_path)).to include("New guidance.")
    end

    it "ignores an attempt to change rule_key via the form body" do
      patch novel_rendering_rule_path(novel, "dialogue"), params: {
        rendering_rule: { name: "Dialogue", guidance: "x", rule_key: "hijacked" }
      }

      expect(novel.rendering_rules.find_by(rule_key: "dialogue")).to be_present
      expect(novel.rendering_rules.find_by(rule_key: "hijacked")).to be_nil
    end
  end

  describe "DELETE /novels/:novel_id/rendering_rules/:rule_key" do
    it "removes the novel's override and reverts the guide to the default text" do
      create(:rendering_rule, :override, novel: novel, rule_key: "dialogue", name: "Dialogue", guidance: "Overridden.")

      expect {
        delete novel_rendering_rule_path(novel, "dialogue")
      }.to change { novel.rendering_rules.count }.by(-1)

      expect(File.read(guide_path)).to include("Use double quotes.")
      expect(File.read(guide_path)).not_to include("Overridden.")
    end

    it "returns 404 when there is no override to remove" do
      delete novel_rendering_rule_path(novel, "dialogue")
      expect(response).to have_http_status(:not_found)
    end
  end
end
