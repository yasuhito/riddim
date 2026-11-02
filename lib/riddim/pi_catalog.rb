# frozen_string_literal: true

require 'open3'
require 'tmpdir'

module Riddim
  # A bounded, request-free preflight against Pi's own model list. Pi has no
  # exact-selection flag: even with --provider pinned, an ID missing from that
  # provider's catalog is fuzzy-matched to another of its models or sent as a
  # custom ID. Refusing any model `pi --list-models` does not list exactly
  # leaves Pi's lookup only its exact branch, so the allowlisted model is the
  # one that starts.
  module PiCatalog
    TIMEOUT = 30
    HEADER = /\Aprovider +(model) +(context)\b/

    class Error < StandardError; end

    module_function

    def verify!(model, timeout: TIMEOUT)
      model = model.dup.force_encoding(Encoding::UTF_8)
      provider, _, id = model.partition('/')
      matches = listed(list(timeout), provider, id)
      return if matches == [[provider, id]]

      raise Error, refusal(model, provider, matches)
    end

    # Rows Pi could select for --provider <provider> --model <id>: any case
    # variant, and for an ID repeating its provider prefix, Pi's split reading.
    def listed(rows, provider, id)
      stripped = id[(provider.length + 1)..] if id.downcase.start_with?("#{provider.downcase}/")
      rows.select do |row_provider, row_id|
        row_provider.casecmp?(provider) && (row_id.casecmp?(id) || (stripped && row_id.casecmp?(stripped)))
      end
    end

    def refusal(model, provider, matches)
      listed = matches.map { |row| row.join('/').dump }.join(', ')
      if matches.empty?
        "model #{model.dump} is not listed by `pi --list-models`; Pi would substitute or guess " \
          "another #{provider.dump} model, so nothing was started"
      elsif !matches.include?(model.split('/', 2))
        "model #{model.dump} is not listed exactly by `pi --list-models`, which lists #{listed}; " \
          'nothing was started'
      else
        "model #{model.dump} is ambiguous in `pi --list-models` (#{listed}); nothing was started"
      end
    end

    def list(timeout)
      stdout = Dir.mktmpdir('riddim-pi-catalog-') { |directory| run_list_models(directory, timeout) }
      parse(stdout.force_encoding(Encoding::UTF_8))
    end

    # Pi pads every column to its widest cell, so the header fixes the slices.
    def parse(stdout)
      header, *rows = stdout.lines.map(&:chomp)
      columns = header&.match(HEADER)
      raise Error, "unexpected `pi --list-models` output: #{header.to_s.dump}" unless stdout.valid_encoding? && columns

      model_at = columns.begin(1)
      context_at = columns.begin(2)
      rows.map { |row| [row[0...model_at].rstrip, row[model_at...context_at].to_s.rstrip] }
    end

    def run_list_models(directory, timeout)
      stdout, stderr, status = capture_list_models(directory, timeout)
      return stdout if status.success?

      raise Error, "`pi --list-models` failed: #{stderr.lines.last.to_s.strip.dump}"
    rescue SystemCallError => e
      raise Error, "could not run `pi --list-models`: #{e.message}"
    end

    def capture_list_models(directory, timeout)
      Open3.popen3('pi', '--list-models', chdir: directory, pgroup: true) do |input, output, error, waiter|
        input.close
        readers = [output, error].map { |stream| Thread.new { stream.read } }
        stop(waiter, timeout) unless waiter.join(timeout)
        [*readers.map(&:value), waiter.value]
      end
    end

    def stop(waiter, timeout)
      Process.kill('KILL', -waiter.pid)
      waiter.join
      raise Error, "`pi --list-models` did not finish within #{timeout} seconds"
    end

    private_class_method :listed, :refusal, :list, :parse, :run_list_models, :capture_list_models, :stop
  end
end
