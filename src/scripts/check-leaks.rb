#!/usr/bin/env ruby
# frozen_string_literal: true

# Fails when the public automation backup holds personal ids, paths, tokens or a term from the
# private repo's denylist. Run by the pre-commit hook, `task check:leaks` and `task test:unit`.
# Uses only the standard library so the hook works without bundler.

require_relative "../install/utils"
require_relative "../install/errors"
require_relative "../install/leak_check"
require_relative "../install/private_repo"

root = File.expand_path("../..", __dir__)
denylist_path = File.join(Installer::PrivateRepo.dir, Installer::LeakCheck::DENYLIST_FILE)
Installer::Utils.warn("No #{denylist_path}: checking generic patterns only") unless File.file?(denylist_path)

findings = Installer::LeakCheck.check_paths(
  Installer::LeakCheck::PUBLIC_PATHS, root: root, denylist: Installer::LeakCheck.denylist(denylist_path)
)
if findings.empty?
  Installer::Utils.success("No leaks in #{Installer::LeakCheck::PUBLIC_PATHS.join(", ")}")
  exit 0
end

Installer::Utils.error("These lines must not be public; move the automation to the private repo or remove the detail:")
puts Installer::LeakCheck.describe(findings)
exit 1
