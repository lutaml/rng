# frozen_string_literal: true

require_relative "lib/rng/version"

all_files_in_git = Dir.chdir(File.expand_path(__dir__)) do
  `git ls-files -z`.split("\x0")
end

Gem::Specification.new do |spec|
  spec.name = "rng"
  spec.version = Rng::VERSION
  spec.authors = ["Ribose"]
  spec.email = ["open.source@ribose.com"]

  spec.summary = "Library to parse and build RELAX NG (RNG) and RELAX NG Compact Syntax (RNC) schemas."
  spec.homepage = "https://github.com/lutaml/rng"
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  # Specify which files should be added to the gem when it is released.
  spec.files = all_files_in_git
               .reject { |f| f.match(%r{\A(?:test|features|bin|\.)/}) }

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "lutaml-model"
  spec.add_dependency "nokogiri"
  spec.add_dependency "parslet"
  spec.add_dependency "zeitwerk"

  # spec.add_dependency "thor"
  spec.metadata["rubygems_mfa_required"] = "true"
end
