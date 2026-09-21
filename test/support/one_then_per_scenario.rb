# frozen_string_literal: true

# Enforces one observable outcome per English-language Gherkin scenario.
module OneThenPerScenario
  Section = Struct.new(:type, :name, :line, :outcomes, keyword_init: true)

  module_function

  def call(source, path:)
    Scanner.new(source, path).call
  end

  # Scans the small subset of Gherkin needed to count scenario outcomes.
  class Scanner
    def initialize(source, path)
      @source = source
      @path = path
      @violations = []
      @section = nil
      @phase = nil
    end

    def call
      @source.each_line.with_index(1) { |line, number| consume(line.strip, number) }
      finish_section
      @violations
    end

    private

    def consume(text, line_number)
      return if text.empty? || text.start_with?('#')

      heading = section_heading(text, line_number)
      return start_section(heading) if heading

      count_outcome(text)
    end

    def start_section(heading)
      finish_section
      @section = heading
      @phase = nil
    end

    def finish_section
      @violations.concat(lint(@section)) if @section
    end

    def section_heading(text, line_number)
      return background(line_number) if text.match?(/\ABackground:/)

      scenario(text, line_number)
    end

    def background(line_number)
      Section.new(type: :background, name: nil, line: line_number, outcomes: 0)
    end

    def scenario(text, line_number)
      match = text.match(/\A(?:Scenario(?: Outline| Template)?|Example):\s*(.*)\z/)
      return unless match

      Section.new(type: :scenario, name: match[1], line: line_number, outcomes: 0)
    end

    def count_outcome(text)
      keyword = text[/\A(Given|When|Then|And|But|\*)(?:\s|\z)/, 1]
      return unless @section && keyword

      @phase = keyword unless %w[And But *].include?(keyword)
      @section.outcomes += 1 if @phase == 'Then'
    end

    def lint(section)
      return lint_background(section) if section.type == :background
      return [] if section.outcomes == 1

      ["#{location(section)}: Scenario \"#{section.name}\" must have exactly one Then step; found #{section.outcomes}"]
    end

    def lint_background(section)
      return [] if section.outcomes.zero?

      ["#{location(section)}: Background must not have Then steps; found #{section.outcomes}"]
    end

    def location(section)
      "#{@path}:#{section.line}"
    end
  end
end
