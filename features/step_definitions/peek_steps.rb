# frozen_string_literal: true

Given('a Herdr executable that answers a pane read with 250 lines') do
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['pane', 'read'] then puts (1..250).map { |number| format('pane-%03d', number) }
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

Given('Herdr fails the pane read with status {int} and error {string}') do |status, error|
  install_fake_herdr(<<~RUBY)
    case ARGV[0, 2]
    when ['pane', 'read'] then puts 'partial tail'; warn #{error.dump}; exit #{status}
    else abort "unexpected invocation: \#{ARGV.join(' ')}"
    end
  RUBY
end

# The fake answers a pane read with 250 numbered lines, so a passing tail
# must be exactly the final <count> of them, trimmed in Riddim itself.
Then('standard output is the final {int} lines of the pane read') do |count|
  total = 250
  expected = ((total - count + 1)..total).map { |number| format('pane-%03d', number) }

  assert_equal "#{expected.join("\n")}\n", @stdout
end

Then('standard output is the whole pane read') do
  expected = (1..250).map { |number| format('pane-%03d', number) }

  assert_equal "#{expected.join("\n")}\n", @stdout
end

Then('the missing record refusal is explained for {string}') do |name|
  assert_equal "riddim: no endpoint record exists at #{scenario_record_path(name)}\n", @stderr
end

Then('the unreadable record refusal is explained for {string}') do |name|
  reason = 'unreadable endpoint record line "not a record"'
  expected = "riddim: the endpoint record for #{name} at #{scenario_record_path(name)} is unreadable: #{reason}\n"

  assert_equal expected, @stderr
end

Then('the symlinked record refusal is explained for {string}') do |name|
  assert_equal "riddim: the endpoint record at #{scenario_record_path(name)} is a symbolic link\n", @stderr
end

Then('the inconsistent window refusal is explained for {string}') do |name|
  expected = "riddim: the endpoint record for #{name} records window \"riddim:w9:p2\", not \"riddim:w9:p1\"\n"

  assert_equal expected, @stderr
end
