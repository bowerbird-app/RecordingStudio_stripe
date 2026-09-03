# frozen_string_literal: true

require "test_helper"

class StartPortalSessionTest < Minitest::Test
  Root = Struct.new(:id)
  FakeCustomer = Struct.new(:stripe_id)

  def setup
    @original_configuration = RecordingStudioStripe.instance_variable_get(:@configuration)
    RecordingStudioStripe.instance_variable_set(:@configuration, RecordingStudioStripe::Configuration.new)
    @original_customer = customer_class
    @root = Root.new(42)
  end

  def teardown
    replace_customer_class(@original_customer)
    RecordingStudioStripe.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_local_mode_returns_unavailable
    result = RecordingStudioStripe::StartPortalSession.call(
      root_recording: @root,
      return_url: "http://example.test/billing"
    )

    assert_equal "http://example.test/billing", result[:url]
    assert_equal true, result[:local]
    assert_equal true, result[:unavailable]
  end

  def test_raises_when_there_is_no_customer
    RecordingStudioStripe.configuration.client = RecordingStudioStripe::Testing::Client.new
    install_customer_class(nil)

    error = assert_raises(RecordingStudioStripe::NoCustomer) do
      RecordingStudioStripe::StartPortalSession.call(
        root_recording: @root,
        return_url: "http://example.test/billing"
      )
    end

    assert_kind_of RecordingStudioStripe::Error, error
  end

  def test_creates_a_portal_session_through_the_client
    RecordingStudioStripe.configuration.client = RecordingStudioStripe::Testing::Client.new
    install_customer_class(FakeCustomer.new("cus_test"))

    result = RecordingStudioStripe::StartPortalSession.call(
      root_recording: @root,
      return_url: "http://example.test/billing"
    )

    assert_match %r{\Ahttps://billing.stripe.test/session/}, result[:url]
    refute result[:local]
    refute result[:unavailable]
  end

  private

  def customer_class
    return unless RecordingStudioStripe.const_defined?(:Customer, false)

    RecordingStudioStripe.const_get(:Customer, false)
  end

  def install_customer_class(record)
    fake = Class.new do
      define_singleton_method(:find_by) { |**_| record }
    end
    replace_customer_class(fake)
  end

  def replace_customer_class(klass)
    RecordingStudioStripe.send(:remove_const, :Customer) if RecordingStudioStripe.const_defined?(:Customer, false)
    RecordingStudioStripe.const_set(:Customer, klass) if klass
  end
end
