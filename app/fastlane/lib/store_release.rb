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

  # The track and version code Play needs to find a release before it takes
  # listing texts: production once it has a release, else internal.
  def listing_anchor(production_codes, internal_codes)
    prod = Array(production_codes)
    return ["production", prod.max] unless prod.empty?
    internal = Array(internal_codes)
    return ["internal", internal.max] unless internal.empty?
    raise ArgumentError, "no release on production or internal to attach the listing texts to"
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

  # How a build goes to Play production. Until an app's first release is
  # out, Play's API only creates draft releases, so the first one is left as
  # a draft to be sent for review from Play Console; once production has had
  # a release, each one starts as a 20% staged rollout.
  def promotion(production_releases)
    published = Array(production_releases).any? { |r| %w[completed inProgress halted].include?(r.status) }
    published ? { rollout: "0.2" } : { release_status: "draft", track_promote_release_status: "draft" }
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

  # The longest "what's new" text each store takes.
  IOS_RELEASE_NOTES_LIMIT = 4000
  PLAY_RELEASE_NOTES_LIMIT = 500

  def locale_dirs(dir)
    return [] unless File.directory?(dir)
    Dir.children(dir).select { |f| File.directory?(File.join(dir, f)) && !f.start_with?(".") }.sort
  end

  # The release notes each store locale needs, as paths relative to the
  # metadata folder with the store's length limit: release_notes.txt for App
  # Store Connect, changelogs/default.txt for Play.
  def release_notes_files(metadata_dir)
    android = locale_dirs(File.join(metadata_dir, "android")).map do |l|
      ["android/#{l}/changelogs/default.txt", PLAY_RELEASE_NOTES_LIMIT]
    end
    ios = locale_dirs(File.join(metadata_dir, "ios")).map { |l| ["ios/#{l}/release_notes.txt", IOS_RELEASE_NOTES_LIMIT] }
    android + ios
  end

  # What stops these release notes from going to the stores: a missing or
  # empty note, one over the store's limit, or, when the paths changed since
  # the last release are given, one still carrying that release's text.
  def release_notes_problems(metadata_dir, changed: nil)
    release_notes_files(metadata_dir).filter_map do |path, limit|
      full = File.join(metadata_dir, path)
      next "#{path} is missing" unless File.file?(full)
      text = File.read(full, encoding: "UTF-8").strip
      next "#{path} is empty" if text.empty?
      next "#{path} has #{text.length} characters; the store takes at most #{limit}" if text.length > limit
      next "#{path} is unchanged since the last release" if changed && !changed.include?(path)
    end
  end

  # The App Store release notes by locale, read from metadata/ios.
  def ios_release_notes(ios_metadata_dir)
    locale_dirs(ios_metadata_dir).to_h do |l|
      path = File.join(ios_metadata_dir, l, "release_notes.txt")
      [l, File.file?(path) ? File.read(path, encoding: "UTF-8").strip : ""]
    end
  end

  # App Store Connect refuses to review an update whose locales lack "what's
  # new", and the submit lane leaves the rest of the metadata alone, so only
  # this field is written. Every locale is checked before any is written.
  def write_whats_new(version, notes_by_locale)
    localizations = version.get_app_store_version_localizations
    missing = localizations.map(&:locale).select { |l| notes_by_locale[l].to_s.strip.empty? }
    raise ArgumentError, "no release notes for #{missing.join(', ')}" unless missing.empty?
    localizations.each { |loc| loc.update(attributes: { whatsNew: notes_by_locale.fetch(loc.locale) }) }
  end

  # match exports the App Store profile it installed for each bundle id as
  # sigh_<id>_appstore_profile-name; every id in the app needs one, so a
  # missing profile stops the lane before the build.
  def appstore_profiles(bundle_ids, env)
    bundle_ids.to_h { |id| [id, env.fetch("sigh_#{id}_appstore_profile-name")] }
  end
end
