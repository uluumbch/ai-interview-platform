require "rails_helper"

RSpec.describe "Portfolio tenant isolation", type: :request do
  let!(:org_a) { create(:organization) }
  let!(:org_b) { create(:organization) }

  let!(:session_a)         { create(:session, organization: org_a) }
  let!(:portfolio_a)       { create(:portfolio, session: session_a) }
  let!(:portfolio_skill_a) { create(:portfolio_skill, portfolio: portfolio_a) }

  let!(:vacancy_a) { create(:vacancy, organization: org_a) }
  let!(:vacancy_b) { create(:vacancy, organization: org_b) }

  let(:token_a) { auth_headers(scheme: org_a.scheme) }
  let(:token_b) { auth_headers(scheme: org_b.scheme) }

  describe "GET /api/v1/portfolios/:id/export" do
    it "allows the owning tenant" do
      get "/api/v1/portfolios/#{portfolio_a.id}/export", headers: token_a

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["portfolio"]["id"]).to eq(portfolio_a.id)
    end

    it "blocks a different tenant" do
      get "/api/v1/portfolios/#{portfolio_a.id}/export", headers: token_b

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/portfolios/:id/regenerate_fitgap" do
    it "allows the owning tenant" do
      post "/api/v1/portfolios/#{portfolio_a.id}/regenerate_fitgap",
           params: { vacancy_id: vacancy_a.id }, headers: token_a

      expect(response).to have_http_status(:accepted)
    end

    it "blocks a different tenant even when targeting a vacancy it legitimately owns" do
      post "/api/v1/portfolios/#{portfolio_a.id}/regenerate_fitgap",
           params: { vacancy_id: vacancy_b.id }, headers: token_b

      expect(response).to have_http_status(:not_found)
      expect(FitGapGeneratorWorker.jobs).to be_empty
    end
  end

  describe "POST /api/v1/portfolios/:id/fitgap" do
    it "allows the owning tenant" do
      post "/api/v1/portfolios/#{portfolio_a.id}/fitgap",
           params: { vacancy_id: vacancy_a.id }, headers: token_a

      expect(response).to have_http_status(:accepted)
    end

    it "blocks a different tenant even when targeting a vacancy it legitimately owns" do
      post "/api/v1/portfolios/#{portfolio_a.id}/fitgap",
           params: { vacancy_id: vacancy_b.id }, headers: token_b

      expect(response).to have_http_status(:not_found)
      expect(FitGapGeneratorWorker.jobs).to be_empty
    end
  end

  describe "GET /api/v1/portfolios/:id/fitgap/:vacancy_id" do
    let!(:fit_gap_report_a) do
      create(:fit_gap_report, portfolio: portfolio_a, vacancy: vacancy_a)
    end

    it "allows the owning tenant" do
      get "/api/v1/portfolios/#{portfolio_a.id}/fitgap/#{vacancy_a.id}", headers: token_a

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["report"]["culture_narrative"]).to eq(fit_gap_report_a.culture_narrative)
    end

    it "blocks a different tenant" do
      get "/api/v1/portfolios/#{portfolio_a.id}/fitgap/#{vacancy_a.id}", headers: token_b

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/portfolio_skills/:id/override" do
    let(:override_params) { { override: { override_level: 4, assessor_notes: "Looks solid." } } }

    it "allows the owning tenant to write an override" do
      expect do
        post "/api/v1/portfolio_skills/#{portfolio_skill_a.id}/override",
             params: override_params, headers: token_a
      end.to change(AssessorOverride, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "blocks a different tenant from writing an override" do
      expect do
        post "/api/v1/portfolio_skills/#{portfolio_skill_a.id}/override",
             params: override_params, headers: token_b
      end.not_to change(AssessorOverride, :count)

      expect(response).to have_http_status(:not_found)
      expect(FitGapGeneratorWorker.jobs).to be_empty
    end
  end
end
