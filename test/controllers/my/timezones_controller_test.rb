require "test_helper"

class My::TimezonesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:david)

    sign_in_as @user
  end

  test "update" do
    assert_changes -> { @user.reload.settings.timezone_name }, to: "Europe/London" do
      put my_timezone_path, params: { timezone_name: "Europe/London" }
    end

    assert_response :no_content
  end

  test "update creates missing settings" do
    @user.settings.destroy!

    assert_difference -> { User::Settings.count }, 1 do
      put my_timezone_path, params: { timezone_name: "Europe/London" }
    end

    assert_response :no_content
    assert_equal "Europe/London", @user.reload.settings.timezone_name
  end
end
