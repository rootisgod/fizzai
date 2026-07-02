require "test_helper"

class User::ConfigurableTest < ActiveSupport::TestCase
  test "should create settings for new users" do
    user = User.create! account: accounts("37s"), name: "Some new user"
    assert user.settings.present?
  end

  test "should create settings for persisted users missing settings" do
    user = users(:david)
    user.settings.destroy!

    assert_difference -> { User::Settings.count }, 1 do
      assert user.reload.settings.present?
    end
  end
end
