require 'spec_helper'

describe 'Contract', type: :model do
  describe '#set_service' do
    context '正常系' do
      it 'You can add_service_from_name' do
        account = create(:pam_gluster_admin_account)
        enterprise = account.enterprise
        create_current_contract(enterprise, account, plan: 'Enterprise', pay_type: 'PayMethod::ManualPay')
        contract = enterprise.contracts.last

        expect{
          contract.add_service_from_name('UnitUser')
        }.to_not raise_error
      end

      it 'You can set_service exist Service' do
        account = create(:pam_gluster_admin_account)
        enterprise = account.enterprise
        create_current_contract(enterprise, account, plan: 'Enterprise', pay_type: 'PayMethod::ManualPay')
        contract = enterprise.contracts.last

        services = {
          accounts: { multiplier:  5, name: 'UnitUser'    },
          quota:    { multiplier: 20, name: 'UnitGB'      },
          partner:  { multiplier:  0, name: 'UnitPartner' }
        }

        expect{ 
          contract.set_services(services: services) 
        }.not_to raise_error
      end

      it 'You can set_service exist Service for Motionbase' do
        account = create(:pam_gluster_admin_account)
        enterprise = account.enterprise
        create_current_contract(enterprise, account, plan: 'Motionbase', pay_type: 'PayMethod::ManualPay', type: 'MotionbaseContract')
        contract = enterprise.contracts.last

        services = {
          accounts: { multiplier:  5, name: 'UnitSilverUser'    },
          quota:    { multiplier: 20, name: 'UnitGB'      },
          partner:  { multiplier:  0, name: 'UnitPartner' }
        }

        expect{ 
          contract.set_services(services: services) 
        }.not_to raise_error
      end
    end

    context '異常系' do
      it 'You can not add_service_from_name by invalid service' do
        account = create(:pam_gluster_admin_account)
        enterprise = account.enterprise
        create_current_contract(enterprise, account, plan: 'Enterprise', pay_type: 'PayMethod::ManualPay')
        contract = enterprise.contracts.last

        expect{
          contract.add_service_from_name('ZETTAINI_SONZAISHINAI_SERVICE_NAME!!!')
        }.to raise_error(Contract::InvalidServiceError)
      end

      it 'You can not set_service not exists Service' do
        account = create(:pam_gluster_admin_account)
        enterprise = account.enterprise
        create_current_contract(enterprise, account, plan: 'Enterprise', pay_type: 'PayMethod::ManualPay')
        contract = enterprise.contracts.last

        services = {
          accounts: { multiplier:  5, name: 'ZETTAINI_SONZAISHINAI_SERVICE!!!'},
          quota:    { multiplier: 20, name: 'UnitGB'      },
          partner:  { multiplier:  0, name: 'UnitPartner' }
        }

        expect{
          contract.set_services(services: services) 
        }.to raise_error(Contract::InvalidServiceError)
      end

      it 'You can not set_service not accept Service' do
        account = create(:pam_gluster_admin_account)
        enterprise = account.enterprise
        create_current_contract(enterprise, account, plan: 'Enterprise', pay_type: 'PayMethod::ManualPay')
        contract = enterprise.contracts.last

        services = {
          accounts: { multiplier:  5, name: 'UnitSilverUser'},
          quota:    { multiplier: 20, name: 'UnitGB'      },
          partner:  { multiplier:  0, name: 'UnitPartner' }
        }

        expect{
          contract.set_services(services: services) 
        }.to raise_error(Contract::InvalidServiceError)
      end

      it 'You can not set_service not accept Service for MOTIONBASE' do
        account = create(:pam_gluster_admin_account)
        enterprise = account.enterprise
        create_current_contract(enterprise, account, plan: 'Motionbase', pay_type: 'PayMethod::ManualPay', type: 'MotionbaseContract')
        contract = enterprise.contracts.last

        services = {
          accounts: { multiplier:  5, name: 'UnitUser'    },
          quota:    { multiplier: 20, name: 'UnitGB'      },
          partner:  { multiplier:  0, name: 'UnitPartner' }
        }

        expect{
          contract.set_services(services: services) 
        }.to raise_error(Contract::InvalidServiceError)
      end
    end
  end

  describe '#final_set' do
    subject { contract.final_set(params) }
    let(:enterprise) { create(:pam_gluster_enterprise) }
    let(:contract) { create(:contract, enterprise: enterprise) }
    let(:accounts) { enterprise.max_account }
    let(:quota) { enterprise.quota }
    let(:visitors) { enterprise.max_visitor_account }
    let(:partners) { enterprise.max_partner_account }
    let(:storm_users) { enterprise.max_storm_user_account }
    let(:services) { {
      accounts: { multiplier:  5, name: 'UnitUser'    },
      quota:    { multiplier: 20, name: 'UnitGB'      },
      partner:  { multiplier:  0, name: 'UnitPartner' }
    } }
    let(:params) { { accounts: accounts, quota: quota, visitors: visitors, partners: partners, services: services, storm_users: storm_users } }
    context 'Positive Condition' do
      it 'calls #set_services with services argument' do
        mock(contract).set_services(services: services)
        subject
      end
      it 'calls #update! with arguments' do
        mock(contract).update!(accounts: accounts, quota: quota, free_visitors: nil, charge_visitors: visitors, partners: partners, storm_users: storm_users)
        subject
      end
      context 'when visitors parameter is received' do
        let(:visitors) { enterprise.max_visitor_account + 1 }
        it 'updates charge_visitors column to value of visitors' do
          subject
          expect(contract.charge_visitors).to eq visitors
        end
      end
      context 'when visitors parameter is not received' do
        let(:params) { { accounts: accounts, quota: quota, partners: partners, services: services, storm_users: storm_users } }
        it 'updates charge_visitors column to default value' do
          subject
          expect(contract.charge_visitors).to eq Contract::DEFAULT_CHARGE_VISITOR
        end
      end
      context 'when storm_users parameter is received' do
        let(:storm_users) { enterprise.max_storm_user_account + 1 }
        it 'updates storm_users column to value of storm_users' do
          subject
          expect(contract.storm_users).to eq storm_users
        end
      end
      context 'when storm_users parameter is not received' do
        let(:params) { { accounts: accounts, quota: quota, visitors: visitors, partners: partners, services: services } }
        it 'updates storm_users column to default value' do
          subject
          expect(contract.storm_users).to eq Contract::DEFAULT_STORM_USER
        end
      end
    end
  end

end
