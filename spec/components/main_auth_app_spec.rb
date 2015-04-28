require 'spec_helper'

RSpec.describe Marty::MainAuthApp do
  describe '#menu' do
    before(:each) do
      allow(Marty::MainAuthApp).to receive(:has_any_perm?).
        and_return(true)
      allow(Marty::MainAuthApp).to receive(:has_admin_perm?).
        and_return(false)
      allow(Marty::MainAuthApp).to receive(:has_user_manager_perm?).
        and_return(false)
    end

    let(:all) {[
        subject.ident_menu,
        subject.system_menu,
        subject.applications_menu,
        subject.posting_menu,
    ]}

    let(:all_but_system) {[
        subject.ident_menu,
        subject.applications_menu,
        subject.posting_menu,
    ]}

    it 'has all the menus for admin user' do
      allow(Marty::MainAuthApp).to receive(:has_admin_perm?).and_return(true)
      expect(subject.menu).to include(*all)
      expect(sep_count(subject.menu)).to eq(4)
      expect(subject.menu).to end_with_super
    end

    it 'has all the menus for a user manager' do
      allow(Marty::MainAuthApp).to receive(:has_user_manager_perm?).
        and_return(true)
      expect(subject.menu).to include(*all)
      expect(sep_count(subject.menu)).to eq(4)
      expect(subject.menu).to end_with_super
    end

    it "doesn't have a system menu if not admin and not user manager" do
      expect(subject.menu).to include(*all_but_system)
      expect(subject.menu).not_to include(subject.system_menu)
      expect(sep_count(subject.menu)).to eq(3)
      expect(subject.menu).to end_with_super
    end

    it 'only has super menu if no perm' do
      allow(Marty::MainAuthApp).to receive(:has_any_perm?).
        and_return(false)
      expect(subject.menu).not_to include(*all_but_system)
      expect(subject.menu).to end_with_super
    end

    def sep_count(menu)
      menu.select { |item| item == subject.sep }.count
    end

    RSpec::Matchers.define :end_with_super do
      match do |actual|
        the_super = Marty::AuthApp.new.menu
        actual.last(the_super.count) == the_super
      end
    end
  end
end
