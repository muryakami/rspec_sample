require 'spec_helper'

describe 'VolumeUsers API', type: :request do

  describe 'Sort Quick Access Projects', autodoc: true do
    subject { put '/volume_users/change_ranks', params }
    let(:json) { JSON.parse(response.body, symbolize_names: true) }
    let(:params)  { { ranks: rank_params } }

    before do
      3.times.each do
        prepare_volume(project_name: random_project_name, role: :owner)
      end
    end

    context 'Positive Condition' do
      # マイフォルダ以外のクイックアクセスプロジェクト
      let(:volume_users) { current_db_user.volume_users.where(quick_access: true).includes(:volume).where.not(volumes: {path: '/'}) }

      # ランダム性のあるテストは良くないと思う
      let(:volume_ids) { volume_users.pluck(:id) }
      let(:ranks) { volume_users.pluck(:rank).shuffle! }
      let(:rank_params) { volume_ids.map.zip(ranks).map{ |id, rank| "#{id}=#{rank}" } }

      let(:expected_result) { volume_ids.sort_by.with_index{ |id, i| ranks[i] } }

      context '全てのプロジェクトがクイックアクセスプロジェクトの場合' do
        it 'sorts volumes in rank order' do
          subject
          result = json.map{ |v| v[:id] }
          expect(response.status).to eq 200
          expect(result).to eq expected_result
        end
      end

      context 'クイックアクセスプロジェクト以外のプロジェクトが存在する場合' do
        before do
          # .first はマイフォルダ
          current_db_user.volume_users.last.update_attribute(:quick_access, false)
        end
        it 'sorts volumes in rank order' do
          subject
          result = json.map{ |v| v[:id] }
          expect(response.status).to eq 200
          expect(result).to eq expected_result
        end
      end
    end

    context 'Negative Condition' do
      context 'ranks で指定した値が空の場合' do
        let(:rank_params) { [] }
        it "receives BadRequest 'ranks_parameter_missing'" do
          subject
          expect(response.status).to eq 400
          expect(json[:code]).to eq 'ranks_parameter_missing'
        end
      end

      context 'ranks で指定した値が不正な場合' do
        let(:rank_params) { ["1=true", "2=false"] }
        it "receives BadRequest 'invalid_values'" do
          subject
          expect(response.status).to eq 400
          expect(json[:code]).to eq 'invalid_values'
        end
      end

      context 'ranks の id が不正な場合' do
        let(:rank_params) { ["9999999=1"] }
        it 'receives Forbidden' do
          subject
          expect(response.status).to eq 403
        end
      end

      context 'ranks を指定しなかった場合' do
        let(:params) { { target: "quick_access" } }
        it "receives BadRequest 'ranks_parameter_missing'" do
          subject
          expect(response.status).to eq 400
          expect(json[:code]).to eq 'ranks_parameter_missing'
        end
      end
    end
  end

  # index
  describe 'GET /volume_users', autodoc: true do
    PermissionManager::PROJECT_ROLES.each do |role|
      it "#{role.to_s.capitalize} get the volume_users information" do
        owner, volume_id = prepare_volume project_name: random_project_name, role: role
        v = owner.volumes.last
        vu = v.volume_users.last

        get '/volume_users', nil

        expect(response.status).to eq 200
        json = JSON.parse response.body
        last_json = json.last

        expect(last_json['id']).to eq vu.id
        expect(last_json['notified']).to eq vu.notified
        expect(last_json['role']).to eq vu.role
        expect(last_json['permissions']).to eq vu.permissions
        expect(last_json['volume']['id']).to eq v.id
        expect(last_json['volume']['name']).to eq v.name_without_prefix
      end
    end
  end

  describe 'GET /volume_users/:id', autodoc: true do
    it 'User get a rank of volume that he belongs to' do

      current_db_user
      project_name = random_project_name
      create_project account: current_account, path: "/#{project_name}" , type: Volume::Type::NORMAL
      # create_project(account: current_account, path: , type: Volume::Type::NORMAL)
      volume_user = current_db_user.volume_users.second

      get "/volume_users/#{volume_user.id}", nil

      expect(response.status).to eq 200
      json = JSON.parse response.body
      expect(json['rank']).to eq volume_user.rank
    end
  end

  describe 'GET /volume_users', autodoc: true do
    it 'User get all ranks of volume that he belongs to' do

      current_db_user
      project_name = random_project_name
      create_project account: current_account, path: "/#{project_name}" , type: Volume::Type::NORMAL
      ranks = []

      get "/volume_users", nil

      expect(response.status).to eq 200
      json = JSON.parse response.body
      json.each do |vu_hash|
        expect(vu_hash['rank']).to eq current_db_user.volume_users.find_by(id: vu_hash['id']).rank
      end
    end
  end
  # show
  describe 'GET /volume_users/:id', autodoc: true do
    PermissionManager::PROJECT_ROLES.each do |role|
      it "#{role.to_s.capitalize} get a volume_user information" do
        owner, volume_id = prepare_volume project_name: random_project_name, role: role
        v = owner.volumes.last
        vu = v.volume_users.last

        get "/volume_users/#{vu.id}", nil

        expect(response.status).to eq 200
        json = JSON.parse response.body

        expect(json['id']).to eq vu.id
        expect(json['notified']).to eq vu.notified
        expect(json['role']).to eq vu.role
        expect(json['permissions']).to eq vu.permissions
        expect(json['volume']['id']).to eq v.id
        expect(json['volume']['name']).to eq v.name_without_prefix
      end
    end

    it "You cannot get a volume_user that doesn't exist" do
      owner, volume_id = prepare_volume project_name: random_project_name, role: :owner
      v = owner.volumes.last
      vu = v.volume_users.last

      get "/volume_users/#{vu.id + 10000}", nil

      expect(response.status).to eq 404
      json = JSON.parse response.body
      expect(json['code']).to eq 'not_found'
    end
  end

  # update
  describe 'PUT /volume_users', autodoc: true do
    PermissionManager::PROJECT_ROLES.each do |role|
      it "#{role.to_s.capitalize} can update his own volume_user setting of notified" do
        owner, volume_id = prepare_volume project_name: random_project_name, role: role
        v = owner.volumes.last
        vu = v.volume_users.last
        _notified = [true, false].sample()

        volume_user_params = {
          notified: _notified,
        }

        put "/volume_users/#{vu.id}", volume_user_params

        expect(response.status).to eq 200
        json = JSON.parse response.body
        expect(json['id']).to eq vu.id
        expect(json['notified']).to eq _notified
        expect(json['role']).to eq vu.role
        expect(json['permissions']).to eq vu.permissions
        expect(json['volume']['id']).to eq v.id
        expect(json['volume']['name']).to eq v.name_without_prefix
      end
    end

    PermissionManager::PROJECT_ROLES.each do |current_role|
      PermissionManager::PROJECT_ROLES.each do |target_role|
        manageable = [:owner, :manager].include? current_role
        it PermissionManager.instance.description("#{current_role} update a #{target_role} volume_user role", manageable) do
          owner, volume_id = prepare_volume project_name: random_project_name, role: current_role
          v = owner.volumes.last
          vu = v.volume_users.last
          _role = Object.const_get("VolumeRole::#{target_role.upcase}")

          volume_user_params = {
            role: _role
          }

          put "/volume_users/#{vu.id}", volume_user_params

          if manageable
            expect(response.status).to eq 200
            json = JSON.parse response.body
            expect(json['id']).to eq vu.id
            expect(json['notified']).to eq vu.notified
            expect(json['role']).to eq _role
            expect(json['volume']['id']).to eq v.id
            expect(json['volume']['name']).to eq v.name_without_prefix
          else
            expect(response.status).to eq 400
            json = JSON.parse response.body
            expect(json['code']).to eq 'not_permitted'
          end
        end
      end
    end

    it 'You cannot update a volume_user setting of notified when the params is invalid' do
      owner, volume_id = prepare_volume project_name: random_project_name, role: :owner
      v = owner.volumes.last
      vu = v.volume_users.last

      volume_user_params = {
        notified: 'true',
      }

      put "/volume_users/#{vu.id}", volume_user_params

      expect(response.status).to eq 400
      json = JSON.parse response.body
      expect(json['code']).to eq 'invalid_notified_type_error'
    end

    it 'You cannot update the role when the param is invalid' do
      owner, volume_id = prepare_volume project_name: random_project_name, role: :owner
      v = owner.volumes.last
      vu = v.volume_users.last

      volume_user_params = {
        role: '1'
      }

      put "/volume_users/#{vu.id}", volume_user_params

      expect(response.status).to eq 400
      json = JSON.parse response.body
      expect(json['code']).to eq 'invalid_role_type_error'
    end

    it 'You cannot update the role when the param is out of range' do
      owner, volume_id = prepare_volume project_name: random_project_name, role: :owner
      v = owner.volumes.last
      vu = v.volume_users.last

      volume_user_params = {
        role: VolumeRole::ALL.max + 1
      }

      put "/volume_users/#{vu.id}", volume_user_params

      expect(response.status).to eq 400
      json = JSON.parse response.body
      expect(json['code']).to eq 'invalid_role_range_error'
    end

  end

  # volume_index
  describe 'GET /volumes/:id/volume_users', autodoc: true do
    PermissionManager::PROJECT_ROLES.each do |role|
      it "#{role.to_s.capitalize} get the volume_index information" do
        owner, volume_id = prepare_volume project_name: random_project_name, role: role
        v = owner.volumes.last
        vu = v.volume_users.last

        get "/volumes/#{v.id}/volume_users", nil

        expect(response.status).to eq 200
        json = JSON.parse response.body
        latest_volume_user_json = json['entries'].last

        expect(json['total_count']).to eq v.volume_users.count
        expect(json['limit']).to eq 100 # Default
        expect(json['offset']).to eq 0 # Default
        expect(latest_volume_user_json['id']).to eq vu.id
        expect(latest_volume_user_json['volume_id']).to eq vu.volume_id
        expect(latest_volume_user_json['user_id']).to eq vu.user_id
        expect(latest_volume_user_json['user_login']).to eq vu.db_user.login
        expect(latest_volume_user_json['role']).to eq vu.role
        expect(latest_volume_user_json['permissions']).to eq vu.permissions
      end

      it "#{role.to_s.capitalize} cannot get the volume_index information when the volume does not exist" do
        owner, volume_id = prepare_volume project_name: random_project_name, role: role
        v = owner.volumes.last
        vu = v.volume_users.last

        get "/volumes/#{v.id + 10000}/volume_users", nil

        expect(response.status).to eq 404
        json = JSON.parse response.body
        expect(json['code']).to eq 'not_found'
      end
    end
  end
end
