require 'spec_helper'
describe 'Enterprise', type: :model do
  it 'You can clean-up enterprise' do
    enterprise = create :pam_gluster_enterprise
    account = create :account, :pam_gluster, :admin, enterprise: enterprise
    user = account.db_user
    user_id = user.id
    enterprise_id = enterprise.id
    account_id = account.id
    path = enterprise.root_path
    moved_path = enterprise.storage_address + '/' + LocalEnterprise::TMP_DIR_NAME + '/' + enterprise.access_key

    enterprise.cleanup_enterprise!

    deleted_account = Account.only_deleted.find account_id
    deleted_enterprise = Enterprise.only_deleted.find enterprise_id
    deleted_user = DbUser.only_deleted.find user_id

    expect(deleted_enterprise.name).to eq "deleted-"+enterprise_id.to_s
    expect(deleted_enterprise.domain).to eq "deleted-"+enterprise_id.to_s

    expect(deleted_account.group_id).to eq nil
    expect(deleted_account.post).to eq nil

    expect(deleted_user.email).to eq nil
    expect(deleted_user.name).to eq nil
    expect(deleted_user.first_name).to eq nil
    expect(deleted_user.family_name).to eq nil

    expect(File.exist? path).to eq false
    expect(File.exist? moved_path).to eq true
  end

  it 'You cannot clean-up enterprises directory if access_key is nothing' do
    enterprise = create :pam_gluster_enterprise
    account = create :account, :pam_gluster, :admin, enterprise: enterprise
    user = account.db_user
    user_id = user.id
    enterprise_id = enterprise.id
    account_id = account.id
    path = enterprise.root_path
    enterprise.update! access_key: nil

    expect {enterprise.cleanup_enterprise!}.to raise_error Enterprise::InvalidPathError

    expect(Account.find(account_id) == account).to eq true
    expect(Enterprise.find(enterprise_id) == enterprise).to eq true
    expect(DbUser.find(user_id) == user).to eq true

    expect(File.exist? path).to eq true
  end

  it 'You can clean-up enterprise association' do
    init_string = "initial3"
    enterprise = create :pam_gluster_enterprise
    account = create :account, :pam_gluster, :admin, enterprise: enterprise
    user = account.db_user
    file_name = random_entry_name
    file_id = create_file account: account, path: "/#{file_name}"

    add_item_box account: account
    add_item_mail account: account
    add_comment account: account, id: file_id, message: Faker::Lorem.sentence
    findex = Findex.last
    add_group enterprise: enterprise
    Address.create! account_id: account.id, email: user.email
    AddressGroup.create! account_id: account.id
    property = Property.create! volume_id: enterprise.volumes[0].id, type: "StringProperty", name: init_string
    PropertyValue.create! fid: findex.fid, property_id: property.id
    Tag.create! findex_id: findex.id, word: init_string, created_by: account.id
    send_to_trash account: account, item_id: file_id

    enterprise_id = enterprise.id
    user_id = user.id

    expect(Address.all.present?).to eq true
    expect(AddressGroup.all.present?).to eq true
    expect(Findex.all.present?).to eq true
    expect(ItemComment.all.present?).to eq true
    expect(Group.all.present?).to eq true
    expect(ItemBox.all.present?).to eq true
    expect(ItemMail.all.present?).to eq true
    expect(Message.all.present?).to eq true
    expect(Volume.find_by(enterprise_id: enterprise_id).present?).to eq true
    expect(VolumeUser.find_by(user_id: user_id).present?).to eq true
    expect(Property.all.present?).to eq true
    expect(PropertyValue.all.present?).to eq true
    expect(Tag.all.present?).to eq true
    expect(PostedItem.all.present?).to eq true
    expect(LocalTrashItem.all.present?).to eq true
    expect(Destination.all.present?).to eq true
    expect(PostedItemDestination.all.present?).to eq true

    enterprise.cleanup_enterprise!

    expect(Address.all.present?).to eq false
    expect(AddressGroup.all.present?).to eq false
    expect(Findex.all.present?).to eq false
    expect(ItemComment.all.present?).to eq false
    expect(Group.all.present?).to eq false
    expect(ItemBox.all.present?).to eq false
    expect(ItemMail.all.present?).to eq false
    expect(Message.all.present?).to eq false
    expect(Volume.find_by(enterprise_id: enterprise_id).present?).to eq false
    expect(VolumeUser.find_by(user_id: user_id).present?).to eq false
    expect(Property.all.present?).to eq false
    expect(PropertyValue.all.present?).to eq false
    expect(Tag.all.present?).to eq false
    expect(PostedItem.all.present?).to eq false
    expect(LocalTrashItem.all.present?).to eq false
    expect(Destination.all.present?).to eq false
    expect(PostedItemDestination.all.present?).to eq false
  end

  describe '#same_email_user' do
    let(:enterprise) { create(:pam_gluster_enterprise) }
    subject { enterprise.same_email_user(email) }
    context 'when email is duplicate' do
      let(:email) { account.db_user.email }
      context 'when same Enterprise' do
        let(:account) { create(:pam_gluster_admin_account, enterprise: enterprise) }
        it { is_expected.to eq account.db_user }
      end
      context 'when other Enterprise' do
        let(:account) { create(:pam_gluster_admin_account, enterprise: create(:pam_gluster_enterprise)) }
        it { is_expected.to eq nil }
      end
    end
    context 'when email is unique' do
      let(:email) { Faker::Internet.safe_email }
      it { is_expected.to eq nil }
    end
  end

  describe '#apply_contract' do
    subject { enterprise.apply_contract(contract) }

    let(:enterprise) { create(:pam_gluster_enterprise) }
    let(:contract) { create_contract(enterprise: enterprise, params: params) }

    let(:accounts) { enterprise.max_account }
    let(:quota) { enterprise.quota }
    let(:free_visitors) { nil }
    let(:charge_visitors) { nil }
    let(:partners) { nil }
    let(:storm_users) { nil }
    let(:params) { { accounts: accounts, quota: quota, free_visitors: free_visitors, charge_visitors: charge_visitors, partners: partners, storm_users: storm_users } }

    context 'Positive Condition' do
      
      #max_account: contract[:accounts]
      context 'when max_account parameter is received' do
        let(:accounts) { enterprise.max_account + 1 }
        it 'sets max_account column to value of contract[:accounts]' do
          subject
          expect(enterprise.max_account).to eq accounts
        end
      end

      # max_visitor_account: (contract[:free_visitors] || contract[:accounts] * 5) + (contract[:charge_visitors] || 0)
      context 'when max_visitor_account parameter is received' do
        context 'when contract[:free_visitors] is present' do
          let(:accounts) { enterprise.max_account }
          let(:free_visitors) { enterprise.max_visitor_account + 1 }
          let(:charge_visitors) { nil }
          it 'sets max_visitor_account column to value of contract[:free_visitors]' do
            subject
            expect(enterprise.max_visitor_account).to eq free_visitors
          end
        end
        context 'when contract[:free_visitors] is not present' do
          let(:accounts) { enterprise.max_account + 1 }
          let(:free_visitors) { nil }
          let(:charge_visitors) { nil }
          it 'sets max_partner_account column to 5 times value of contract[:accounts]' do
            subject
            expect(enterprise.max_visitor_account).to eq (accounts * 5)
          end
        end
        context 'when contract[:charge_visitors] is present' do
          let(:accounts) { enterprise.max_account }
          let(:free_visitors) { enterprise.max_visitor_account }
          let(:charge_visitors) { 1 }
          it 'sets max_visitor_account column to total value of contract[:free_visitors] & contract[:charge_visitors]' do
            subject
            expect(enterprise.max_visitor_account).to eq (free_visitors + charge_visitors)
          end
        end
        context 'when contract[:charge_visitors] is not present' do
          let(:accounts) { enterprise.max_account }
          let(:free_visitors) { enterprise.max_visitor_account + 1 }
          let(:charge_visitors) { nil }
          it 'sets max_visitor_account column to total value of contract[:free_visitors] & 0' do
            subject
            expect(enterprise.max_visitor_account).to eq (free_visitors + 0)
          end
        end
      end

      # max_partner_account: (contract[:partners] || 0)
      context 'when max_partner_account parameter is received' do
        context 'when contract[:partner] is present' do
          let(:partners) { enterprise.max_partner_account + 1 }
          it 'sets max_partner_account column to value of contract[:partner]' do
            subject
            expect(enterprise.max_partner_account).to eq partners
          end
        end
        context 'when contract[:partner] is not present' do
          let(:partners) { nil }
          it 'sets max_partner_account column to 0' do
            subject
            expect(enterprise.max_partner_account).to eq 0
          end
        end
      end

      # max_storm_user_account: (contract[:storm_users] || 0)
      context 'when max_storm_user_account parameter is received' do
        context 'when contract[:storm_users] is present' do
          let(:storm_users) { enterprise.max_storm_user_account + 1 }
          it 'sets max_storm_user_account column to value of contract[:storm_users]' do
            subject
            expect(enterprise.max_storm_user_account).to eq storm_users
          end
        end
        context 'when contract[:storm_users] is not present' do
          let(:storm_users) { nil }
          it 'sets max_storm_user_account column to 0' do
            subject
            expect(enterprise.max_storm_user_account).to eq 0
          end
        end
      end

      # quota: contract[:quota]
      context 'when quota parameter is received' do
        context 'when value of enterprise[:quota] is equal to value of contract[:quota]' do
          let(:quota) { enterprise.quota }
          it 'do not changes quota column' do
            subject
            expect(enterprise.quota).to eq quota
          end
        end
        context 'when value of enterprise[:quota] is not equal to value of contract[:quota]' do
          let(:quota) { enterprise.quota + 10.gigabyte }
          before do
            admin_account = create(:pam_gluster_admin_account, enterprise: enterprise)
          end
          it "sets quota of FolderItemFactory instance" do
            mock.proxy(FolderItemFactory).new(enterprise: enterprise, account: enterprise.accounts.first) { |obj|
              mock(obj).set_quota(path: obj.root, quota: enterprise.quota, action: "contract")
            }
            subject
          end
          it "updates quota of each account of belonging to itself" do
            enterprise.accounts.each { |account|
              mock(account).update!(quota: quota)
            }
            subject
          end
          it 'changes quota column to value of contract[:quota]' do
            subject
            expect(enterprise.quota).to eq quota
          end
        end
      end
    end
  end

  describe "SETTINGS_PARAMS" do
    context "EnterpriseSettingsForEnviroment が差分だけ書かれていた場合" do
      before {
        stub(EnterpriseSettingsForEnviroment).keys_to_sym { 
          {
            files: {
              # activate_favorites のデフォルトが false であるということが前提の悪いコード
              activate_favorites: true,
              allowed_roles: [999]
            }
          }
        }
      }
      let(:enterprise) { create(:pam_gluster_enterprise) }
      it "差分に書いたキーが存在すること" do
        expect(true).to eq Enterprise::SETTINGS_PARAMS[:files].key?(:activate_favorites)
      end
      it "差分が適用されていること" do
        expect(true).to eq Enterprise::SETTINGS_PARAMS[:files][:activate_favorites]
      end
      it "差分以外のキーが消失していないこと" do
        expect(true).to eq Enterprise::SETTINGS_PARAMS[:files].key?(:by_group)
      end
      it "差分以外はデフォルトが使用されていること" do
        expect(Enterprise::DEFAULT_PARAMS[:files][:by_group]).to eq Enterprise::SETTINGS_PARAMS[:files][:by_group]
      end
      context "差分が配列だった場合" do
        it "配列が置き換えられていること" do
          expect([999]).to eq Enterprise::SETTINGS_PARAMS[:files][:allowed_roles]
        end
      end
    end
  end

end
