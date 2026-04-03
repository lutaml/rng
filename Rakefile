# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# Extract external test fixtures from Jing-Trang spectest.xml
namespace :fixtures do
  desc "Extract external test resources from Jing-Trang's spectest.xml"
  task :extract_spectest do
    system('ruby scripts/extract_spectest_resources.rb')
  end
end
