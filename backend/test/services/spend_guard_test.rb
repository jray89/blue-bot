require "test_helper"

class SpendGuardTest < ActiveSupport::TestCase
  test "allows questions up to the daily limit, then raises" do
    with_env("DAILY_QUESTION_LIMIT" => "2") do
      SpendGuard.reset!

      2.times { SpendGuard.consume! }
      assert_raises(SpendGuard::LimitExceeded) { SpendGuard.consume! }
      assert_equal 0, SpendGuard.status[:remaining]
    end
  end

  test "a refund hands a reservation back but never goes negative" do
    with_env("DAILY_QUESTION_LIMIT" => "1") do
      SpendGuard.reset!

      SpendGuard.consume!
      SpendGuard.refund!
      SpendGuard.refund!

      assert_equal 0, SpendGuard.status[:asked_today]
      SpendGuard.consume!
    end
  end

  test "the counter resets on a new UTC day" do
    with_env("DAILY_QUESTION_LIMIT" => "1") do
      SpendGuard.reset!
      SpendGuard.consume!

      travel_to 1.day.from_now do
        assert_equal 1, SpendGuard.status[:remaining]
        SpendGuard.consume!
      end
    end
  end

  test "status reports estimated spend" do
    SpendGuard.consume!

    assert_equal SpendGuard::ESTIMATED_COST_PER_QUESTION, SpendGuard.status[:estimated_spend_today]
  end
end
