require "rails_helper"

RSpec.describe RenderingRule, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      rule = build(:rendering_rule)
      expect(rule).to be_valid
    end

    it "requires rule_key" do
      rule = build(:rendering_rule, rule_key: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:rule_key]).to be_present
    end

    it "requires name" do
      rule = build(:rendering_rule, name: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:name]).to be_present
    end

    it "requires guidance" do
      rule = build(:rendering_rule, guidance: nil)
      expect(rule).not_to be_valid
      expect(rule.errors[:guidance]).to be_present
    end

    it "allows example_input and example_output to be nil" do
      rule = build(:rendering_rule, example_input: nil, example_output: nil)
      expect(rule).to be_valid
    end

    it "allows novel to be nil (a global default)" do
      rule = build(:rendering_rule, novel: nil)
      expect(rule).to be_valid
    end

    it "rejects a second default with the same rule_key" do
      create(:rendering_rule, rule_key: "dialogue", novel: nil)
      dup = build(:rendering_rule, rule_key: "dialogue", novel: nil)
      expect(dup).not_to be_valid
      expect(dup.errors[:rule_key]).to be_present
    end

    it "rejects a second row for the same novel with the same rule_key" do
      novel = create(:novel)
      create(:rendering_rule, :override, rule_key: "dialogue", novel: novel)
      dup = build(:rendering_rule, :override, rule_key: "dialogue", novel: novel)
      expect(dup).not_to be_valid
      expect(dup.errors[:rule_key]).to be_present
    end

    it "allows the same rule_key once as a default and once as a novel override" do
      create(:rendering_rule, rule_key: "dialogue", novel: nil)
      novel = create(:novel)
      override = build(:rendering_rule, rule_key: "dialogue", novel: novel)
      expect(override).to be_valid
    end

    it "allows the same rule_key for two different novels" do
      create(:rendering_rule, rule_key: "dialogue", novel: create(:novel))
      other_novel_override = build(:rendering_rule, rule_key: "dialogue", novel: create(:novel))
      expect(other_novel_override).to be_valid
    end
  end

  describe "novel destroy cascade" do
    it "is destroyed when its novel is destroyed" do
      novel = create(:novel)
      create(:rendering_rule, :override, novel: novel)
      expect { novel.destroy }.to change(RenderingRule, :count).by(-1)
    end

    it "is not destroyed when it belongs to no novel" do
      create(:rendering_rule, novel: nil)
      novel = create(:novel)
      expect { novel.destroy }.not_to change(RenderingRule, :count)
    end
  end

  describe "scopes" do
    it ".defaults returns only novel_id: nil rows" do
      default = create(:rendering_rule, novel: nil)
      create(:rendering_rule, :override)
      expect(RenderingRule.defaults).to contain_exactly(default)
    end

    it ".for_novel returns only that novel's rows" do
      novel = create(:novel)
      mine = create(:rendering_rule, :override, novel: novel)
      create(:rendering_rule, :override)
      create(:rendering_rule, novel: nil)
      expect(RenderingRule.for_novel(novel)).to contain_exactly(mine)
    end

    it ".ordered sorts by position then id" do
      second = create(:rendering_rule, novel: nil, position: 1)
      first  = create(:rendering_rule, novel: nil, position: 0)
      expect(RenderingRule.ordered).to eq([ first, second ])
    end
  end

  describe ".effective_for" do
    it "returns the defaults, in position order, when the novel has no overrides" do
      novel = create(:novel)
      thoughts  = create(:rendering_rule, novel: nil, rule_key: "thoughts", position: 1)
      dialogue  = create(:rendering_rule, novel: nil, rule_key: "dialogue", position: 0)

      expect(RenderingRule.effective_for(novel)).to eq([ dialogue, thoughts ])
    end

    it "substitutes the novel's override for the matching default, in the default's slot" do
      novel = create(:novel)
      dialogue = create(:rendering_rule, novel: nil, rule_key: "dialogue", position: 0)
      create(:rendering_rule, novel: nil, rule_key: "thoughts", position: 1)
      dialogue_override = create(:rendering_rule, novel: novel, rule_key: "dialogue",
                                                    name: "House dialogue rule")

      result = RenderingRule.effective_for(novel)

      expect(result.first).to eq(dialogue_override)
      expect(result).not_to include(dialogue)
      expect(result.size).to eq(2)
    end

    it "does not let one novel's override leak into another novel's resolution" do
      novel_a = create(:novel)
      novel_b = create(:novel)
      create(:rendering_rule, novel: nil, rule_key: "dialogue", position: 0)
      create(:rendering_rule, novel: novel_a, rule_key: "dialogue", name: "Novel A's rule")

      result = RenderingRule.effective_for(novel_b)

      expect(result.map(&:name)).not_to include("Novel A's rule")
    end

    it "appends a novel-specific rule_key that has no matching default" do
      novel = create(:novel)
      create(:rendering_rule, novel: nil, rule_key: "dialogue", position: 0)
      addition = create(:rendering_rule, novel: novel, rule_key: "titles")

      result = RenderingRule.effective_for(novel)

      expect(result.last).to eq(addition)
      expect(result.size).to eq(2)
    end
  end
end
