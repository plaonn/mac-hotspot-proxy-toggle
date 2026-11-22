# frozen_string_literal: true

require "json"
require "open3"
require "socket"
require "timeout"
require "tempfile"

module HotspotProxy
  TYPES = %w[socksfirewall web secureweb].freeze

  # The deadline covers the entire exchange, including a partial response.
  def self.probe(protocol, host, port, seconds)
    Timeout.timeout(seconds) do
      TCPSocket.open(host, port) do |socket|
        if protocol == "socks5"
          socket.write("\x05\x01\x00")
          response = socket.read(2)
          return "ready" if response == "\x05\x00"
          return "authentication_required" if response == "\x05\x02"
        else
          socket.write("GET http://127.0.0.1/ HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
          line = socket.gets("\n", 4096)
          code = line && line[/\AHTTP\/\d+\.\d+ (\d{3})(?:\s|$)/, 1]
          return "authentication_required" if code == "407"
          return "ready" if code
        end
        "unexpected_response"
      end
    end
  rescue Timeout::Error, Errno::ETIMEDOUT
    "timeout"
  rescue SystemCallError, IOError, SocketError
    "connection_failed"
  end

  class NetworkSetup
    def command(*args)
      output, status = Open3.capture2e("/usr/sbin/networksetup", *args)
      raise "macOS proxy operation failed" unless status.success? && !output.include?("** Error:")
      output
    end

    def read(service, type)
      fields = command("-get#{type}proxy", service).lines.map { |line| line.chomp.split(": ", 2) }.to_h
      enabled = { "Yes" => true, "No" => false }.fetch(fields.fetch("Enabled"))
      [enabled, fields.fetch("Server"), fields.fetch("Port"), fields.fetch("Authenticated Proxy Enabled")]
    end

    def endpoint(service, type, host, port)
      command("-set#{type}proxy", service, host, port, "off")
    end

    def toggle(service, type, enabled)
      command("-set#{type}proxystate", service, enabled ? "on" : "off")
    end
  end

  # A write-ahead record preserves the baseline across repeated runs and crashes.
  # Each backend is restored only while it still matches a write we recorded.
  class Session
    class ExternalChange < StandardError; end
    class ProtectedEndpoint < StandardError; end

    def initialize(path, system = NetworkSetup.new, dry_run = false)
      @path, @system, @dry_run = path, system, dry_run
      @journal = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      @changed = false
    end

    def desired(current, type, protocol, host, port)
      selected = protocol == "socks5" ? type == "socksfirewall" : type != "socksfirewall"
      selected ? [true, host, port, "0"] : [false, *current.drop(1)]
    end

    def matches?(service, protocol, host, port)
      TYPES.all? do |type|
        state = @system.read(service, type)
        state == desired(state, type, protocol, host, port)
      end
    end

    def apply(service, protocol, host, port)
      restore if @journal.any? && @journal.fetch("service") != service
      states = TYPES.map { |type| [type, @system.read(service, type)] }.to_h
      goals = states.map { |type, state| [type, desired(state, type, protocol, host, port)] }.to_h
      @journal = { "service" => service, "entries" => {} } if @journal.empty?
      entries = @journal.fetch("entries")

      TYPES.each do |type|
        state, goal, entry = states.fetch(type), goals.fetch(type), entries[type]
        raise ExternalChange, "proxy settings changed outside the app" if entry && !owned?(entry, state)
        if state[3] != "0" && state.drop(1) != goal.drop(1)
          raise ProtectedEndpoint, "existing authenticated endpoint cannot be replaced safely"
        end
      end

      TYPES.each do |type|
        state, goal = states.fetch(type), goals.fetch(type)
        entry = entries[type] ||= { "before" => state, "last" => state }
        move(service, type, entry, state, goal)
      end
      raise "proxy readback mismatch" unless @dry_run || matches?(service, protocol, host, port)
      @changed
    end

    def restore
      return false if @journal.empty?
      service = @journal.fetch("service")
      entries = @journal.fetch("entries")
      entries.keys.each do |type|
        raise "unknown proxy type in saved state" unless TYPES.include?(type)
        entry = entries.fetch(type)
        state = @system.read(service, type)
        if owned?(entry, state)
          goal = entry.fetch("before")
          # networksetup cannot clear a dormant, never-configured host and port.
          goal = [false, *state.drop(1)] if !goal[0] && (goal[1].empty? || goal[2] == "0")
          move(service, type, entry, state, goal)
        end
        entries.delete(type)
        save
      end
      File.unlink(@path) if !@dry_run && File.exist?(@path)
      @journal = {}
      @changed
    end

    private

    def owned?(entry, state)
      [entry.fetch("last"), entry["pending"]].include?(state)
    end

    def move(service, type, entry, state, goal)
      if state.drop(1) != goal.drop(1)
        after_endpoint = [true, *goal.drop(1)]
        step(service, type, entry, after_endpoint) { @system.endpoint(service, type, goal[1], goal[2]) }
        state = after_endpoint
      end
      if state[0] != goal[0]
        step(service, type, entry, goal) { @system.toggle(service, type, goal[0]) }
      end
      if entry.key?("pending")
        entry["last"] = goal
        entry.delete("pending")
        save
      end
    end

    def step(service, type, entry, goal)
      @changed = true
      return if @dry_run
      entry["pending"] = goal
      save
      yield
      raise "proxy state readback mismatch" unless @system.read(service, type) == goal
      entry["last"] = goal
      entry.delete("pending")
      save
    end

    def save
      return if @dry_run
      Tempfile.create([".proxy-session", ".json"], File.dirname(@path)) do |file|
        file.write(JSON.generate(@journal))
        file.flush
        file.fsync
        File.rename(file.path, @path)
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  action = ARGV.shift
  begin
    if action == "probe"
      protocol, host, port, timeout = ARGV
      puts HotspotProxy.probe(protocol, host, Integer(port, 10), Integer(timeout, 10))
    else
      path, service, protocol, host, port, dry_run = ARGV
      session = HotspotProxy::Session.new(path, HotspotProxy::NetworkSetup.new, dry_run == "1")
      case action
      when "matches" then exit(session.matches?(service, protocol, host, port) ? 0 : 1)
      when "apply" then puts(session.apply(service, protocol, host, port) ? "changed" : "unchanged")
      when "restore" then puts(session.restore ? "changed" : "unchanged")
      else abort "unknown proxy operation"
      end
    end
  rescue StandardError => error
    case error
    when HotspotProxy::Session::ExternalChange then puts "external_change"
    when HotspotProxy::Session::ProtectedEndpoint then puts "protected_endpoint"
    end
    warn error.message
    exit 1
  end
end
