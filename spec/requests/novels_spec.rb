require "rails_helper"

RSpec.describe "Novels", type: :request do
  let(:user)         { create(:user) }
  let(:organization) { create(:organization) }
  let!(:novel)       { create(:novel, organization: organization) }

  before { sign_in(user) }

  describe "GET /novels" do
    it "returns 200 and lists novels" do
      get novels_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(novel.title)
    end
  end

  describe "GET /novels/:id" do
    it "returns 200 and shows the novel" do
      get novel_path(novel)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(novel.title)
    end
  end

  describe "GET /novels/new" do
    it "returns 200" do
      get new_novel_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /novels" do
    context "with valid params" do
      it "creates a novel and redirects to it" do
        expect {
          post novels_path, params: {
            novel: {
              title:           "My New Novel",
              directory_name:  "my-new-novel",
              organization_id: organization.id,
              visibility:      "discoverable"
            }
          }
        }.to change(Novel, :count).by(1)

        expect(response).to redirect_to(novel_path(Novel.last))
      end
    end

    context "with invalid params" do
      it "does not create a novel and re-renders new" do
        expect {
          post novels_path, params: { novel: { title: "", organization_id: organization.id } }
        }.not_to change(Novel, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /novels/:id/edit" do
    it "returns 200" do
      get edit_novel_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /novels/:id" do
    context "with valid params" do
      it "updates the novel and redirects" do
        patch novel_path(novel), params: { novel: { title: "Updated Title" } }
        expect(response).to redirect_to(novel_path(novel))
        expect(novel.reload.title).to eq("Updated Title")
      end
    end

    context "with invalid params" do
      it "does not update and re-renders edit" do
        patch novel_path(novel), params: { novel: { title: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /novels/:id" do
    it "destroys the novel and redirects to index" do
      expect {
        delete novel_path(novel)
      }.to change(Novel, :count).by(-1)

      expect(response).to redirect_to(novels_path)
    end
  end

  describe "authentication" do
    it "redirects unauthenticated requests to login" do
      # Clear session by not signing in
      get novels_path, headers: { "HTTP_COOKIE" => "" }
      # A fresh request without session will redirect
      new_session_get = ActionDispatch::Integration::Session.new(app)
      new_session_get.get novels_path
      expect(new_session_get.response).to redirect_to(login_path)
    end
  end
end
