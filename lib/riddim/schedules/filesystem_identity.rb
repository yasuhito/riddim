# frozen_string_literal: true

require 'fiddle/import'

module Riddim
  module Schedules
    # Linux statfs ABI. Unlike mount-time st_dev, btrfs f_fsid incorporates the
    # filesystem UUID and subvolume root ID. Descriptors avoid path races.
    module FilesystemIdentity
      extend Fiddle::Importer

      dlload Fiddle.dlopen(nil)
      extern 'int fstatfs(int, void*)'
      Statfs = struct ['long type', 'long bsize', 'unsigned long blocks', 'unsigned long bfree',
                       'unsigned long bavail', 'unsigned long files', 'unsigned long ffree',
                       'int fsid[2]', 'long namelen', 'long frsize', 'long flags', 'long spare[4]']

      module_function

      def filesystem(file)
        raise Error, 'stable identities require x86_64/aarch64 Linux statfs' unless
          RUBY_PLATFORM.match?(/\A(?:x86_64|aarch64)-linux/) && Fiddle::SIZEOF_LONG == 8

        stat = Statfs.malloc(Fiddle::RUBY_FREE)
        raise SystemCallError.new('fstatfs', Fiddle.last_error) unless fstatfs(file.fileno, stat).zero?

        stat.fsid.map { |word| format('%08x', word & 0xffffffff) }.join
      end

      def identity(file)
        "fsid:#{filesystem(file)}:#{file.stat.ino}"
      end
    end
  end
end
