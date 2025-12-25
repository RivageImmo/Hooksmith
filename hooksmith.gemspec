# frozen_string_literal: true

require_relative 'lib/hooksmith/version'

Gem::Specification.new do |spec|
  spec.name = 'hooksmith'
  spec.version = Hooksmith::VERSION
  spec.authors = ['gregoryrivage']
  spec.email = ['gregory@rivage.immo']

  spec.summary = 'Hooksmith is a gem that allows you to handle webhooks in your Rails application.'
  spec.description = <<~DESC.gsub("\n", ' ').strip
    Hooksmith is a gem that allows you to handle webhooks in your Rails application.
    It provides a simple and flexible way to receive, validate, and process webhooks from various services.
    With Hooksmith, you can easily configure webhook endpoints, handle authentication, retry failed webhooks,
    and manage webhook payloads in a consistent manner.
  DESC
  spec.homepage = 'https://github.com/gregoryrivage/hooksmith'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/gregoryrivage/hooksmith'
  spec.metadata['changelog_uri'] = 'https://github.com/gregoryrivage/hooksmith/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'base64', '>= 0.1.0' # Required for HMAC signature encoding

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
