# frozen_string_literal: true

require "rng"
require "xml/c14n"
require "equivalent-xml"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Add helper method for XML comparison
  config.include(Module.new do
    def normalize_xml(xml)
      Xml::C14n.format(xml)
    end
  end)
end
