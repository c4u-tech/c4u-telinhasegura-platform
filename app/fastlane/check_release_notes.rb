# Checks the store release notes before a release, with no store access:
#
#   ruby app/fastlane/check_release_notes.rb             every locale has a note within the store's limit
#   ruby app/fastlane/check_release_notes.rb app-v1.2.3  ... and each one changed since that release
#
# Run from the repository root.
require "open3"
require_relative "lib/store_release"

METADATA = "app/fastlane/metadata".freeze

since = ARGV[0]
changed = nil
if since
  out, status = Open3.capture2("git", "diff", "--name-only", since, "HEAD", "--", METADATA)
  abort "check_release_notes: git diff against #{since} failed" unless status.success?
  changed = out.lines.map { |l| l.strip.delete_prefix("#{METADATA}/") }
end

problems = StoreRelease.release_notes_problems(METADATA, changed: changed)
if problems.empty?
  puts "Release notes ready#{" (changed since #{since})" if since}."
  exit 0
end
warn "Release notes are not ready:"
problems.each { |p| warn "  #{METADATA}/#{p}" }
warn "Write what's new in this version for each store locale."
exit 1
