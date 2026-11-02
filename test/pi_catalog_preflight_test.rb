# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'json'
require 'open3'
require 'socket'
require 'tmpdir'
require_relative '../scripts/pi_stall_server'

# The real Riddim CLI's `pi --list-models` preflight against the real Pi and
# an isolated loopback catalog. Herdr is a recording fake; any model request
# reaching the loopback provider would be recorded too.
class PiCatalogPreflightTest < Minitest::Test
  RIDDIM = File.expand_path('../bin/riddim', __dir__)
  PANE = { pane_id: 'w9:p1', workspace_id: 'w9', tab_id: 'w9:t1', cwd: '/' }.freeze
  CREATED = { id: 'x', result: { type: 'workspace_created', workspace: { workspace_id: 'w9', label: 'w' },
                                 tab: { tab_id: 'w9:t1', workspace_id: 'w9', label: '1' }, root_pane: PANE } }.freeze

  def setup
    skip 'Pi executable unavailable on PATH' unless pi_installed?
    @root = Dir.mktmpdir('riddim-catalog-preflight-')
    @server = TCPServer.new('127.0.0.1', 0)
    @contacts = Queue.new
    @responder = Thread.new { loop { answer } }
    configure_riddim
    install_fake_herdr
  end

  def pi_installed?
    ENV.fetch('PATH').split(File::PATH_SEPARATOR).any? do |dir|
      File.file?(File.join(dir, 'pi')) && File.executable?(File.join(dir, 'pi'))
    end
  end

  def configure_riddim
    %w[config state bin].each { |name| Dir.mkdir(File.join(@root, name)) }
    File.write(File.join(@root, 'config/agent-profile'), "pi lab-bridge/opus low\n")
    File.write(File.join(@root, 'config/allowed-models'), "lab-bridge/opus\n")
  end

  def teardown
    @responder&.kill
    @server&.close
    FileUtils.remove_entry(@root) if @root
  end

  def answer
    socket = PiStallLab::LabServer.receive_request(@server)
    @contacts << :request
    PiStallLab::LabServer.send_ok(socket)
  rescue Errno::EPIPE, Errno::ECONNRESET
    nil
  ensure
    socket&.close
  end

  def install_fake_herdr
    File.write(File.join(@root, 'bin/herdr'), <<~RUBY, perm: 0o755)
      #!#{RbConfig.ruby}
      File.open(#{File.join(@root, 'herdr.log').dump}, 'a') { |file| file.puts(ARGV.join(' ')) }
      ARGV.shift(2)
      case ARGV[0, 2]
      when %w[status --json] then puts '{"client":{"protocol":22,"version":"0.9.0"},"server":{"running":false}}'
      when %w[workspace create] then puts #{JSON.generate(CREATED).dump}
      when %w[agent start] then nil
      else abort "unexpected \#{ARGV.inspect}"
      end
    RUBY
  end

  # Only "opus-pro" exists unless the exact ID is listed too.
  def catalog(*)
    model = ->(id) { { id: id, contextWindow: 128_000, maxTokens: 64 } }
    provider = { baseUrl: "http://127.0.0.1:#{@server.addr[1]}/v1", api: 'openai-completions', apiKey: 'dummy',
                 models: [*].map(&model) }
    File.write(File.join(@root, 'models.json'), JSON.generate(providers: { 'lab-bridge' => provider }))
  end

  def riddim(*)
    environment = { 'PI_CODING_AGENT_DIR' => @root, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
                    'PATH' => "#{File.join(@root, 'bin')}:#{ENV.fetch('PATH')}", 'HERDR_SESSION' => 'lab',
                    'RIDDIM_CONFIG_DIR' => File.join(@root, 'config'), 'RIDDIM_STATE_DIR' => File.join(@root, 'state'),
                    'RIDDIM_ACTOR' => nil, 'RIDDIM_SUPERVISE' => nil }
    _, stderr, status = Bundler.with_unbundled_env do
      Open3.capture3(environment, RIDDIM, *, chdir: @root)
    end
    log = File.join(@root, 'herdr.log')
    [status.exitstatus, stderr, File.file?(log) ? File.readlines(log, chomp: true) : [], @contacts.size]
  end

  def test_start_refuses_an_unlisted_exact_id_whose_fuzzy_candidate_costs_more
    catalog('opus-pro')
    status, stderr, herdr, requests = riddim('start', 'worker', '--model', 'lab-bridge/opus')

    assert_equal [1, true, [], 0],
                 [status, stderr.include?('"lab-bridge/opus" is not listed by `pi --list-models`'), herdr, requests]
  end

  def test_supervise_refuses_an_unlisted_profile_model_before_herdr
    catalog('opus-pro')
    status, stderr, herdr, requests = riddim('supervise')

    assert_equal [1, true, [], 0], [status, stderr.include?('is not listed by `pi --list-models`'), herdr, requests]
  end

  def test_start_passes_a_listed_exact_id_pinned_to_its_provider
    catalog('opus', 'opus-pro')
    status, stderr, herdr, requests = riddim('start', 'worker')

    assert_equal [0, 'pi --pane w9:p1 -- --provider lab-bridge --model opus --thinking low', 0],
                 [status, herdr.last&.split(' --kind ')&.last, requests], stderr
  end
end
