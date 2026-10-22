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

  ROLLOUT_STEPS = {
    "50" => { rollout: "0.5" },
    "100" => { release_status: "completed" },
    "halt" => { release_status: "halted" },
  }.freeze

  def rollout_change(step)
    ROLLOUT_STEPS.fetch(step) { raise ArgumentError, "unknown rollout step #{step.inspect}" }
  end

  # An app never published on Play only accepts draft releases, so the
  # status of the internal release can be overridden until it is.
  def release_status(value)
    status = value.to_s.empty? ? "completed" : value
    raise ArgumentError, "unknown Play release status #{value.inspect}" unless %w[completed draft].include?(status)
    status
  end
end
