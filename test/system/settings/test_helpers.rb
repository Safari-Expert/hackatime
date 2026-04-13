module SettingsSystemTestHelpers
  private

  def assert_settings_page(path:, marker_text:, card_count: 1)
    visit path

    assert_current_path path, ignore_query: true
    assert_text "Settings"
    assert_text marker_text
    assert_selector "[data-settings-shell]"
    assert_selector "[data-settings-content]"
    assert_selector "[data-settings-card]", minimum: card_count
  end

  def choose_select_option(select_id, option_text)
    trigger = find("##{select_id}", visible: true)
    trigger.click

    popover = find(".dashboard-select-popover[data-state='open']", visible: true)

    within(popover) do
      option_matcher = Regexp.new("\\A#{Regexp.escape(option_text)}")
      find("[role='option']", text: option_matcher, match: :first, visible: true).click
    end

    assert_no_selector ".dashboard-select-popover[data-state='open']"
    assert_selector "##{select_id}", text: option_text
  end

  def within_modal(&)
    within ".bits-modal-content", &
  end

  def wait_for_record_attribute(record, attribute, expected, timeout: Capybara.default_max_wait_time)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      actual = record.reload.public_send(attribute)
      return actual if actual == expected

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise Minitest::Assertion, "Expected #{record.class}##{attribute} to become #{expected.inspect}, got #{actual.inspect}"
      end

      sleep 0.05
    end
  end
end
