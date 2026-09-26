# frozen_string_literal: true

require_relative '../../lib/riddim/notifications'

module WatchScanReplacement
  def scan
    unless @replaced
      @replaced = true
      selected = ENV.fetch('RIDDIM_REPLACED_HOME')
      File.rename(selected, "#{selected}-old")
      File.rename(ENV.fetch('RIDDIM_REPLACEMENT_HOME'), selected)
    end
    super
  end
end

Riddim::Notifications.singleton_class.prepend(WatchScanReplacement)
