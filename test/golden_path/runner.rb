#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "capybara"
require "fileutils"
require "open3"
require "optparse"
require "securerandom"
require "selenium-webdriver"
require "time"
require "uri"

class GoldenPathRunner
  SCREENSHOT_DIR = File.expand_path("../../tmp/golden_path", __dir__)

  def self.call(...)
    new(...).call
  end

  def initialize(base_url:, container:)
    @base_url = validate_base_url(base_url)
    @container = validate_container(container)
    @run_id = "#{Time.now.utc.strftime("%Y%m%d%H%M%S")}-#{SecureRandom.hex(4)}"
    @email = "golden-path-#{@run_id}@example.test"
    @full_name = "Golden Path"
    @board_name = "Golden Path Board #{@run_id}"
    @card_title = "Golden Path Card #{@run_id}"
    @card_description = "Created by the Docker golden path."
    @session = build_session
  end

  def call
    step "Open signup"
    visit "/signup/new"
    assert_selector "h1", text: "Sign up"

    step "Register #{@email}"
    fill_in "signup_email_address", with: @email
    click_button "log_in"
    assert_selector "h1", text: "Check your email"

    step "Verify magic code"
    fill_in "code", with: latest_magic_code
    find("#code").send_keys(:enter)
    assert_selector "h1", text: "Complete your sign-up"

    step "Complete signup"
    fill_in "signup_full_name", with: @full_name
    click_button "Continue"
    wait_for_account_scope
    visit_account_path "/"
    assert_selector "body", text: "Add a board"

    step "Create board"
    click_on "Add a board", match: :first
    assert_selector "h1", text: "Create a new board"
    fill_in "board_name", with: @board_name
    click_button "Create board"
    assert_selector "body", text: @board_name

    step "Create card"
    click_on "Add a card", match: :first
    assert_selector "#card_title"
    fill_in "card_title", with: @card_title
    fill_in_lexxy with: @card_description
    click_button "Create card"
    assert_selector "h3", text: @card_title

    step "Verify database records"
    puts verify_backend_records

    puts "Golden path passed for #{@email}"
  rescue StandardError => error
    save_failure_artifacts
    raise error
  ensure
    @session&.driver&.quit
  end

  private
    attr_reader :session

    def validate_base_url(value)
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTP) && %w[ 127.0.0.1 localhost ].include?(uri.host)
        raise ArgumentError, "base URL must be http://127.0.0.1 or http://localhost"
      end

      value.delete_suffix("/")
    rescue URI::InvalidURIError
      raise ArgumentError, "base URL is invalid"
    end

    def validate_container(value)
      unless value.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}\z/)
        raise ArgumentError, "container name is invalid"
      end

      value
    end

    def build_session
      browser_options = Selenium::WebDriver::Chrome::Options.new.tap do |opts|
        opts.add_argument("--window-size=1200,900")
        opts.add_argument("--disable-extensions")
        opts.add_argument("--disable-renderer-backgrounding")
        opts.add_argument("--disable-backgrounding-occluded-windows")
        opts.add_argument("--deny-permission-prompts")
        opts.add_argument("--enable-automation")
        opts.add_argument("--headless") unless ENV["FIZZY_GOLDEN_PATH_BROWSER"] == "headed"
      end

      Capybara.run_server = false
      Capybara.app_host = @base_url
      Capybara.default_max_wait_time = ENV.fetch("FIZZY_GOLDEN_PATH_WAIT", "15").to_i
      Capybara.default_normalize_ws = true

      Capybara.register_driver :golden_path_chrome do |app|
        Capybara::Selenium::Driver.new(app, browser: :chrome, options: browser_options)
      end

      Capybara::Session.new(:golden_path_chrome)
    end

    def latest_magic_code
      script = <<~RUBY
        identity = Identity.find_by!(email_address: ENV.fetch("GOLDEN_PATH_EMAIL"))
        puts identity.magic_links.active.order(created_at: :desc).first!.code
      RUBY

      rails_runner script, "GOLDEN_PATH_EMAIL" => @email
    end

    def verify_backend_records
      script = <<~RUBY
        identity = Identity.find_by!(email_address: ENV.fetch("GOLDEN_PATH_EMAIL"))
        user = identity.users.order(created_at: :desc).first!
        account = user.account
        board = account.boards.find_by!(name: ENV.fetch("GOLDEN_PATH_BOARD"))
        card = board.cards.find_by!(title: ENV.fetch("GOLDEN_PATH_CARD"))
        raise "Expected card to be published" unless card.published?

        puts "account=\#{account.external_account_id} board=\#{board.id} card=\#{card.number}"
      RUBY

      rails_runner script,
        "GOLDEN_PATH_EMAIL" => @email,
        "GOLDEN_PATH_BOARD" => @board_name,
        "GOLDEN_PATH_CARD" => @card_title
    end

    def rails_runner(script, env = {})
      command = [ "docker", "exec" ]
      env.each do |key, value|
        command.concat [ "-e", "#{key}=#{value}" ]
      end
      command.concat [ @container, "./bin/rails", "runner", script ]

      stdout, stderr, status = Open3.capture3(*command)
      unless status.success?
        output = stderr.empty? ? stdout : stderr
        raise "rails runner failed: #{output}"
      end

      stdout.strip
    end

    def account_path_prefix
      path = URI.parse(session.current_url).path
      match = path.match(%r{\A/[^/]+})
      raise "Expected account-scoped URL, got #{session.current_url}" unless match && account_slug?(match[0].delete_prefix("/"))

      match[0]
    end

    def wait_for_account_scope
      deadline = Time.now + Capybara.default_max_wait_time

      loop do
        path = URI.parse(session.current_url).path
        slug = path.split("/")[1]
        return if account_slug?(slug)

        break if Time.now >= deadline

        sleep 0.1
      end

      raise "Expected redirect to account scope, got #{session.current_url}"
    end

    def visit_account_path(path)
      visit "#{account_path_prefix}#{path}"
    end

    def account_slug?(slug)
      slug && !%w[ signup session up manifest.json ].include?(slug)
    end

    def visit(path)
      session.visit path
    end

    def assert_selector(*args, **kwargs)
      return if session.has_selector?(*args, **kwargs)

      raise "Expected selector #{args.inspect} #{kwargs.inspect} on #{session.current_url}"
    end

    def fill_in(...)
      session.fill_in(...)
    end

    def click_button(...)
      session.click_button(...)
    end

    def click_on(...)
      session.click_on(...)
    end

    def find(...)
      session.find(...)
    end

    def fill_in_lexxy(selector = "lexxy-editor", with:)
      editor = find(selector)
      editor.set with
      session.execute_script("arguments[0].value = arguments[1]", editor, with)
    end

    def step(message)
      puts "==> #{message}"
    end

    def save_failure_artifacts
      FileUtils.mkdir_p SCREENSHOT_DIR

      timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
      screenshot = File.join(SCREENSHOT_DIR, "failure-#{timestamp}.png")
      html = File.join(SCREENSHOT_DIR, "failure-#{timestamp}.html")

      session.save_screenshot screenshot
      File.write html, session.html

      warn "Saved failure screenshot: #{screenshot}"
      warn "Saved failure HTML: #{html}"
    rescue StandardError => artifact_error
      warn "Could not save failure artifacts: #{artifact_error.message}"
    end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: test/golden_path/runner.rb --base-url URL --container NAME"
  parser.on("--base-url URL", "Local URL for the running Fizzy container") { |value| options[:base_url] = value }
  parser.on("--container NAME", "Docker container name to inspect for one-time codes") { |value| options[:container] = value }
end.parse!

missing = %i[ base_url container ].reject { |key| options[key] }
unless missing.empty?
  warn "Missing required options: #{missing.join(", ")}"
  exit 64
end

GoldenPathRunner.call(**options)
