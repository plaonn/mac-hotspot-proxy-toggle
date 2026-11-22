# Run the installed-style CLI and event helper with a loopback proxy and disposable
# Wi-Fi observations and settings. All system proxy writes terminate in this file.
require "fileutils"
require "json"
require "open3"
require "socket"
require "shellwords"
require "timeout"
require "tmpdir"

if ARGV.first == "networksetup"
  _, key, _service, host, port = ARGV
  path = ENV.fetch("TEST_SETTINGS")
  states = JSON.parse(File.read(path))
  match = /\A-(get|set)(socksfirewall|web|secureweb)proxy(state)?\z/.match(key) or abort key
  state = states.fetch(match[2])
  if match[1] == "get"
    puts "Enabled: #{state[0] ? 'Yes' : 'No'}", "Server: #{state[1]}", "Port: #{state[2]}", "Authenticated Proxy Enabled: 0"
  else
    if match[3]
      state[0] = host == "on"
    else
      state.replace([true, host, port])
    end
    File.open(path + ".writes", "a") { |log| log.puts(key) }
    File.write(path + ".tmp", JSON.generate(states))
    File.rename(path + ".tmp", path)
  end
  exit
end

def wait_for
  Timeout.timeout(12) { sleep 0.04 until yield }
end

Dir.mktmpdir do |dir|
  root = File.expand_path("..", __dir__)
  FileUtils.mkdir_p(["#{dir}/bin", "#{dir}/lib/hotspot-proxy-toggle"])
  cli = "#{dir}/bin/hotspot-proxy-toggle"
  lib = "#{dir}/lib/hotspot-proxy-toggle/proxy.rb"
  adapter = "#{dir}/networksetup"
  File.write(adapter, "#!/bin/bash\nexec /usr/bin/ruby \"$TEST_DRIVER\" networksetup \"$@\"\n")
  File.chmod(0o755, adapter)
  File.write(lib, File.read("#{root}/lib/hotspot-proxy-toggle/proxy.rb").sub('"/usr/sbin/networksetup"', adapter.inspect))
  # Replace only the OS access points. The entry point, lock, routing decision,
  # protocol exchange, journal and readback all run unchanged.
  stubs = <<~'SH'
    default_interface() { printf 'en0\n'; }
    ipconfig_summary() { cat "$TEST_WIFI"; }
  SH
  entry = 'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then'
  source = File.read("#{root}/bin/hotspot-proxy-toggle").gsub("/usr/sbin/networksetup") { Shellwords.escape(adapter) }
  File.write(cli, source.sub(entry) { stubs + "\n" + entry })
  File.chmod(0o755, cli)
  port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
  wifi = "#{dir}/wifi"
  hotspot = "SSID : TestPhone\nRouter : 127.0.0.1\nConnectionID : one\n"
  File.write(wifi, hotspot)
  state = "#{dir}/ui.json"
  settings = "#{dir}/settings"
  baseline = { "socksfirewall" => [false, "old", "1081"], "web" => [true, "office", "8080"], "secureweb" => [false, "office", "443"] }
  File.write(settings, JSON.generate(baseline))
  config = "#{dir}/config"
  File.write(config, "HOTSPOT_SSID=TestPhone\nNETWORK_SERVICE=Wi-Fi\nWIFI_DEVICE=en0\nPROXY_TYPE=socks5\nPROXY_PORT=#{port}\nPROXY_CHECK_TIMEOUT=3\nNOTIFY_ON_CHANGE=0\nDRY_RUN=0\n")
  env = { "TEST_DRIVER" => File.expand_path(__FILE__), "TEST_SETTINGS" => settings,
          "TEST_WIFI" => wifi, "HOTSPOT_PROXY_CONFIG" => config, "HOTSPOT_PROXY_LOG" => "#{dir}/log",
          "HOTSPOT_PROXY_RUNTIME_DIR" => "#{dir}/managed", "HOTSPOT_PROXY_UI_STATE" => state }
  run = lambda do |arg|
    out, rc = Open3.capture2e(env, cli, arg)
    raise "#{arg} failed: #{out}" unless rc.success?
    out
  end
  kind = lambda { JSON.parse(File.read(state)).fetch("kind") if File.exist?(state) }
  helper = Process.spawn(env, ARGV.fetch(0), "--command", cli, "--identity", "#{dir}/identity/id",
    "--watchdog", "0.2", "--debounce", "0.02", "--max-runs", "30", "--window", "2", out: "#{dir}/helper.log", err: [:child, :out])
  begin
    wait_for { kind.call == "unavailable" }
    server = TCPServer.new("127.0.0.1", port)
    # The server appears without any new network or Wi-Fi identity event.
    Timeout.timeout(12) do
      client = server.accept
      raise "bad greeting" unless client.read(3) == "\x05\x01\x00"
      client.write("\x05")
      sleep 0.05
      client.write("\x00")
      client.close
    end
    wait_for { kind.call == "on" }
    server.close
    wait_for { kind.call == "unavailable" }
  ensure
    Process.kill("TERM", helper)
    Process.wait(helper)
    server.close if server && !server.closed?
  end
  raise "automatic restore failed" unless JSON.parse(File.read(settings)) == baseline

  TCPServer.open("127.0.0.1", port) do |manual|
    reply = lambda do |before_reply = nil|
      Thread.new do
        Timeout.timeout(8) do
          peer = manual.accept
          peer.read(3)
          before_reply.call if before_reply
          peer.write("\x05\x00")
          peer.close
        end
      end
    end
    t = reply.call
    raise "manual reconnect failed" unless run.call("run").include?("ui_state=on")
    t.value
    raise "manual state not applied" unless JSON.parse(File.read(settings))["socksfirewall"] == [true, "127.0.0.1", port.to_s]
    t = reply.call(lambda { File.write(wifi, hotspot.sub("TestPhone", "Other")) })
    run.call("run")
    t.value
    raise "late result applied" unless kind.call == "idle" && JSON.parse(File.read(settings)) == baseline

    File.write(wifi, hotspot)
    writes = File.read(settings + ".writes")
    accepted = Queue.new
    t = reply.call(lambda { accepted << true; sleep 0.15 })
    attempt = Thread.new { run.call("run") }
    Timeout.timeout(8) { accepted.pop }
    run.call("stop")
    t.value
    attempt.value
    run.call("run")
    raise "wrote proxy during cancelled probe" unless File.read(settings + ".writes") == writes
    raise "late result after stop" unless kind.call == "off" && JSON.parse(File.read(settings)) == baseline
    run.call("resume")
    t = reply.call
    raise "resume failed" unless run.call("run").include?("ui_state=on")
    t.value
    run.call("off")
  end
  puts "ok - late server, automatic and manual reconnect, route change during probe, stop during probe, resume and baseline restore"
end
