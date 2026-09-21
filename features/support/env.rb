# frozen_string_literal: true

require 'bundler'
require 'fileutils'
require 'minitest'
require 'minitest/assertions'
require 'open3'
require 'shellwords'
require 'tmpdir'

# Shared filesystem, process, and assertion support for CLI scenarios.
module RiddimWorld
  RIDDIM = File.expand_path('../../bin/riddim', __dir__)

  include Minitest::Assertions

  def assertions
    @assertions ||= 0
  end
end

World(RiddimWorld)

Before do
  @temporary_directories = []
end

After do
  @temporary_directories.each { |directory| FileUtils.remove_entry(directory) }
end
