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

  def test_promotion_leaves_a_draft_on_an_app_never_published
    # Until the app's first release is out, Play's API only creates drafts.
    draft = { release_status: "draft", track_promote_release_status: "draft" }
    assert_equal draft, StoreRelease.promotion([])
    assert_equal draft, StoreRelease.promotion(nil)
    assert_equal draft, StoreRelease.promotion([Release.new("draft", nil, ["40"])])
  end

  def test_promotion_stages_once_the_app_has_been_published
    %w[completed inProgress halted].each do |status|
      assert_equal({ rollout: "0.2" }, StoreRelease.promotion([Release.new(status, nil, ["40"])]), status)
    end
  end

  def test_release_status
    assert_equal "completed", StoreRelease.release_status(nil)
    assert_equal "completed", StoreRelease.release_status("")
    assert_equal "completed", StoreRelease.release_status("completed")
    assert_equal "draft", StoreRelease.release_status("draft")
    assert_raises(ArgumentError) { StoreRelease.release_status("inProgress") }
  end

  class FakeVersion
    attr_reader :version_string, :calls

    def initialize(version_string, phased)
      @version_string = version_string
      @phased = phased
      @calls = []
    end

    def update(attributes:)
      @calls << [:update, attributes]
    end

    def fetch_app_store_version_phased_release
      raise "no data" unless @phased
      @phased
    end

    def create_app_store_version_phased_release(attributes:)
      @calls << [:create_phased_release, attributes]
    end
  end

  class FakeApp
    attr_reader :calls

    def initialize(version)
      @version = version
      @calls = []
    end

    def ensure_version!(version_string, platform:)
      @calls << [:ensure_version!, version_string, platform]
    end

    def get_edit_app_store_version(platform:)
      @calls << [:get_edit_app_store_version, platform]
      @version
    end
  end

  def test_hold_and_phase_prepares_the_version_before_submission
    version = FakeVersion.new("1.2.0", nil)
    app = FakeApp.new(version)
    StoreRelease.hold_and_phase(app, "1.2.0")
    assert_equal [[:ensure_version!, "1.2.0", "IOS"], [:get_edit_app_store_version, "IOS"]], app.calls
    assert_equal [
      [:update, { releaseType: "MANUAL" }],
      [:create_phased_release, { phasedReleaseState: "INACTIVE" }],
    ], version.calls
  end

  def test_hold_and_phase_keeps_an_existing_phased_release
    version = FakeVersion.new("1.2.0", Object.new)
    StoreRelease.hold_and_phase(FakeApp.new(version), "1.2.0")
    assert_equal [[:update, { releaseType: "MANUAL" }]], version.calls
  end

  def test_listing_anchor_prefers_production
    assert_equal ["production", 5], StoreRelease.listing_anchor([3, 5], [9])
  end

  def test_listing_anchor_falls_back_to_internal_before_the_first_production_release
    assert_equal ["internal", 2], StoreRelease.listing_anchor([], [1, 2])
    assert_equal ["internal", 2], StoreRelease.listing_anchor(nil, [2])
  end

  def test_listing_anchor_refuses_when_no_track_has_a_release
    assert_raises(ArgumentError) { StoreRelease.listing_anchor([], []) }
    assert_raises(ArgumentError) { StoreRelease.listing_anchor(nil, nil) }
  end

  def test_hold_and_phase_refuses_another_version
    assert_raises(ArgumentError) { StoreRelease.hold_and_phase(FakeApp.new(FakeVersion.new("1.1.0", nil)), "1.2.0") }
    assert_raises(ArgumentError) { StoreRelease.hold_and_phase(FakeApp.new(nil), "1.2.0") }
  end
end
