# frozen_string_literal: true

module Riddim
  # The composer-typing surface of Riddim::Herdr: one literal line into a
  # proven-empty composer, one named key, and the composer-verified submit
  # loop. This is the control plane's mechanics only: no caller may submit
  # arbitrary text, and nothing here is a generic raw-key entry point.
  module Herdr
    # Firstmate's submit-core timing: the settle after a literal send, and the
    # bounded Enter retries (FM_CONTROL_EXIT_RETRIES default).
    SUBMIT_SETTLE = 1.2
    SUBMIT_RETRIES = 3

    module_function

    # Firstmate's fm_backend_herdr_send_literal: TEXT as literal, unsubmitted
    # composer input - the caller sends Enter separately. Herdr's `pane
    # send-text` does not auto-submit.
    def send_literal(pane_id, text, session: nil)
      stdout, stderr, status = capture('pane', 'send-text', pane_id, text, session: session)
      raise CommandFailed.new(stdout, stderr, status) unless status.success?
    end

    # Firstmate's key vocabulary onto herdr's `pane send-keys` names,
    # normalized explicitly rather than relying on herdr's case-insensitivity.
    def send_key(pane_id, key, session: nil)
      stdout, stderr, status = capture('pane', 'send-keys', pane_id, normalize_key(key), session: session)
      raise CommandFailed.new(stdout, stderr, status) unless status.success?
    end

    def normalize_key(key)
      case key
      when 'Enter' then 'enter'
      when 'Escape' then 'escape'
      else key
      end
    end

    # The composer-verified submit: type the line ONCE, settle, then retry
    # Enter only - never retype - while the composer still reads pending. The
    # verdicts: :empty is a composer that cleared (positive delivery), :pending
    # is proven text the Enter failed to submit, :unknown is a composer that
    # stopped being classifiable (possibly destroyed), and :send_failed means
    # nothing was typed at all. The caller's postcondition is authoritative.
    def submit_line(pane_id, text, session:)
      send_literal(pane_id, text, session: session)
      sleep SUBMIT_SETTLE

      enter_until_cleared(pane_id, session: session)
    end

    def enter_until_cleared(pane_id, session:)
      enter_sent = false
      verdict = :pending
      1.upto(SUBMIT_RETRIES) do
        state = deliver_enter_key(pane_id, session: session, enter_sent: enter_sent)
        return :send_failed if state == :send_failed

        enter_sent = true
        verdict = composer_verdict_for_submit(pane_id, session: session)
        return verdict unless verdict == :pending
      end
      verdict
    end

    # One Enter delivery: :send_failed when no Enter ever reached the pane, or
    # :attempted when the key was delivered now, or earlier with the retry send
    # failing - either way the composer verdict, not the delivery, decides.
    def deliver_enter_key(pane_id, session:, enter_sent:)
      send_key(pane_id, 'Enter', session: session)
      :attempted
    rescue CommandFailed
      enter_sent ? :attempted : :send_failed
    end

    def composer_verdict_for_submit(pane_id, session:)
      case composer_state(pane_id, session: session)
      when :empty then :empty
      when :pending then :pending
      else :unknown
      end
    end
  end
end
