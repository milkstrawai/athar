# frozen_string_literal: true

require_relative "lib/athar/version"

Gem::Specification.new do |spec|
  spec.name = "athar"
  spec.version = Athar::VERSION
  spec.authors = ["Ali Hamdi Ali Fadel"]
  spec.email = ["aliosm1997@gmail.com"]

  spec.summary = "Database-level deletion auditing for Rails applications using PostgreSQL triggers."
  spec.description = "Athar records database deletions to a separate audit table using PostgreSQL " \
                     "triggers, instead of soft-deleting rows in their original tables."
  spec.homepage = "https://github.com/milkstrawai/athar"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.glob("{lib,exe}/**/*", File::FNM_DOTMATCH).reject { |f| File.directory?(f) } +
               %w[CHANGELOG.md DESIGN.md LICENSE.txt README.md]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activejob", ">= 7.2"
  spec.add_dependency "activerecord", ">= 7.2"
  spec.add_dependency "activesupport", ">= 7.2"
  spec.add_dependency "fx", "~> 0.10"
  spec.add_dependency "railties", ">= 7.2"
end
