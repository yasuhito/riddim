# frozen_string_literal: true

require 'json'
require 'socket'
require 'timeout'

module PiStallLab
  # Single-connection local OpenAI-compatible test server. Never logs requests.
  module LabServer
    module_function

    def config(root, port)
      model = { id: 'test', contextWindow: 128_000, maxTokens: 64 }
      provider = { baseUrl: "http://127.0.0.1:#{port}/v1", api: 'openai-completions', apiKey: 'dummy',
                   models: [model] }
      File.write(File.join(root, 'models.json'), JSON.generate(providers: { 'stall-lab' => provider }),
                 mode: 'w', perm: 0o600)
    end

    def receive_request(server)
      socket = Timeout.timeout(20) { server.accept }
      line = Timeout.timeout(10) { socket.gets }
      raise 'unexpected API request' unless line&.start_with?('POST /v1/chat/completions ')

      read_body(socket)
      socket
    rescue StandardError
      socket&.close
      raise
    end

    def read_body(socket)
      headers = {}
      Timeout.timeout(10) do
        while (header = socket.gets) && header != "\r\n"
          key, value = header.split(':', 2)
          headers[key.downcase] = value.strip if value
        end
        length = headers.fetch('content-length', '0').to_i
        raise 'unexpectedly large request' if length > 2_000_000

        socket.read(length) if length.positive? # Never log request bodies or credentials.
      end
    end

    def send_ok(socket)
      chunk = { id: 'stall-lab', object: 'chat.completion.chunk', created: 0, model: 'test',
                choices: [{ index: 0, delta: { role: 'assistant', content: 'OK' }, finish_reason: 'stop' }] }
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n")
      socket.write("data: #{JSON.generate(chunk)}\n\ndata: [DONE]\n\n")
      socket.flush
    end

    # Sends only static HTTP 200 event-stream headers and keeps the connection
    # open. No SSE body follows until the caller closes the socket. Header
    # values are constants and are never logged.
    def send_headers_only(socket)
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n")
      socket.flush
    end
  end
end
