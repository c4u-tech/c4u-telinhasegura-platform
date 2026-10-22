# Helpers for the store lanes, kept apart from fastlane so they can be
# tested without network access or store credentials; store objects are
# passed in.
module StoreRelease
  module_function

  # Google Play refuses version codes above this value.
  PLAY_MAX_VERSION_CODE = 2_100_000_000

  # Both stores must receive the same build number, and neither accepts one
  # it has seen, so the next number is one past the highest on either store.
  def next_build_number(play_codes, testflight_latest)
    highest = [*Array(play_codes), testflight_latest.to_i].max || 0
    n = highest + 1
    raise ArgumentError, "build number #{n} exceeds Google Play's limit" if n > PLAY_MAX_VERSION_CODE
    n
  end

  def already_uploaded?(codes, n)
    Array(codes).include?(n)
  end

  def version_name(pubspec_text)
    match = pubspec_text.match(/^version:\s*(\d+\.\d+\.\d+)/)
    raise ArgumentError, "pubspec.yaml has no version" unless match
    match[1]
  end

  # Without a new binary, supply only touches a track when it is given a
  # rollout fraction: 1 completes the release, and halting must restate
  # the fraction the release is at. Each call builds a fresh hash so a
  # caller cannot change what the next call returns.
  def rollout_change(step, current_fraction = nil)
    case step
    when "50" then { rollout: "0.5" }
    when "100" then { rollout: "1" }
    when "halt"
      raise ArgumentError, "halting needs the current rollout fraction" if current_fraction.to_s.empty?
      { release_status: "halted", rollout: current_fraction.to_s }
    else
      raise ArgumentError, "unknown rollout step #{step.inspect}"
    end
  end

  # The staged rollout a step can move: the in-progress release, its
  # highest version code (Play returns them as strings) and its fraction.
  def in_progress_release(releases)
    release = Array(releases).find { |r| r.status == "inProgress" }
    return nil unless release
    { version_code: release.version_codes.map(&:to_i).max, fraction: release.user_fraction }
  end

  # An app never published on Play only accepts draft releases, so the
  # status of the internal release can be overridden until it is.
  def release_status(value)
    status = value.to_s.empty? ? "completed" : value
    raise ArgumentError, "unknown Play release status #{value.inspect}" unless %w[completed draft].include?(status)
    status
  end

  # deliver sets the release type and the phased release only while it
  # uploads metadata, which the submit lane skips, so the version is
  # prepared here first: once approved it waits for a maintainer to
  # release it, then reaches users over the phased release. The app is a
  # Spaceship::ConnectAPI::App; ensure_version! creates the version when
  # App Store Connect does not have it yet.
  def hold_and_phase(app, version_string, platform: "IOS")
    app.ensure_version!(version_string, platform: platform)
    version = app.get_edit_app_store_version(platform: platform)
    unless version && version.version_string == version_string
      raise ArgumentError, "App Store Connect has no editable version #{version_string}"
    end
    version.update(attributes: { releaseType: "MANUAL" })
    phased = begin
      version.fetch_app_store_version_phased_release
    rescue StandardError
      # App Store Connect answers with an error when there is none.
      nil
    end
    version.create_app_store_version_phased_release(attributes: { phasedReleaseState: "INACTIVE" }) unless phased
    version
  end
end
