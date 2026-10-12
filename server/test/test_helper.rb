ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/evidence_reporter"

module ActiveSupport
  class TestCase
    fixtures :all
  end
end
