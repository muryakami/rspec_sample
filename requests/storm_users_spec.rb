require 'spec_helper'

describe 'StormUsers API', type: :request do
  let(:json) { JSON.parse(response.body) }
  let(:target_account) { create(:pam_gluster_admin_account, enterprise: current_enterprise) }
  let(:target_account_id) { target_account.id }
  let(:storm_server) { create(:storm_server) }

  before do
    current_enterprise.settings(:storm).update_attributes(enable: true)
    current_enterprise.update_attributes(max_storm_user_account: 5)
    any_instance_of(StormServer) do |server|
      stub(server).create_user { Struct.new(:body).new('{"user_id": 1}') }
      stub(server).destroy_user { Struct.new(:status_code).new(204) }
      stub(server).update_user { Struct.new(:status_code).new(204) }
      stub(server).bulk_update_users { Struct.new(:status_code, :body).new(200, '{"bandrate": 100, "bandwidth": 0}') }
    end
  end

  describe 'POST /storm_users/:user_id', autodoc: true do
    subject { post "/storm_users/#{target_account_id}", params }

    let(:bandrate) { 100 }
    let(:params) { { bandrate: bandrate } }

    context 'Positive Condition' do
      it "saves the new StormUser in the database" do
        storm_server
        StormUser.destroy_all
        current_enterprise.update!(registered_storm_user_accounts: 0)
        expect do
          subject
        end.to change(StormUser, :count).from(0).to(1)
        expect(response.status).to eq 200
        expect(json["account_id"]).to eq target_account_id
        expect(json["storm_user"]["bandrate"]).to eq bandrate
        current_enterprise.reload
        expect(current_enterprise.registered_storm_user_accounts).to eq 1
      end
    end

    context 'Negative Condition' do
      context "when target account does not exist" do
        let(:target_account_id) { 1111111111 }
        it "receives BadRequest 'account_not_found'" do
          subject
          expect(response.status).to eq 400
          expect(json['code']).to eq 'account_not_found'
        end
      end
      context "when current account's role isn't OWNER" do
        it "receives BadRequest 'unpermitted_account'" do
          current_account.update!(role: Account::GENERAL)
          subject
          expect(response.status).to eq 400
          expect(json['code']).to eq 'unpermitted_account'
        end
      end
      context "when enterprise of target account is different from enterprise of current account" do
        let(:enterprise) { create(:pam_gluster_enterprise) }
        let(:target_account) { create(:pam_gluster_admin_account, enterprise: enterprise) }
        it "receives BadRequest 'unpermitted_account'" do
          subject
          expect(response.status).to eq 400
          expect(json['code']).to eq 'unpermitted_account'
        end
      end
      context "when enterprise settings[:storm] is disable" do
        it "receives BadRequest 'unpermitted_enterprise'" do
          current_enterprise.settings(:storm).update_attributes(enable: false)
          subject
          expect(response.status).to eq 400
          expect(json['code']).to eq 'unpermitted_enterprise'
        end
      end
      context "when action_name is create_user" do
        context "when the number of registered accounts exceeds the upper limit" do
          it "receives BadRequest 'storm_user_count_reached'" do
            current_enterprise.update_attributes(max_storm_user_account: 0)
            subject
            expect(response.status).to eq 400
            expect(json['code']).to eq 'storm_user_count_reached'
          end
        end
        context "when StormUser account already exists" do
          it "receives BadRequest 'already_exists'" do
            create(:storm_user, account: target_account, storm_server: storm_server)
            subject
            expect(response.status).to eq 400
            expect(json['code']).to eq 'already_exists'
          end
        end
      end
      context "when params[:bandrate] is not Integer instance" do
        let(:bandrate) { '100' }
        it "receives BadRequest 'invalid_bandrate'" do
          subject
          expect(response.status).to eq 400
          expect(json['code']).to eq 'invalid_bandrate'
        end
      end
      # TODO: status code が統一できていないので pending
      xcontext "when JECTOR Application receives the status code except for xxx from STORM Server" do
        it "receives 'create_storm_user_error'" do
          any_instance_of(StormServer) do |server|
            stub(server).create_user { Struct.new(:status_code).new(500) }
          end
          subject
          expect(response.status).to eq 500
          expect(json['code']).to eq 'create_storm_user_error'
        end
      end
    end
  end

  describe 'DELETE /storm_users/:user_id', autodoc: true do
    subject { delete "/storm_users/#{target_account_id}", {} }

    context 'Positive Condition' do
      it "deletes the StormUser in the database" do
        StormUser.destroy_all
        create(:storm_user, account: target_account, storm_server: storm_server)
        current_enterprise.update!(registered_storm_user_accounts: 1)
        expect do
          subject
        end.to change(StormUser, :count).from(1).to(0)
        expect(response.status).to eq 200
        expect(json['status']).to eq 204
        current_enterprise.reload
        expect(current_enterprise.registered_storm_user_accounts).to eq 0
      end
    end

    context 'Negative Condition' do
      context "when target account does not exist" do
        let(:target_account_id) { 1111111111 }
        it "receives BadRequest 'account_not_found'" do
          subject
          expect(response.status).to eq 400
          expect(json['code']).to eq 'account_not_found'
        end
      end
      context "when current account's role isn't OWNER" do
        it "receives BadRequest 'unpermitted_account'" do
          current_account.update!(role: Account::GENERAL)
          subject
          expect(response.status).to eq 400
          expect(json['code']).to eq 'unpermitted_account'
        end
      end
      context "when enterprise of target account is different from enterprise of current account" do
        let(:enterprise) { create(:pam_gluster_enterprise) }
        let(:target_account) { create(:pam_gluster_admin_account, enterprise: enterprise) }
        it "receives BadRequest 'unpermitted_account'" do
          subject
          expect(response.status).to eq 400
          expect(json['code']).to eq 'unpermitted_account'
        end
      end
      context "when enterprise settings[:storm] is disable" do
        it "receives BadRequest 'unpermitted_enterprise'" do
          current_enterprise.settings(:storm).update_attributes(enable: false)
          subject
          expect(response.status).to eq 400
          expect(json['code']).to eq 'unpermitted_enterprise'
        end
      end
      context "when JECTOR Application receives the status code except for 204 from STORM Server" do
        it "receives 'destroy_storm_user_error'" do
          any_instance_of(StormServer) do |server|
            stub(server).destroy_user { Struct.new(:status_code).new(500) }
          end
          create(:storm_user, account: target_account, storm_server: storm_server)
          subject
          expect(response.status).to eq 500
          expect(json['code']).to eq 'destroy_storm_user_error'
        end
      end
    end

    describe 'PATCH /storm_users/:user_id', autodoc: true do
      subject { patch "/storm_users/#{target_account_id}", params }

      let(:bandrate) { 100 }
      let(:params) { { bandrate: bandrate } }

      context 'Positive Condition' do
        it "updates the StormUser in the database" do
          StormUser.destroy_all
          create(:storm_user, account: target_account, storm_server: storm_server)
          expect do
            subject
          end.not_to change(StormUser, :count)
          expect(response.status).to eq 200
          expect(json["account_id"]).to eq target_account_id
          expect(json["storm_user"]["bandrate"]).to eq bandrate
        end
      end

      context 'Negative Condition' do
        context "when target account does not exist" do
          let(:target_account_id) { 1111111111 }
          it "receives BadRequest 'account_not_found'" do
            subject
            expect(response.status).to eq 400
            expect(json['code']).to eq 'account_not_found'
          end
        end
        context "when current account's role isn't OWNER" do
          it "receives BadRequest 'unpermitted_account'" do
            current_account.update!(role: Account::GENERAL)
            subject
            expect(response.status).to eq 400
            expect(json['code']).to eq 'unpermitted_account'
          end
        end
        context "when enterprise of target account is different from enterprise of current account" do
          let(:enterprise) { create(:pam_gluster_enterprise) }
          let(:target_account) { create(:pam_gluster_admin_account, enterprise: enterprise) }
          it "receives BadRequest 'unpermitted_account'" do
            subject
            expect(response.status).to eq 400
            expect(json['code']).to eq 'unpermitted_account'
          end
        end
        context "when enterprise settings[:storm] is disable" do
          it "receives BadRequest 'unpermitted_enterprise'" do
            current_enterprise.settings(:storm).update_attributes(enable: false)
            subject
            expect(response.status).to eq 400
            expect(json['code']).to eq 'unpermitted_enterprise'
          end
        end
        context "when params[:bandrate] is not Integer instance" do
          let(:bandrate) { '100' }
          it "receives BadRequest 'invalid_bandrate'" do
            subject
            expect(response.status).to eq 400
            expect(json['code']).to eq 'invalid_bandrate'
          end
        end
        context "when JECTOR Application receives the status code except for 204 from STORM Server" do
          it "receives 'update_storm_user_error'" do
            any_instance_of(StormServer) do |server|
              stub(server).update_user { Struct.new(:status_code).new(500) }
            end
            StormUser.destroy_all
            create(:storm_user, account: target_account, storm_server: storm_server)
            subject
            expect(response.status).to eq 500
            expect(json['code']).to eq 'update_storm_user_error'
          end
        end
      end
    end

    describe 'PATCH enterprises/:enterprise_id/storm_users/settings', autodoc: true do
      subject { patch "/enterprises/#{target_enterprise_id}/storm_users/settings", params }

      let(:target_enterprise_id) { current_enterprise.id }
      let(:default_bandrate) { 100 }
      let(:params) { { bandrate: default_bandrate } }
      let(:other_target_account) { create(:pam_gluster_admin_account, enterprise: current_enterprise) }
      let(:non_target_account) { create(:pam_gluster_admin_account, enterprise: current_enterprise) }

      context 'Positive Condition' do
        it "updates the target StormUsers in the database" do
          StormUser.destroy_all
          create(:storm_user, account: target_account, storm_server: storm_server)
          create(:storm_user, account: other_target_account, storm_server: storm_server)
          non_target_account
          expect do
            subject
          end.not_to change(StormUser, :count)
          expect(response.status).to eq 200
          expect(json['settings']['storm']['default_bandrate']).to eq default_bandrate
        end
      end

      context 'Negative Condition' do
        context "when enterprise settings[:storm] is disable" do
          it "receives BadRequest 'unpermitted_enterprise'" do
            current_enterprise.settings(:storm).update_attributes(enable: false)
            subject
            expect(response.status).to eq 400
            expect(json['code']).to eq 'unpermitted_enterprise'
          end
        end
        context "when params[:bandrate] is not Integer instance" do
          let(:default_bandrate) { '100' }
          it "receives BadRequest 'invalid_bandrate'" do
            subject
            expect(response.status).to eq 400
            expect(json['code']).to eq 'invalid_bandrate'
          end
        end
        context "when JECTOR Application receives the status code except for 200 from STORM Server" do
          it "receives 'bulk_update_storm_users_error'" do
            any_instance_of(StormServer) do |server|
              stub(server).bulk_update_users { Struct.new(:status_code).new(500) }
            end
            StormUser.destroy_all
            create(:storm_user, account: target_account, storm_server: storm_server)
            create(:storm_user, account: other_target_account, storm_server: storm_server)
            non_target_account
            subject
            expect(response.status).to eq 500
            expect(json['code']).to eq 'bulk_update_storm_users_error'
          end
        end
      end
    end

  end
end
