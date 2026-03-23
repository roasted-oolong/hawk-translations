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

    # --- M21: cover_art attachment via PATCH ---

    context "with a valid cover image" do
      it "attaches cover_art to the novel" do
        image = fixture_file_upload(
          Rails.root.join("spec/fixtures/files/cover.jpg"),
          "image/jpeg"
        )
        patch novel_path(novel), params: { novel: { cover_art: image } }
        expect(response).to redirect_to(novel_path(novel))
        expect(novel.reload.cover_art).to be_attached
      end
    end

    context "with an invalid cover image content type" do
      it "does not attach the file and re-renders edit" do
        gif = fixture_file_upload(
          Rails.root.join("spec/fixtures/files/cover.gif"),
          "image/gif"
        )
        patch novel_path(novel), params: { novel: { cover_art: gif } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(novel.reload.cover_art).not_to be_attached
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

  describe "DELETE /novels/:id/cover_art" do
    it "purges the cover_art attachment and redirects to the novel" do
      novel.cover_art.attach(
        io: StringIO.new("\xFF\xD8\xFF" + "x" * 100),
        filename: "cover.jpg",
        content_type: "image/jpeg"
      )
      expect(novel.cover_art).to be_attached

      delete cover_art_novel_path(novel)
      expect(response).to redirect_to(novel_path(novel))
      expect(novel.reload.cover_art).not_to be_attached
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
