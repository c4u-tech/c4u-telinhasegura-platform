require "minitest/autorun"
require_relative "../lib/store_release"

class StoreReleaseTest < Minitest::Test
  def test_next_build_number_is_one_past_the_highest_on_either_store
    assert_equal 8, StoreRelease.next_build_number([3, 7], 5)
    assert_equal 10, StoreRelease.next_build_number([3], 9)
  end

  def test_next_build_number_starts_at_one_when_nothing_was_uploaded
    assert_equal 1, StoreRelease.next_build_number([], nil)
    assert_equal 1, StoreRelease.next_build_number(nil, 0)
  end

  def test_next_build_number_refuses_to_pass_the_play_ceiling
    assert_equal 2_100_000_000, StoreRelease.next_build_number([2_099_999_999], nil)
    assert_raises(ArgumentError) { StoreRelease.next_build_number([2_100_000_000], nil) }
  end

  def test_already_uploaded
    assert StoreRelease.already_uploaded?([4, 5], 5)
    refute StoreRelease.already_uploaded?([4], 5)
    refute StoreRelease.already_uploaded?(nil, 5)
  end

  def test_version_name_reads_the_pubspec
    assert_equal "0.2.0", StoreRelease.version_name("name: app\nversion: 0.2.0+3\n")
    assert_equal "1.10.4", StoreRelease.version_name("version: 1.10.4\n")
  end

  def test_version_name_refuses_a_pubspec_without_a_version
    assert_raises(ArgumentError) { StoreRelease.version_name("name: app\n") }
  end

  def test_rollout_change
    assert_equal({ rollout: "0.5" }, StoreRelease.rollout_change("50"))
    # A fraction of 1 is what makes supply complete the release.
    assert_equal({ rollout: "1" }, StoreRelease.rollout_change("100"))
    assert_equal({ release_status: "halted", rollout: "0.2" }, StoreRelease.rollout_change("halt", 0.2))
    assert_equal({ release_status: "halted", rollout: "0.5" }, StoreRelease.rollout_change("halt", "0.5"))
    assert_raises(ArgumentError) { StoreRelease.rollout_change("75") }
  end

  def test_rollout_change_needs_the_current_fraction_to_halt
    assert_raises(ArgumentError) { StoreRelease.rollout_change("halt") }
    assert_raises(ArgumentError) { StoreRelease.rollout_change("halt", "") }
  end

  def test_rollout_change_cannot_be_altered_by_a_caller
    change = StoreRelease.rollout_change("50")
    begin
      change[:rollout] << "9"
      change[:release_status] = "halted"
    rescue RuntimeError
      nil
    end
    assert_equal({ rollout: "0.5" }, StoreRelease.rollout_change("50"))
  end

  Release = Struct.new(:status, :user_fraction, :version_codes)

  def test_in_progress_release_finds_the_staged_rollout
    releases = [
      Release.new("completed", nil, ["40"]),
      Release.new("inProgress", 0.2, ["41", "42"]),
    ]
    assert_equal({ version_code: 42, fraction: 0.2 }, StoreRelease.in_progress_release(releases))
  end

  def test_in_progress_release_is_nil_without_a_staged_rollout
    assert_nil StoreRelease.in_progress_release([Release.new("completed", nil, ["40"])])
    assert_nil StoreRelease.in_progress_release([Release.new("halted", 0.2, ["41"])])
    assert_nil StoreRelease.in_progress_release([])
    assert_nil StoreRelease.in_progress_release(nil)
  end

  def test_release_status
    assert_equal "completed", StoreRelease.release_status(nil)
    assert_equal "completed", StoreRelease.release_status("")
    assert_equal "completed", StoreRelease.release_status("completed")
    assert_equal "draft", StoreRelease.release_status("draft")
    assert_raises(ArgumentError) { StoreRelease.release_status("inProgress") }
  end
end
