require 'rails_helper'

describe EmailPreferencesController, :type => :controller do
  let(:deposit)   { EmailPreference.create(author: 'John Doe', monthly_opt_out: false, email: 'john.doe@example.com') }

  describe 'GET index' do
    include_examples 'authorization required' do
      let(:request) { get :index }
    end
  end

  describe 'GET show' do
    include_examples 'authorization required' do
      let(:request) { get :show, id: deposit.id }
    end
  end

  describe 'GET new' do
    include_examples 'authorization required' do
      let(:request) { get :new }
    end
  end

  describe 'POST create' do
    let(:request) {
      post :create, email_preference: { author: 'John Doe', monthly_opt_out: true, email: 'john.doe@example.com' }
    }

    context "without being logged in" do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
        request
      end

      it "redirects to new_user_session_path" do
        expect(response.status).to eql(302)
        expect(response.headers['Location']).to eql(new_user_session_url)
      end
    end

    context "logged in as a non-admin user" do
      include_context 'mock non-admin user'

      before do
        request
      end

      it "fails" do
        expect(response.status).to eql(302)
        expect(response.headers['Location']).to eql(access_denied_url)
      end
    end

    context "logged in as an admin user" do
      include_context 'mock admin user'

      before do
        request
      end

      it "succeeds" do
        expect(response).to redirect_to email_preference_url(EmailPreference.first.id)
      end
    end
  end

  describe 'GET edit' do
    include_examples 'authorization required' do
      let(:request) { get :edit, id: deposit.id}
    end
  end

  describe 'PUT update' do
    let(:request) { put :update, id: deposit.id }

    context "without being logged in" do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
        request
      end

      it "redirects to new_user_session_path" do
        expect(response.status).to eql(302)
        expect(response.headers['Location']).to eql(new_user_session_url)
      end
    end

    context "logged in as a non-admin user" do
      include_context 'mock non-admin user'

      before do
        request
      end

      it "fails" do
        expect(response.status).to eql(302)
        expect(response.headers['Location']).to eql(access_denied_url)
      end
    end

    context "logged in as an admin user" do
      include_context 'mock admin user'

      before do
        request
      end

      it "succeeds" do
        expect(response).to redirect_to email_preference_url(deposit.id)
      end
    end
  end

  describe 'DELETE destroy' do
    let(:request) { delete :destroy, id: deposit.id }

    context "without being logged in" do
      before do
        allow(controller).to receive(:current_user).and_return(nil)
        request
      end

      it "redirects to new_user_session_path" do
        expect(response.status).to eql(302)
        expect(response.headers['Location']).to eql(new_user_session_url)
      end
    end

    context "logged in as a non-admin user" do
      include_context 'mock non-admin user'

      before do
        request
      end

      it "fails" do
        expect(response.status).to eql(302)
        expect(response.headers['Location']).to eql(access_denied_url)
      end
    end

    context "logged in as an admin user" do
      include_context 'mock admin user'

      before do
        request
      end

      it "succeeds" do # Redirects to index page on success.
        expect(response).to redirect_to email_preferences_url
      end
    end
  end
end
