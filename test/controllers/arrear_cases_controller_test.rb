require "test_helper"

class ArrearCasesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get arrear_cases_index_url
    assert_response :success
  end

  test "should get show" do
    get arrear_cases_show_url
    assert_response :success
  end

  test "should get new" do
    get arrear_cases_new_url
    assert_response :success
  end

  test "should get edit" do
    get arrear_cases_edit_url
    assert_response :success
  end
end
