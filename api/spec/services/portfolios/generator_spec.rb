require "rails_helper"

RSpec.describe Portfolios::Generator do
  let(:session) { create(:session) }

  describe "#call" do
    context "when the AI response is fully valid" do
      let(:response) do
        {
          "configured_skills" => [
            {
              "skill_id"           => "sk-1",
              "skill_label"        => "Ruby",
              "level"              => 3,
              "confidence"         => "high",
              "evidence"           => ["quote"],
              "competency_summary" => "Solid."
            }
          ],
          "discovered_skills" => []
        }
      end
      let(:gemini) { instance_double(Gemini::HttpClient, generate_content: response) }

      it "creates a complete portfolio with the parsed skills" do
        portfolio = described_class.new(session: session, gemini_client: gemini).call

        expect(portfolio.generation_status).to eq("complete")
        expect(portfolio.portfolio_skills.count).to eq(1)
        expect(portfolio.portfolio_skills.first.skill_label).to eq("Ruby")
      end
    end

    context "when one skill in the AI response is invalid" do
      let!(:portfolio) { create(:portfolio, session: session, generation_status: "complete") }
      let!(:old_skill) { create(:portfolio_skill, portfolio: portfolio, skill_label: "Existing Skill") }

      let(:bad_response) do
        {
          "configured_skills" => [
            {
              "skill_id"           => "sk-1",
              "skill_label"        => "Ruby",
              "level"              => 3,
              "confidence"         => "high",
              "evidence"           => ["quote"],
              "competency_summary" => "Solid."
            },
            {
              "skill_id"           => "sk-2",
              "skill_label"        => nil, # fails PortfolioSkill's presence validation
              "level"              => 2,
              "confidence"         => "low",
              "evidence"           => [],
              "competency_summary" => "x"
            }
          ],
          "discovered_skills" => []
        }
      end
      let(:gemini) { instance_double(Gemini::HttpClient, generate_content: bad_response) }

      it "preserves the prior skills and marks the portfolio failed instead of losing data" do
        expect do
          described_class.new(session: session, gemini_client: gemini).call
        end.to raise_error(ActiveRecord::RecordInvalid)

        portfolio.reload

        expect(portfolio.generation_status).to eq("failed")
        expect(portfolio.portfolio_skills.count).to eq(1)
        expect(portfolio.portfolio_skills.first.id).to eq(old_skill.id)
        expect(portfolio.portfolio_skills.first.skill_label).to eq("Existing Skill")
      end
    end
  end
end
