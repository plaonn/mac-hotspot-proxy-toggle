# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/hotspot-proxy-toggle/proxy"

class ProxyTest < Minitest::Test
  class FakeSettings
    attr_reader :states
    attr_accessor :fail_type

    def initialize
      @states = {
        "socksfirewall" => [false, "previous", "1081", "0"],
        "web" => [true, "office", "8080", "1"],
        "secureweb" => [true, "office", "8443", "0"]
      }
    end

    def read(_service, type)
      @states.fetch(type).dup
    end

    def endpoint(_service, type, host, port)
      @states[type] = [true, host, port, "0"]
      raise "interrupted after write" if type == fail_type
    end

    def toggle(_service, type, enabled)
      @states[type][0] = enabled
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "session.json")
    @system = FakeSettings.new
    @baseline = Marshal.load(Marshal.dump(@system.states))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def session
    HotspotProxy::Session.new(@path, @system)
  end

  def activate
    session.apply("Wi-Fi", "socks5", "router", "1080")
  end

  def test_repeated_checks_and_restart_preserve_original_settings
    assert activate
    refute activate
    assert session.apply("Wi-Fi", "socks5", "next-router", "1080")
    assert session.matches?("Wi-Fi", "socks5", "next-router", "1080")
    assert session.restore
    assert_equal @baseline, @system.states
    refute File.exist?(@path)
    refute session.restore
  end

  def test_restore_leaves_external_edits_intact
    activate
    @system.endpoint("Wi-Fi", "socksfirewall", "user-choice", "1099")
    assert_raises(HotspotProxy::Session::ExternalChange) { activate }
    session.restore
    assert_equal "user-choice", @system.states["socksfirewall"][1]
    assert_equal @baseline["web"], @system.states["web"]
  end

  def test_interrupted_command_can_restore_or_resume
    @system.fail_type = "socksfirewall"
    assert_raises(RuntimeError) { activate }
    @system.fail_type = nil
    assert session.restore
    assert_equal @baseline, @system.states
  end

  def test_authenticated_endpoint_is_preserved
    assert_raises(HotspotProxy::Session::ProtectedEndpoint) { session.apply("Wi-Fi", "http", "router", "80") }
    assert_equal @baseline, @system.states
    refute File.exist?(@path)
  end

  def test_http_backend_and_previously_empty_fields
    @system.states["web"] = [false, "", "0", "0"]
    assert session.apply("Wi-Fi", "http", "router", "80")
    assert session.matches?("Wi-Fi", "http", "router", "80")
    session.restore
    refute @system.states["web"][0]
    assert_equal @baseline["secureweb"], @system.states["secureweb"]
  end

  def serve(protocol, response)
    TCPServer.open("127.0.0.1", 0) do |server|
      thread = Thread.new do
        client = server.accept
        begin
          protocol == "http" ? client.gets("\r\n\r\n") : client.read(3)
          response.each do |part|
            client.write(part)
            sleep 0.04
          end
        ensure
          client.close
        end
      end
      result = HotspotProxy.probe(protocol, "127.0.0.1", server.addr[1], 1)
      thread.value
      result
    end
  end

  def test_split_and_partial_greetings
    assert_equal "ready", serve("socks5", ["\x05", "\x00"])
    assert_equal "unexpected_response", serve("socks5", ["\x05"])
    assert_equal "authentication_required", serve("socks5", ["\x05\x02"])
  end

  def test_http_status
    assert_equal "authentication_required", serve("http", ["HTTP/1.1 407 Auth Required\r\n"])
    assert_equal "ready", serve("http", ["HTTP/1.1 204 No Content\r\n"])
    assert_equal "unexpected_response", serve("http", ["invalid\r\n"])
  end
end
