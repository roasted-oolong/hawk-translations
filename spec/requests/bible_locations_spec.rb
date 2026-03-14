require "rails_helper"

RSpec.describe "BibleLocations", type: :request do
  let(:user)     { create(:user) }
  let(:novel)    { create(:novel) }
  let!(:location) { create(:bible_location, novel: novel, name: "Seoul Arena") }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/bible_locations" do
    it "returns 200 and lists locations" do
      get novel_bible_locations_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_locations/:id" do
    it "returns 200 and shows the location" do
      get novel_bible_location_path(novel, location)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /novels/:novel_id/bible_locations/new" do
    it "returns 200" do
      get new_novel_bible_location_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /novels/:novel_id/bible_locations" do
    context "with valid params" do
      it "creates a location and redirects to show" do
        expect {
          post novel_bible_locations_path(novel), params: {
            bible_location: { name: "Busan Stadium", location_type: "Arena" }
          }
        }.to change(BibleLocation, :count).by(1)

        expect(response).to redirect_to(novel_bible_location_path(novel, BibleLocation.last))
      end
    end

    context "with missing name" do
      it "does not create a location and re-renders new" do
        expect {
          post novel_bible_locations_path(novel), params: {
            bible_location: { name: nil }
          }
        }.not_to change(BibleLocation, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /novels/:novel_id/bible_locations/:id/edit" do
    it "returns 200" do
      get edit_novel_bible_location_path(novel, location)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /novels/:novel_id/bible_locations/:id" do
    it "updates and redirects to show" do
      patch novel_bible_location_path(novel, location), params: {
        bible_location: { location_type: "Stadium" }
      }
      expect(response).to redirect_to(novel_bible_location_path(novel, location))
      expect(location.reload.location_type).to eq("Stadium")
    end

    it "re-renders edit on invalid params" do
      patch novel_bible_location_path(novel, location), params: {
        bible_location: { name: "" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /novels/:novel_id/bible_locations/:id" do
    it "destroys the location and redirects to index" do
      expect {
        delete novel_bible_location_path(novel, location)
      }.to change(BibleLocation, :count).by(-1)

      expect(response).to redirect_to(novel_bible_locations_path(novel))
    end
  end
end
