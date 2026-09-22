# frozen_string_literal: true

Given('Herdr returns agent JSON for pane {string}:') do |pane, json|
  install_fake_herdr(<<~RUBY)
    expected = ['agent', 'get', #{pane.dump}]
    abort "unexpected arguments: \#{ARGV.join(' ')}" unless ARGV == expected
    puts #{json.dump}
  RUBY
end

Given('the recorded agent read fails with status {int}, output {string}, and error {string}') do |status, output, error|
  install_fake_herdr(<<~RUBY)
    abort "unexpected arguments: \#{ARGV.join(' ')}" unless ARGV == %w[agent get w9:p1]
    puts #{output.dump}
    warn #{error.dump}
    exit #{status}
  RUBY
end
