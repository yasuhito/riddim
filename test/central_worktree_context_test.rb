# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../scripts/pi_stall_server'

# Real Git allocation and Pi context discovery, with only a loopback model.
# rubocop:disable-next Metrics/ClassLength
class CentralWorktreeContextTest < Minitest::Test
  SOURCE = File.expand_path('..', __dir__)
  GLOBAL = 'GLOBAL_CONTEXT_PROBE: Keep legitimate personal instructions.'
  PARENT = 'PARENT_CONTEXT_PROBE: Keep legitimate shared ancestor instructions.'
  TARGET = 'TARGET_CONTEXT_PROBE: Edit only the assigned target project.'
  RUNTIME = 'RIDDIM_CONTEXT_PROBE: Coordinate workers; do not edit target projects.'

  # rubocop:disable-next Metrics/MethodLength, Metrics/AbcSize
  def setup
    skip 'Pi executable unavailable on PATH' unless ENV.fetch('PATH').split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, 'pi')) && File.file?(File.join(dir, 'pi'))
    end

    @root = Dir.mktmpdir('riddim-context-')
    @runtime = File.join(@root, 'riddim')
    @target = File.join(@root, 'target')
    @home = File.join(@root, 'home')
    prepare_instructions
    @worker = allocate_worker
    @server = TCPServer.new('127.0.0.1', 0)
    PiStallLab::LabServer.config(@home, @server.addr[1])
  end

  def prepare_instructions
    FileUtils.mkdir_p(@home)
    File.write(File.join(@home, 'AGENTS.md'), GLOBAL)
    File.write(File.join(@root, 'AGENTS.md'), PARENT)
    prepare_repository(@runtime, RUNTIME)
    prepare_repository(@target, TARGET)
    FileUtils.cp_r(File.join(SOURCE, 'lib'), @runtime)
  end

  def teardown
    @server&.close
    FileUtils.remove_entry(@root) if @root
  end

  def run!(*)
    output, error, status = Open3.capture3(*)
    raise "fixture command failed: #{error}" unless status.success?

    output.strip
  end

  def prepare_repository(path, instructions)
    Dir.mkdir(path)
    run!('git', '-C', path, 'init', '--quiet', '--initial-branch=main')
    File.write(File.join(path, 'AGENTS.md'), instructions)
    run!('git', '-C', path, 'add', 'AGENTS.md')
    run!('git', '-C', path, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
         'commit', '--quiet', '-m', 'fixture instructions')
  end

  def allocate_worker
    library = File.join(@runtime, 'lib/riddim/worktree')
    code = <<~RUBY
      created = Riddim::Worktree.create('worker', cwd: ARGV[0], config_dir: ARGV[1], state_dir: ARGV[2])
      puts created.path
    RUBY
    run!('ruby', '-r', library, '-e', code, @target, File.join(@root, 'config'), File.join(@root, 'state'))
  end

  def pi_environment
    { 'PI_CODING_AGENT_DIR' => @home, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
      'RIDDIM_ACTOR' => 'branch', 'RIDDIM_SUPERVISE' => nil, 'RIDDIM_STATE_DIR' => File.join(@root, 'state') }
  end

  # rubocop:disable-next Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
  def request_context
    args = %w[--print --no-tools --no-session --model stall-lab/test --thinking off]
    Bundler.with_unbundled_env do
      Open3.popen3(pi_environment, 'pi', *args, 'Describe instructions.', chdir: @worker) do |input, out, err, wait|
        input.close
        diagnostics = +''
        readers = [Thread.new { out.read }, Thread.new { err.each_line { |line| diagnostics << line } }]
        requester = Thread.new { read_context_request }
        requester.report_on_exception = false
        Timeout.timeout(20) do
          status = wait.value
          readers.each(&:value)
          raise "Pi startup failed: #{diagnostics}" unless status.success?

          requester.value
        end
      rescue Timeout::Error
        raise "Pi context timed out: #{diagnostics}"
      ensure
        stop_context_process(wait)
        requester&.kill
        requester&.join(5)
        readers&.each { |reader| raise 'Pi pipe reader did not stop' unless reader.join(5) }
      end
    end
  end

  def read_context_request
    socket = PiStallLab::LabServer.accept_http_request(@server)
    request = JSON.parse(PiStallLab::LabServer.read_body(socket))
    PiStallLab::LabServer.send_ok(socket)
    request.fetch('messages').select { |message| message['role'] == 'system' }.to_json
  ensure
    socket&.close
  end

  def stop_context_process(wait)
    return if wait.join(0)

    Process.kill('TERM', wait.pid)
    return if wait.join(5)

    Process.kill('KILL', wait.pid)
    raise "Test-owned Pi #{wait.pid} did not stop after KILL" unless wait.join(5)
  rescue Errno::ESRCH
    raise "Test-owned Pi #{wait.pid} was not reaped" unless wait.join(5)
  end

  def test_real_pi_keeps_target_and_global_context_without_riddim_context
    context = request_context
    paths = [File.join(@home, 'AGENTS.md'), File.join(@root, 'AGENTS.md'), File.join(@worker, 'AGENTS.md')]

    assert_equal [true, true, true, true, true, false, false],
                 [@worker.start_with?(File.join(@root, '.riddim-worktrees/')),
                  paths.all? { |path| context.include?(path) }, context.include?(GLOBAL),
                  context.include?(PARENT), context.include?(TARGET), context.include?(RUNTIME),
                  context.include?(File.join(@runtime, 'AGENTS.md'))]
  end
end
