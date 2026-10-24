# frozen_string_literal: true

require 'json'
require_relative '../lib/riddim/supervise'

# Session-start prerequisite, not a launcher. Pi owns the existing watcher.
begin
  puts JSON.generate(Riddim::Supervise.native_environment(ARGV.fetch(0)))
rescue Riddim::Supervise::Error, Riddim::RuntimePaths::Error, SystemCallError => e
  warn e.message
  exit 1
end
